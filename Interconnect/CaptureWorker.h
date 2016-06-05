//
//  CaptureWorker.h
//  Interconnect
//
//  Created by oroboto on 17/04/2016.
//  Copyright © 2016 oroboto. All rights reserved.
//

#import <Cocoa/Cocoa.h>

typedef enum
{
    kProbeTypeICMPEcho = 0,
    kProbeTypeTraceroute,
    kProbeTypeThreadICMPEcho,
    kProbeTypeThreadTraceroute
} ProbeType;

@interface CaptureWorker : NSObject

@property (nonatomic, readonly) ProbeType probeType;                  // how should newly discovered hosts be probed?
@property (nonatomic, readonly) BOOL completeTimedOutProbes;

- (BOOL)setProbeMethod:(ProbeType)probeType completeTimedOutProbes:(BOOL)completeTimedOutProbes;

- (void)startCapture;
- (BOOL)stopCapture:(void (^)(void))threadStoppedBlock;

@end
