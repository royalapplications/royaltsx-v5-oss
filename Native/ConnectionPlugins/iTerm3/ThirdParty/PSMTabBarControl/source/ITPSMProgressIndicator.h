//
//  ITPSMProgressIndicator.h
//  ITPSMTabBarControl
//
//  Created by John Pannell on 2/23/06.
//  Copyright 2006 Positive Spin Media. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@protocol ITPSMProgressIndicatorDelegate
- (void)progressIndicatorNeedsUpdate;
@end

// This is a wrapper around an NSProgressIndicator. The main difference between this and
// NSProgressIndicator is that setting the |light| property changes the appearance of the progress
// indicator so it looks good against a dark background.
@interface ITPSMProgressIndicator : NSView

// Should the progress indicator render in a "light" style, suitable for use over a dark background?
@property(nonatomic, assign) BOOL light;
@property(nonatomic, assign) id<ITPSMProgressIndicatorDelegate> delegate;
@property(nonatomic, assign) BOOL animate;

@end
