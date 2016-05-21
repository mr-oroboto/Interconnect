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

- (void)startCapture;
- (void)stopCapture;

@end
