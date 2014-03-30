//
//  UICollectionView+TransitionLayoutAnimator.m
//
//  Copyright (c) 2013 Tim Moose (http://tractablelabs.com)
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

#import "UICollectionView+TLTransitioning.h"
#import "TLTransitionLayout.h"

@implementation UICollectionView (TLTransitioning)

#pragma mark - Simulated properties

static char kTLAnimationDurationKey;
static char kTLAnimationStartTimeKey;
static char kTLTransitionLayoutKey;
static char kTLEasingFunctionKey;

- (NSNumber *)tl_animationDuration
{
    return (NSNumber *)objc_getAssociatedObject(self, &kTLAnimationDurationKey);
}

- (void)tl_setAnimationDuration:(NSNumber *)duration
{
    objc_setAssociatedObject(self, &kTLAnimationDurationKey, duration, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSNumber *)tl_animationStartTime
{
    return (NSNumber *)objc_getAssociatedObject(self, &kTLAnimationStartTimeKey);
}

- (void)tl_setAnimationStartTime:(NSNumber *)startTime
{
    objc_setAssociatedObject(self, &kTLAnimationStartTimeKey, startTime, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (UICollectionViewTransitionLayout *)tl_transitionLayout
{
    return (UICollectionViewTransitionLayout *)objc_getAssociatedObject(self, &kTLTransitionLayoutKey);
}

- (void)tl_setTransitionLayout:(UICollectionViewTransitionLayout *)layout
{
    objc_setAssociatedObject(self, &kTLTransitionLayoutKey, layout, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (AHEasingFunction)tl_easingFunction
{
    NSValue *value = objc_getAssociatedObject(self, &kTLEasingFunctionKey);
    return [value pointerValue];
}

- (void)tl_setEasingFunction:(AHEasingFunction)easingFunction
{
    NSValue *value = easingFunction ? [NSValue valueWithPointer:easingFunction] : nil;
    objc_setAssociatedObject(self, &kTLEasingFunctionKey, value, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#pragma mark - Transition logic

- (UICollectionViewTransitionLayout *)transitionToCollectionViewLayout:(UICollectionViewLayout *)layout duration:(NSTimeInterval)duration easing:(AHEasingFunction)easingFunction completion:(UICollectionViewLayoutInteractiveTransitionCompletion)completion
{
    if (duration <= 0) {
        [NSException raise:@"" format:@""];//TODO
    }
    [[UIApplication sharedApplication] beginIgnoringInteractionEvents];
    [self tl_setAnimationDuration:@(duration)];
    [self tl_setAnimationStartTime:@(CACurrentMediaTime())];
    [self tl_setEasingFunction:easingFunction];
    CADisplayLink *link = [CADisplayLink displayLinkWithTarget:self selector:@selector(updateProgress:)];
    [link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    __weak UICollectionView *weakSelf = self;
    UICollectionViewTransitionLayout *transitionLayout = [self startInteractiveTransitionToCollectionViewLayout:layout completion:^(BOOL completed, BOOL finish) {
        __strong UICollectionView *strongSelf = weakSelf;
        UICollectionViewTransitionLayout *transitionLayout = [self tl_transitionLayout];
        if ([transitionLayout conformsToProtocol:@protocol(TLTransitionAnimatorLayout)]) {
            id<TLTransitionAnimatorLayout>layout = (id<TLTransitionAnimatorLayout>)transitionLayout;
            [layout collectionViewDidCompleteTransitioning:strongSelf completed:completed finish:finish];
        }
        [strongSelf tl_setAnimationDuration:nil];
        [strongSelf tl_setAnimationStartTime:nil];
        [strongSelf tl_setTransitionLayout:nil];
        [strongSelf tl_setEasingFunction:NULL];
        if (completion) {
            completion(completed, finish);
        }
        [[UIApplication sharedApplication] endIgnoringInteractionEvents];
    }];
    [self tl_setTransitionLayout:transitionLayout];
    return transitionLayout;
}

- (UICollectionViewTransitionLayout *)transitionToCollectionViewLayout:(UICollectionViewLayout *)layout duration:(NSTimeInterval)duration completion:(UICollectionViewLayoutInteractiveTransitionCompletion)completion
{
    return [self transitionToCollectionViewLayout:layout duration:duration easing:nil completion:completion];
}

- (void)updateProgress:(CADisplayLink *)link
{
    UICollectionViewLayout *layout = self.collectionViewLayout;
    if ([layout isKindOfClass:[UICollectionViewTransitionLayout class]]) {
        CFTimeInterval startTime = [[self tl_animationStartTime] floatValue];
        NSTimeInterval duration = [[self tl_animationDuration] floatValue];
        CFTimeInterval time = duration > 0 ? (link.timestamp - startTime) / duration : 1;
        time = MIN(1, time);
        time = MAX(0, time);
        UICollectionViewTransitionLayout *l = (UICollectionViewTransitionLayout *)layout;
        if (time >= 1) {
            [self finishTransition:link];
        } else {
            AHEasingFunction easingFunction = [self tl_easingFunction];
            CGFloat progress = easingFunction ? easingFunction(time) : time;
            l.transitionProgress = progress;
            [l invalidateLayout];
        }
    } else {
        [self finishTransition:link];
    }
}

- (void)finishTransition:(CADisplayLink *)link
{
    [link invalidate];
    [self finishInteractiveTransition];
}

#pragma mark - Calculating transition values

CGFloat transitionProgress(CGFloat initialValue, CGFloat currentValue, CGFloat finalValue, AHEasingFunction easingFunction)
{
    CGFloat p = (currentValue - initialValue) / (finalValue - initialValue);
    p = MIN(1.0, p);
    p = MAX(0, p);
    return easingFunction ? easingFunction(p) : p;
}

- (CGPoint)toContentOffsetForLayout:(UICollectionViewTransitionLayout *)layout indexPaths:(NSArray *)indexPaths placement:(TLTransitionLayoutIndexPathPlacement)placement
{
    return [self toContentOffsetForLayout:layout indexPaths:indexPaths placement:placement toSize:self.bounds.size toContentInset:self.contentInset];
}

- (CGPoint)toContentOffsetForLayout:(UICollectionViewTransitionLayout *)layout indexPaths:(NSArray *)indexPaths placement:(TLTransitionLayoutIndexPathPlacement)placement toSize:(CGSize)toSize toContentInset:(UIEdgeInsets)toContentInset
{
    CGPoint fromCenter, toCenter = CGPointZero;
    CGRect toFrameUnion = CGRectNull;
    if (indexPaths.count) {
        for (NSIndexPath *indexPath in indexPaths) {
            UICollectionViewLayoutAttributes *fromPose = [layout.currentLayout layoutAttributesForItemAtIndexPath:indexPath];
            UICollectionViewLayoutAttributes *toPose = [layout.nextLayout layoutAttributesForItemAtIndexPath:indexPath];
            fromCenter = addPoints(fromCenter, fromPose.center);
            toCenter = addPoints(toCenter, toPose.center);
            if (CGRectIsNull(toFrameUnion)) {
                toFrameUnion = toPose.frame;
            }
            toFrameUnion = CGRectUnion(toFrameUnion, toPose.frame);
        }
        fromCenter = dividePoint(fromCenter, indexPaths.count);
        toCenter = dividePoint(toCenter, indexPaths.count);
    }
    
    CGRect bounds = (CGRect){{0, 0}, toSize};
    
    UIEdgeInsets contentInset = self.contentInset;
    CGPoint contentOffset = self.contentOffset;
    
    CGPoint sourcePoint;
    CGPoint destinationPoint;
    
    switch (placement) {
            
        case TLTransitionLayoutIndexPathPlacementMinimal:
            sourcePoint = CGPointMake(toCenter.x, toCenter.y);
            destinationPoint = CGPointMake(fromCenter.x - contentInset.left - contentOffset.x, fromCenter.y - contentInset.top - contentOffset.y);
            break;
        case TLTransitionLayoutIndexPathPlacementCenter:
            sourcePoint = toCenter;
            destinationPoint = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
            break;
        case TLTransitionLayoutIndexPathPlacementTop:
            sourcePoint = CGPointMake(CGRectGetMidX(toFrameUnion), CGRectGetMinY(toFrameUnion));
            destinationPoint = CGPointMake(CGRectGetMidX(bounds), CGRectGetMinY(bounds));
            break;
        case TLTransitionLayoutIndexPathPlacementLeft:
            sourcePoint = CGPointMake(CGRectGetMinX(toFrameUnion), CGRectGetMidY(toFrameUnion));
            destinationPoint = CGPointMake(CGRectGetMinX(bounds), CGRectGetMidY(bounds));
            break;
        case TLTransitionLayoutIndexPathPlacementBottom:
            sourcePoint = CGPointMake(CGRectGetMidX(toFrameUnion), CGRectGetMaxY(toFrameUnion));
            destinationPoint = CGPointMake(CGRectGetMidX(bounds), CGRectGetMaxY(bounds));
            break;
        case TLTransitionLayoutIndexPathPlacementRight:
            sourcePoint = CGPointMake(CGRectGetMaxX(toFrameUnion), CGRectGetMidY(toFrameUnion));
            destinationPoint = CGPointMake(CGRectGetMaxX(bounds), CGRectGetMidY(bounds));
            break;
        default:
            break;
    }
    
    CGSize contentSize = layout.nextLayout.collectionViewContentSize;
    
    CGPoint toInsetOffset = CGPointMake(toContentInset.left, toContentInset.top);
    
    CGPoint offset = CGPointMake(sourcePoint.x - destinationPoint.x - toInsetOffset.x, sourcePoint.y - destinationPoint.y - toInsetOffset.y);

    CGFloat minOffsetX = -toContentInset.left;
    CGFloat minOffsetY = -toContentInset.top;

    CGFloat maxOffsetX = toContentInset.right + contentSize.width - bounds.size.width;
    CGFloat maxOffsetY = toContentInset.right + contentSize.height - bounds.size.height;
    
    offset.x = MAX(minOffsetX, offset.x);
    offset.y = MAX(minOffsetY, offset.y);
    
    offset.x = MIN(maxOffsetX, offset.x);
    offset.y = MIN(maxOffsetY, offset.y);
    
    return offset;
}

- (CGRect)transitionFrameFromFrame:(CGRect)fromFrame toFrame:(CGRect)toFrame transitionProgress:(CGFloat)transitionProgress
{
    CGFloat t = transitionProgress;
    CGFloat f = 1 - t;
    CGRect frame;
    frame.origin.x = t * toFrame.origin.x + f * fromFrame.origin.x;
    frame.origin.y = t * toFrame.origin.y + f * fromFrame.origin.y;
    frame.size.width = t * toFrame.size.width + f * fromFrame.size.width;
    frame.size.height = t * toFrame.size.height + f * fromFrame.size.height;
    return frame;
}

- (CGPoint)transitionPointFromPoint:(CGPoint)fromPoint toPoint:(CGPoint)toPoint transitionProgress:(CGFloat)transitionProgress
{
    CGFloat t = transitionProgress;
    CGFloat f = 1 - t;
    CGPoint point;
    point.x = t * toPoint.x + f * fromPoint.x;
    point.y = t * toPoint.y + f * fromPoint.y;
    return point;
}

CGPoint addPoints(CGPoint point, CGPoint otherPoint)
{
    return CGPointMake(point.x + otherPoint.x, point.y + otherPoint.y);
}

CGPoint dividePoint(CGPoint point, CGFloat divisor)
{
    if (divisor <= 0) {
        divisor = 1;
    }
    return CGPointMake(point.x  / divisor, point.y / divisor);
}

@end
