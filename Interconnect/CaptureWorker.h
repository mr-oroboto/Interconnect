//
//  CaptureWorker.h
//  Interconnect
//
//  Created by oroboto on 17/04/2016.
//  Copyright © 2016 oroboto. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#define kProbeTypeICMPEcho          0
#define kProbeTypeTraceroute        1
#define kProbeTypeThreadICMPEcho    2
#define kProbeTypeThreadTraceroute  3

@interface CaptureWorker : NSObject

- (void)startCapture;
- (void)stopCapture;

@end
