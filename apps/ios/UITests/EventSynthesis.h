// XCTest's own touch synthesis (the classes XCUICoordinate uses internally; WebDriverAgent uses
// them the same way): arbitrary single- and multi-finger paths with timing, which the public API
// (one straight drag) cannot express. Declared here, provided by XCTest.framework at run time.
// SPDX-License-Identifier: GPL-2.0-or-later
#import <XCTest/XCTest.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface XCPointerEventPath : NSObject
- (instancetype)initForTouchAtPoint:(CGPoint)point offset:(double)offset;
- (void)moveToPoint:(CGPoint)point atOffset:(double)offset;
- (void)liftUpAtOffset:(double)offset;
@end

@interface XCSynthesizedEventRecord : NSObject
- (instancetype)initWithName:(NSString *)name interfaceOrientation:(UIInterfaceOrientation)orientation;
- (void)addPointerEventPath:(XCPointerEventPath *)path;
- (BOOL)synthesizeWithError:(NSError * _Nullable * _Nullable)error;
@end

NS_ASSUME_NONNULL_END
