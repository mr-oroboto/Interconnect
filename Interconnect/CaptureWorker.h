//
//  CaptureWorker.h
//  Interconnect
//
//  Created by oroboto on 17/04/2016.
//  Copyright © 2016 oroboto. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#define kProbeTypeICMPEcho  0

@interface CaptureWorker : NSObject

- (void)startCapture;
- (void)stopCapture;

@end
