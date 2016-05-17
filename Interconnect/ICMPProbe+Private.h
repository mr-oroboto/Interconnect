//
//  ICMPProbe+Private.h
//  Interconnect
//
//  Private methods that are available only to derived classes of ProbeThread
//
//  Created by oroboto on 17/05/2016.
//  Copyright © 2016 oroboto. All rights reserved.
//

#include <time.h>

@interface ICMPProbe (oroboto_Private)

- (unsigned short)internetChecksum:(unsigned char*)data length:(unsigned short)length;
- (float)msElapsedBetween:(const struct timeval*)startTime endTime:(const struct timeval*)endTime;

@end