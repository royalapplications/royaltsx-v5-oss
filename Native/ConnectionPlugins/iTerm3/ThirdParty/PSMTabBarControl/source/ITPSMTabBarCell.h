//
//  ITPSMTabBarCell.h
//  ITPSMTabBarControl
//
//  Created by John Pannell on 10/13/05.
//  Copyright 2005 Positive Spin Media. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "ITPSMTabBarControl.h"
#import "ITPSMProgressIndicator.h"

@class ITPSMTabBarControl;
@protocol ITPSMTabStyle;

@protocol ITPSMTabBarControlProtocol <NSObject>
- (void)tabClick:(id)sender;
- (void)closeTabClick:(id)sender;
- (id<ITPSMTabStyle>)style;
- (void)update:(BOOL)animate;
- (BOOL)automaticallyAnimates;
- (PSMTabBarOrientation)orientation;
- (id<ITPSMTabBarControlDelegate>)delegate;
- (NSTabView *)tabView;
@end

@interface ITPSMTabBarCell : NSActionCell <NSCoding>
// Is this the last cell? Only valid while drawing.
@property(nonatomic, assign) BOOL isLast;
@property(nonatomic, assign) BOOL isCloseButtonSuppressed;
@property(nonatomic, readonly) BOOL closeButtonVisible;
@property(nonatomic, assign) int tabState;
@property(nonatomic, assign) NSRect frame;
@property(nonatomic, assign) NSTrackingRectTag cellTrackingTag;  // right side tracking, if dragging
@property(nonatomic, assign) NSTrackingRectTag closeButtonTrackingTag;  // left side tracking, if dragging
@property(nonatomic, assign) BOOL isInOverflowMenu;
@property(nonatomic, assign) BOOL closeButtonPressed;
@property(nonatomic, assign) BOOL closeButtonOver;
@property(nonatomic, assign) BOOL hasCloseButton;
@property(nonatomic, assign) BOOL hasIcon;
@property(nonatomic, assign) int count;
@property(nonatomic, assign) BOOL isPlaceholder;
@property(nonatomic, assign) int currentStep;
@property(nonatomic, copy) NSString *modifierString;
@property(nonatomic, retain) NSColor *tabColor;
@property(nonatomic, readonly) ITPSMProgressIndicator *indicator;
@property(nonatomic, readonly) NSAttributedString *attributedStringValue;
@property(nonatomic, readonly) NSSize stringSize;
@property(nonatomic, readonly) float width;
@property(nonatomic, readonly) float minimumWidthOfCell;
@property(nonatomic, readonly) float desiredWidthOfCell;
@property(nonatomic, readonly) id<ITPSMTabStyle> style;
@property(nonatomic, assign) NSLineBreakMode truncationStyle;  // How to truncate title.
@property(nonatomic, readonly) NSAccessibilityElement *element;

// creation/destruction
- (id)initWithControlView:(ITPSMTabBarControl *)controlView;
- (id)initPlaceholderWithFrame:(NSRect)frame expanded:(BOOL)value inControlView:(ITPSMTabBarControl *)controlView;

// accessors
- (void)setStringValue:(NSString *)aString;

// component attributes
- (NSRect)indicatorRectForFrame:(NSRect)cellFrame;
- (NSRect)closeButtonRectForFrame:(NSRect)cellFrame;

// drawing
- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView;
- (void)drawPostHocDecorationsOnSelectedCellWithTabBarControl:(ITPSMTabBarControl *)bar;

// drag support
- (NSImage *)dragImage;

// iTerm additions
- (void)updateForStyle;
- (void)updateHighlight;

@end
