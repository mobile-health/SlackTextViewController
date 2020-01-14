//
//  SlackTextViewController
//  https://github.com/slackhq/SlackTextViewController
//
//  Copyright 2014-2016 Slack Technologies, Inc.
//  Licence: MIT-Licence
//

#import "SLKTextInputbar.h"
#import "SLKTextView.h"
#import "SLKInputAccessoryView.h"

#import "SLKTextView+SLKAdditions.h"
#import "UIView+SLKAdditions.h"

#import "SLKUIConstants.h"

NSString * const SLKTextInputbarDidMoveNotification =   @"SLKTextInputbarDidMoveNotification";

@interface SLKTextInputbar ()

@property (nonatomic, strong) NSLayoutConstraint *textViewBottomMarginC;
@property (nonatomic, strong) NSLayoutConstraint *contentViewHC;
@property (nonatomic, strong) NSLayoutConstraint *rightButtonWC;
@property (nonatomic, strong) NSLayoutConstraint *rightMarginWC;
@property (nonatomic, strong) NSLayoutConstraint *editorContentViewHC;
@property (nonatomic, strong) NSArray *charCountLabelVCs;

@property (nonatomic, strong) UILabel *charCountLabel;
@property (nonatomic, strong) UIView *buttonsView;

@property (nonatomic) CGPoint previousOrigin;

@property (nonatomic, strong) Class textViewClass;

@property (nonatomic, getter=isHidden) BOOL hidden; // Required override

@property (nonatomic) BOOL isExpanding;

@end

@implementation SLKTextInputbar
@synthesize textView = _textView;
@synthesize contentView = _contentView;
@synthesize inputAccessoryView = _inputAccessoryView;
@synthesize hidden = _hidden;

#pragma mark - Initialization

- (instancetype)initWithTextViewClass:(Class)textViewClass
{
    if (self = [super init]) {
        self.textViewClass = textViewClass;
        [self slk_commonInit];
    }
    return self;
}

- (id)init
{
    if (self = [super init]) {
        [self slk_commonInit];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    if (self = [super initWithCoder:coder]) {
        [self slk_commonInit];
    }
    return self;
}

- (void)slk_commonInit
{
    self.backgroundColor = [UIColor whiteColor];
    self.charCountLabelNormalColor = [UIColor lightGrayColor];
    self.charCountLabelWarningColor = [UIColor redColor];
    
    self.autoHideRightButton = NO;
    self.editorContentViewHeight = 38.0;
    self.toolBarButtonsViewHeight = 44.0;
    self.contentInset = UIEdgeInsetsMake(5.0, 8.0, 0.0, 8.0);

    // Since iOS 11, it is required to call -layoutSubviews before adding custom subviews
    // so private UIToolbar subviews don't interfere on the touch hierarchy
    [self layoutSubviews];

    [self addSubview:self.editorContentView];
    [self addSubview:self.photoButton];
    [self addSubview:self.expandButton];
    [self addSubview:self.textView];
    [self addSubview:self.charCountLabel];
    [self addSubview:self.contentView];
    [self addSubview:self.buttonsView];

    [self slk_setupViewConstraints];
    [self slk_updateConstraintConstants];
    
    self.counterStyle = SLKCounterStyleNone;
    self.counterPosition = SLKCounterPositionTop;
    
    [self slk_registerNotifications];
    
    [self slk_registerTo:self.layer forSelector:@selector(position)];
    [self slk_registerTo:self.photoButton.imageView forSelector:@selector(image)];
    [self slk_registerTo:self.expandButton.titleLabel forSelector:@selector(font)];
}


#pragma mark - UIView Overrides

- (void)updateConstraints {
    [super updateConstraints];
    
    // iOS 11.0 only bug fix.
    for (UIView * subview in [self subviews]) {
        if (![NSStringFromClass([subview class]) isEqualToString:@"_UIToolbarContentView"]) {
            continue;
        }
        // check top constraint.
        NSLayoutConstraint *constraint = [self slk_constraintForAttribute:NSLayoutAttributeTop firstItem:subview secondItem:self];
        
        if (constraint == nil) {
            // check reverse order.
            constraint = [self slk_constraintForAttribute:NSLayoutAttributeTop firstItem:self secondItem:subview];
        }
        
        if (constraint == nil) {
            // no constraint found.
            // this is a bug from iOS 11.0
            // we will add the constraint manually to correct the layout issue.
            NSMutableArray<NSLayoutConstraint *> *newConstraints = [NSMutableArray new];
            
            [newConstraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-[subview]-|"
                                                                                        options:0
                                                                                        metrics:nil
                                                                                          views:NSDictionaryOfVariableBindings(subview)]];
            [newConstraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-[subview]-|"
                                                                                        options:0
                                                                                        metrics:nil
                                                                                          views:NSDictionaryOfVariableBindings(subview)]];
            [NSLayoutConstraint activateConstraints:newConstraints];
            NSString* const systemVersion = [[UIDevice currentDevice] systemVersion];
            // ver >= 11.0 && ver < 11.2
            if ([systemVersion compare:@"11.0" options:NSNumericSearch] != NSOrderedAscending &&
                [systemVersion compare:@"11.2" options:NSNumericSearch] == NSOrderedAscending) {
                subview.transform = CGAffineTransformMakeTranslation(-8, 0);
            }
        }
    }
}

- (void)layoutIfNeeded
{
    if (self.constraints.count == 0 || !self.window) {
        return;
    }
    
    [self slk_updateConstraintConstants];
    [super layoutIfNeeded];
}

- (CGSize)intrinsicContentSize
{
    return CGSizeMake(UIViewNoIntrinsicMetric, [self minimumInputbarHeight]);
}

+ (BOOL)requiresConstraintBasedLayout
{
    return YES;
}


#pragma mark - Getters

- (SLKTextView *)textView
{
    if (!_textView) {
        Class class = self.textViewClass ? : [SLKTextView class];
        
        _textView = [[class alloc] init];
        _textView.translatesAutoresizingMaskIntoConstraints = NO;
        _textView.font = [UIFont systemFontOfSize:15.0];
        _textView.maxNumberOfLines = [self slk_defaultNumberOfLines];
        
        _textView.keyboardType = UIKeyboardTypeTwitter;
        _textView.returnKeyType = UIReturnKeyDefault;
        _textView.enablesReturnKeyAutomatically = YES;
        _textView.scrollIndicatorInsets = UIEdgeInsetsMake(0.0, -1.0, 0.0, 1.0);
        _textView.textContainerInset = UIEdgeInsetsMake(8.0, 4.0, 8.0, 0.0);
        
        /*
        _textView.layer.cornerRadius = 5.0;
        _textView.layer.borderWidth = 0.5;
        _textView.layer.borderColor =  [UIColor colorWithRed:200.0/255.0 green:200.0/255.0 blue:205.0/255.0 alpha:1.0].CGColor;
        */
    }
    return _textView;
}

- (UIView *)contentView
{
    if (!_contentView) {
        _contentView = [UIView new];
        _contentView.translatesAutoresizingMaskIntoConstraints = NO;
        _contentView.backgroundColor = [UIColor clearColor];
        _contentView.clipsToBounds = YES;
    }
    return _contentView;
}

- (SLKInputAccessoryView *)inputAccessoryView
{
    if (!_inputAccessoryView) {
        _inputAccessoryView = [[SLKInputAccessoryView alloc] initWithFrame:CGRectZero];
        _inputAccessoryView.backgroundColor = [UIColor clearColor];
        _inputAccessoryView.userInteractionEnabled = NO;
    }
    
    return _inputAccessoryView;
}

- (UIView *)buttonsView
{
    if (!_buttonsView) {
        _buttonsView = [UIView new];
        _buttonsView.translatesAutoresizingMaskIntoConstraints = NO;
        _buttonsView.backgroundColor = [UIColor whiteColor];
        
        [_buttonsView addSubview: self.stackButtonsView];
        [_buttonsView addSubview: self.submitButton];
        
        NSDictionary *views = @{@"stackButtonsView": self.stackButtonsView,
                                @"submitButton": self.submitButton,
                                };
        
        NSDictionary *metrics = @{@"top" : @(self.contentInset.top),
                                  @"left" : @(self.contentInset.left),
                                  @"bottom" : @(self.contentInset.top),
                                  @"right" : @(self.contentInset.right)
                                  };

        [_buttonsView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-(left)-[stackButtonsView]-(>=right)-[submitButton(60)]-(right)-|" options:0 metrics:metrics views:views]];
        [_buttonsView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-(top)-[stackButtonsView]-(bottom)-|" options:0 metrics:metrics views:views]];
        [_buttonsView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-(top)-[submitButton]-(bottom)-|" options:0 metrics:metrics views:views]];
    }
    return _buttonsView;
}

- (UIStackView* )stackButtonsView
{
    if (!_stackButtonsView) {
        _stackButtonsView = [UIStackView new];
        _stackButtonsView.translatesAutoresizingMaskIntoConstraints = NO;
        _stackButtonsView.axis = UILayoutConstraintAxisHorizontal;
        _stackButtonsView.alignment = UIStackViewAlignmentCenter;
        _stackButtonsView.distribution = UIStackViewDistributionFill;
        _stackButtonsView.spacing = 16.0;

        [_stackButtonsView addArrangedSubview:self.photoButton];
    }
    return _stackButtonsView;
}

- (UIButton *)submitButton
{
    if (!_submitButton) {
        _submitButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _submitButton.translatesAutoresizingMaskIntoConstraints = NO;
        _submitButton.titleLabel.font = [UIFont systemFontOfSize:15.0];
        _submitButton.enabled = NO;

        NSString *title = NSLocalizedString(@"Send", nil);
        [_submitButton setTitle:title forState:UIControlStateNormal];
        
        _submitButton.layer.cornerRadius = 5.0;
        _submitButton.layer.borderWidth = 0.5;
        _submitButton.layer.borderColor =  [UIColor colorWithRed:200.0/255.0 green:200.0/255.0 blue:205.0/255.0 alpha:1.0].CGColor;
    }
    return _submitButton;
}

- (UIButton *)photoButton
{
    if (!_photoButton) {
        _photoButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _photoButton.translatesAutoresizingMaskIntoConstraints = NO;
        _photoButton.titleLabel.font = [UIFont systemFontOfSize:15.0];
    }
    return _photoButton;
}

- (UIButton *)expandButton
{
    if (!_expandButton) {
        _expandButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _expandButton.translatesAutoresizingMaskIntoConstraints = NO;
        [_expandButton addTarget:self action:@selector(expandButtonDidPressed:) forControlEvents:UIControlEventTouchUpInside];
    }
    return _expandButton;
}

-(void)setIsExpanding:(BOOL)isExpanding {
    _isExpanding = isExpanding;
    [self.expandButton setSelected:_isExpanding];
}

- (UIView *)editorContentView
{
    if (!_editorContentView) {
        _editorContentView = [UIView new];
        _editorContentView.translatesAutoresizingMaskIntoConstraints = NO;
        _editorContentView.backgroundColor = self.backgroundColor;
        _editorContentView.clipsToBounds = YES;
        _editorContentView.hidden = YES;
        
        [_editorContentView addSubview:self.editorTitle];
        [_editorContentView addSubview:self.editorLeftButton];
        [_editorContentView addSubview:self.editorRightButton];
        
        NSDictionary *views = @{@"label": self.editorTitle,
                                @"leftButton": self.editorLeftButton,
                                @"rightButton": self.editorRightButton,
                                };
        
        NSDictionary *metrics = @{@"left" : @(self.contentInset.left),
                                  @"right" : @(self.contentInset.right)
                                  };
        
        [_editorContentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-(left)-[leftButton(60)]-(left)-[label(>=0)]-(right)-[rightButton(60)]-(<=right)-|" options:0 metrics:metrics views:views]];
        [_editorContentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[leftButton]|" options:0 metrics:metrics views:views]];
        [_editorContentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[rightButton]|" options:0 metrics:metrics views:views]];
        [_editorContentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[label]|" options:0 metrics:metrics views:views]];
    }
    return _editorContentView;
}

- (UILabel *)editorTitle
{
    if (!_editorTitle) {
        _editorTitle = [UILabel new];
        _editorTitle.translatesAutoresizingMaskIntoConstraints = NO;
        _editorTitle.textAlignment = NSTextAlignmentCenter;
        _editorTitle.backgroundColor = [UIColor clearColor];
        _editorTitle.font = [UIFont boldSystemFontOfSize:15.0];
        
        NSString *title = NSLocalizedString(@"Editing Message", nil);
        _editorTitle.text = title;
    }
    return _editorTitle;
}

- (UIButton *)editorLeftButton
{
    if (!_editorLeftButton) {
        _editorLeftButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _editorLeftButton.translatesAutoresizingMaskIntoConstraints = NO;
        _editorLeftButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        _editorLeftButton.titleLabel.font = [UIFont systemFontOfSize:15.0];
        
        NSString *title = NSLocalizedString(@"Cancel", nil);
        [_editorLeftButton setTitle:title forState:UIControlStateNormal];
    }
    return _editorLeftButton;
}

- (UIButton *)editorRightButton
{
    if (!_editorRightButton) {
        _editorRightButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _editorRightButton.translatesAutoresizingMaskIntoConstraints = NO;
        _editorRightButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentRight;
        _editorRightButton.titleLabel.font = [UIFont boldSystemFontOfSize:15.0];
        _editorRightButton.enabled = NO;
        
        NSString *title = NSLocalizedString(@"Save", nil);
        
        [_editorRightButton setTitle:title forState:UIControlStateNormal];
    }
    return _editorRightButton;
}

- (UILabel *)charCountLabel
{
    if (!_charCountLabel) {
        _charCountLabel = [UILabel new];
        _charCountLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _charCountLabel.backgroundColor = [UIColor clearColor];
        _charCountLabel.textAlignment = NSTextAlignmentRight;
        _charCountLabel.font = [UIFont systemFontOfSize:11.0];
        
        _charCountLabel.hidden = YES;
    }
    return _charCountLabel;
}

- (BOOL)isHidden
{
    return _hidden;
}

- (CGFloat)minimumInputbarHeight
{
    CGFloat minimumHeight = self.toolBarButtonsViewHeight + self.textView.intrinsicContentSize.height;
    minimumHeight += self.contentInset.top;
    minimumHeight += self.slk_bottomMargin;
    
    return minimumHeight;
}

- (CGFloat)appropriateHeight
{
    CGFloat height = 0;
    CGFloat minimumHeight = [self minimumInputbarHeight];
    
    if (self.textView.numberOfLines == 1) {
        height = minimumHeight;
    }
    else if (self.textView.numberOfLines < self.textView.maxNumberOfLines) {
        height = self.toolBarButtonsViewHeight + [self slk_inputBarHeightForLines:self.textView.numberOfLines];
    }
    else {
        height = self.toolBarButtonsViewHeight + [self slk_inputBarHeightForLines:self.textView.maxNumberOfLines];
    }
    
    if (height < minimumHeight) {
        height = minimumHeight;
    }
    
    if (self.isEditing) {
        height += self.editorContentViewHeight;
    }
    
    return roundf(height);
}

- (BOOL)limitExceeded
{
    NSString *text = [self.textView.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    if (self.maxCharCount > 0 && text.length > self.maxCharCount) {
        return YES;
    }
    return NO;
}

- (CGFloat)slk_inputBarHeightForLines:(NSUInteger)numberOfLines
{
    CGFloat height = self.textView.intrinsicContentSize.height;
    height -= self.textView.font.lineHeight;
    height += roundf(self.textView.font.lineHeight*numberOfLines);
    height += self.contentInset.top;
    height += self.slk_bottomMargin;
    
    return height;
}

- (CGFloat)slk_bottomMargin
{
    CGFloat margin = self.contentInset.bottom;
    margin += self.slk_contentViewHeight;
    
    return margin;
}

- (CGFloat)slk_contentViewHeight
{
    if (!self.editing) {
        return CGRectGetHeight(self.contentView.frame);
    }
    
    return 0.0;
}

- (CGFloat)slk_appropriateRightButtonWidth
{
    if (self.autoHideRightButton) {
        if (self.textView.text.length == 0) {
            return 0.0;
        }
    }

    return [self.expandButton intrinsicContentSize].width;
}

- (CGFloat)slk_appropriateRightButtonMargin
{
    if (self.autoHideRightButton) {
        if (self.textView.text.length == 0) {
            return 0.0;
        }
    }
    
    return self.contentInset.right;
}

- (NSUInteger)slk_defaultNumberOfLines
{
    if (SLK_IS_IPAD) {
        return 8;
    }
    else if (SLK_IS_IPHONE4) {
        return 4;
    }
    else {
        return 6;
    }
}


#pragma mark - Setters

- (void)setBackgroundColor:(UIColor *)color
{
    self.barTintColor = color;

    self.editorContentView.backgroundColor = color;
}

- (void)setAutoHideRightButton:(BOOL)hide
{
    if (self.autoHideRightButton == hide) {
        return;
    }
    
    _autoHideRightButton = hide;
    
    self.rightButtonWC.constant = [self slk_appropriateRightButtonWidth];
    self.rightMarginWC.constant = [self slk_appropriateRightButtonMargin];

    [self layoutIfNeeded];
}

- (void)setContentInset:(UIEdgeInsets)insets
{
    if (UIEdgeInsetsEqualToEdgeInsets(self.contentInset, insets)) {
        return;
    }
    
    if (UIEdgeInsetsEqualToEdgeInsets(self.contentInset, UIEdgeInsetsZero)) {
        _contentInset = insets;
        return;
    }
    
    _contentInset = insets;
    
    // Add new constraints
    [self removeConstraints:self.constraints];
    [self slk_setupViewConstraints];
    
    // Add constant values and refresh layout
    [self slk_updateConstraintConstants];
    
    [super layoutIfNeeded];
}

- (void)setEditing:(BOOL)editing
{
    if (self.isEditing == editing) {
        return;
    }
    
    _editing = editing;
    _editorContentView.hidden = !editing;
    
    self.contentViewHC.active = editing;
    
    [super setNeedsLayout];
    [super layoutIfNeeded];
}

- (void)setHidden:(BOOL)hidden
{
    // We don't call super here, since we want to avoid to visually hide the view.
    // The hidden render state is handled by the view controller.
    
    _hidden = hidden;
    
    // Hide buttons view.
    self.buttonsView.hidden = hidden;
    
    if (!self.isEditing) {
        self.contentViewHC.active = hidden;
        
        [super setNeedsLayout];
        [super layoutIfNeeded];
    }
}

- (void)setCounterPosition:(SLKCounterPosition)counterPosition
{
    if (self.counterPosition == counterPosition && self.charCountLabelVCs) {
        return;
    }
    
    // Clears the previous constraints
    if (_charCountLabelVCs.count > 0) {
        [self removeConstraints:_charCountLabelVCs];
        _charCountLabelVCs = nil;
    }
    
    _counterPosition = counterPosition;
    
    NSDictionary *views = @{@"rightButton": self.expandButton,
                            @"charCountLabel": self.charCountLabel
                            };
    
    NSDictionary *metrics = @{@"top" : @(self.contentInset.top),
                              @"bottom" : @(-self.slk_bottomMargin/2.0)
                              };
    
    // Constraints are different depending of the counter's position type
    if (counterPosition == SLKCounterPositionBottom) {
        _charCountLabelVCs = [NSLayoutConstraint constraintsWithVisualFormat:@"V:[charCountLabel]-(bottom)-[rightButton]" options:0 metrics:metrics views:views];
    }
    else {
        _charCountLabelVCs = [NSLayoutConstraint constraintsWithVisualFormat:@"V:|-(top@750)-[charCountLabel]-(>=0)-|" options:0 metrics:metrics views:views];
    }
    
    [self addConstraints:self.charCountLabelVCs];
}

- (void)setLeftButtonHidden:(BOOL)isHidden
{
    self.photoButton.hidden = isHidden;
}

- (void)expandButtonDidPressed:(UIButton *)sender
{
    [self setIsExpanding:!self.isExpanding];
}

#pragma mark - Text Editing

- (BOOL)canEditText:(NSString *)text
{
    if ((self.isEditing && [self.textView.text isEqualToString:text]) || self.isHidden) {
        return NO;
    }
    
    return YES;
}

- (void)beginTextEditing
{
    if (self.isEditing || self.isHidden) {
        return;
    }
    
    self.editing = YES;
    
    [self slk_updateConstraintConstants];
    
    if (!self.isFirstResponder) {
        [self layoutIfNeeded];
    }
}

- (void)endTextEdition
{
    if (!self.isEditing || self.isHidden) {
        return;
    }
    
    self.editing = NO;
    
    [self slk_updateConstraintConstants];
}


#pragma mark - Character Counter

- (void)slk_updateCounter
{
    NSString *text = [self.textView.text stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSString *counter = nil;
    
    if (self.counterStyle == SLKCounterStyleNone) {
        counter = [NSString stringWithFormat:@"%lu", (unsigned long)text.length];
    }
    if (self.counterStyle == SLKCounterStyleSplit) {
        counter = [NSString stringWithFormat:@"%lu/%lu", (unsigned long)text.length, (unsigned long)self.maxCharCount];
    }
    if (self.counterStyle == SLKCounterStyleCountdown) {
        counter = [NSString stringWithFormat:@"%ld", (long)(text.length - self.maxCharCount)];
    }
    if (self.counterStyle == SLKCounterStyleCountdownReversed)
    {
        counter = [NSString stringWithFormat:@"%ld", (long)(self.maxCharCount - text.length)];
    }
    
    self.charCountLabel.text = counter;
    self.charCountLabel.textColor = [self limitExceeded] ? self.charCountLabelWarningColor : self.charCountLabelNormalColor;
}


#pragma mark - Notification Events

- (void)slk_didChangeTextViewText:(NSNotification *)notification
{
    SLKTextView *textView = (SLKTextView *)notification.object;
    
    // Skips this it's not the expected textView.
    if (![textView isEqual:self.textView]) {
        return;
    }
    
    // Updates the char counter label
    if (self.maxCharCount > 0) {
        [self slk_updateCounter];
    }
    
    if (self.autoHideRightButton && !self.isEditing)
    {
        CGFloat rightButtonNewWidth = [self slk_appropriateRightButtonWidth];
        
        // Only updates if the width did change
        if (self.rightButtonWC.constant == rightButtonNewWidth) {
            return;
        }
        
        self.rightButtonWC.constant = rightButtonNewWidth;
        self.rightMarginWC.constant = [self slk_appropriateRightButtonMargin];
        [self.expandButton layoutIfNeeded]; // Avoids the right button to stretch when animating the constraint changes
        
        BOOL bounces = self.bounces && [self.textView isFirstResponder];
        
        if (self.window) {
            [self slk_animateLayoutIfNeededWithBounce:bounces
                                              options:UIViewAnimationOptionCurveEaseInOut|UIViewAnimationOptionBeginFromCurrentState|UIViewAnimationOptionAllowUserInteraction
                                           animations:NULL];
        }
        else {
            [self layoutIfNeeded];
        }
    }
}

- (void)slk_didChangeTextViewContentSize:(NSNotification *)notification
{
    /*
    if (self.maxCharCount > 0) {
        BOOL shouldHide = (self.textView.numberOfLines == 1) || self.editing;
        self.charCountLabel.hidden = shouldHide;
    }
    */
}

- (void)slk_didChangeContentSizeCategory:(NSNotification *)notification
{
    if (!self.textView.isDynamicTypeEnabled) {
        return;
    }
    
    [self layoutIfNeeded];
}


#pragma mark - View Auto-Layout

- (void)slk_setupViewConstraints
{
    NSDictionary *views = @{@"textView": self.textView,
                            @"rightButton": self.expandButton,
                            @"editorContentView": self.editorContentView,
                            @"charCountLabel": self.charCountLabel,
                            @"contentView": self.contentView,
                            @"buttonsView": self.buttonsView,
                            };
    
    NSDictionary *metrics = @{@"top" : @(self.contentInset.top),
                              @"left" : @(self.contentInset.left),
                              @"right" : @(self.contentInset.right),
                              };
    
    [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-(left)-[textView]-(right)-[rightButton(0)]-(right)-|" options:0 metrics:metrics views:views]];
    [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-(top)-[rightButton]-(>=0)-[buttonsView]-(0)-|" options:0 metrics:metrics views:views]];
    [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-(left@250)-[charCountLabel(<=50@1000)]-(right@750)-|" options:0 metrics:metrics views:views]];
    [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-0-[editorContentView(0)]-(<=top)-[textView(0@999)]-(4)-[buttonsView(44)]-(0)-|" options:0 metrics:metrics views:views]];
    [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[editorContentView]|" options:0 metrics:metrics views:views]];
    [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[contentView]|" options:0 metrics:metrics views:views]];
    [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:[contentView(0)]|" options:0 metrics:metrics views:views]];
    [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[buttonsView]|" options:0 metrics:metrics views:views]];

    self.textViewBottomMarginC = [self slk_constraintForAttribute:NSLayoutAttributeBottom firstItem:self secondItem:self.buttonsView];
    self.editorContentViewHC = [self slk_constraintForAttribute:NSLayoutAttributeHeight firstItem:self.editorContentView secondItem:nil];
    
    self.contentViewHC = [self slk_constraintForAttribute:NSLayoutAttributeHeight firstItem:self.contentView secondItem:nil];;
    self.contentViewHC.active = NO; // Disabled by default, so the height is calculated with the height of its subviews
        
    self.rightButtonWC = [self slk_constraintForAttribute:NSLayoutAttributeWidth firstItem:self.expandButton secondItem:nil];
    self.rightMarginWC = [[self slk_constraintsForAttribute:NSLayoutAttributeTrailing] firstObject];
}

- (void)slk_updateConstraintConstants
{
    CGFloat zero = 0.0;
    
    self.textViewBottomMarginC.constant = self.slk_bottomMargin;

    if (self.isEditing)
    {
        self.editorContentViewHC.constant = self.editorContentViewHeight;
        
        self.rightButtonWC.constant = zero;
        self.rightMarginWC.constant = zero;
    }
    else {
        self.editorContentViewHC.constant = zero;
                        
        self.rightButtonWC.constant = [self slk_appropriateRightButtonWidth];
        self.rightMarginWC.constant = [self slk_appropriateRightButtonMargin];
    }
}


#pragma mark - Observers

- (void)slk_registerTo:(id)object forSelector:(SEL)selector
{
    if (object) {
        [object addObserver:self forKeyPath:NSStringFromSelector(selector) options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld context:NULL];
    }
}

- (void)slk_unregisterFrom:(id)object forSelector:(SEL)selector
{
    if (object) {
        [object removeObserver:self forKeyPath:NSStringFromSelector(selector)];
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if ([object isEqual:self.layer] && [keyPath isEqualToString:NSStringFromSelector(@selector(position))]) {
        
        if (!CGPointEqualToPoint(self.previousOrigin, self.frame.origin)) {
            self.previousOrigin = self.frame.origin;
            [[NSNotificationCenter defaultCenter] postNotificationName:SLKTextInputbarDidMoveNotification object:self userInfo:@{@"origin": [NSValue valueWithCGPoint:self.previousOrigin]}];
        }
    }
    else if ([object isEqual:self.photoButton.imageView] && [keyPath isEqualToString:NSStringFromSelector(@selector(image))]) {
        
        UIImage *newImage = change[NSKeyValueChangeNewKey];
        UIImage *oldImage = change[NSKeyValueChangeOldKey];
        
        if (![newImage isEqual:oldImage]) {
            [self slk_updateConstraintConstants];
        }
    }
    else if ([object isEqual:self.expandButton.titleLabel] && [keyPath isEqualToString:NSStringFromSelector(@selector(font))]) {
        
        [self slk_updateConstraintConstants];
    }
    else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}


#pragma mark - NSNotificationCenter registration

- (void)slk_registerNotifications
{
    [self slk_unregisterNotifications];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(slk_didChangeTextViewText:) name:UITextViewTextDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(slk_didChangeTextViewContentSize:) name:SLKTextViewContentSizeDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(slk_didChangeContentSizeCategory:) name:UIContentSizeCategoryDidChangeNotification object:nil];
}

- (void)slk_unregisterNotifications
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UITextViewTextDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:SLKTextViewContentSizeDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIContentSizeCategoryDidChangeNotification object:nil];
}


#pragma mark - Lifeterm

- (void)dealloc
{
    [self slk_unregisterNotifications];
    
    [self slk_unregisterFrom:self.layer forSelector:@selector(position)];
    [self slk_unregisterFrom:self.photoButton.imageView forSelector:@selector(image)];
    [self slk_unregisterFrom:self.expandButton.titleLabel forSelector:@selector(font)];
}

@end
