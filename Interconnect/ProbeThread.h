//
//  ProbeThread.h
//  Interconnect
//
//  Created by oroboto on 15/05/2016.
//  Copyright © 2016 oroboto. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class Probe;

@interface ProbeThread : NSObject

@property (nonatomic, readonly) BOOL threadRunning;
@property (nonatomic) BOOL completeTimedOutProbes;

- (void)start;
- (BOOL)stop:(void (^)(void))threadStoppedBlock;

- (void)queueProbeForHost:(NSString*)hostIdentifier withPriority:(BOOL)priority onCompletion:(void (^)(Probe*))completionBlock;
- (void)processHostQueue;

@end
