//
//  ICMPEchoProbe.h
//  Interconnect
//
//  Created by oroboto on 29/04/2016.
//  Copyright © 2016 oroboto. All rights reserved.
//

#import "ICMPProbe.h"

/**
 * Possible values for lastError
 */
#define kICMPEchoProbeErrorNone        0
#define kICMPEchoProbeErrorNoSocket    1
#define kICMPEchoProbeErrorPacket      2
#define kICMPEchoProbeErrorSend        3
#define kICMPEchoProbeErrorRecvTimeout 4
#define kICMPEchoProbeErrorRecvWait    5
#define kICMPEchoProbeErrorRecv        6
#define kICMPEchoProbeInvalidPacket    7

@interface ICMPEchoProbe : ICMPProbe

@property (nonatomic) NSUInteger lastError;

- (float)measureAverageRTT;

@end
