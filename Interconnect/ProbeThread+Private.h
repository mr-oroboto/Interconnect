//
//  ProbeThread+Private.h
//  Interconnect
//
//  Private methods that are available only to derived classes of ProbeThread
//
//  Created by oroboto on 15/05/2016.
//  Copyright © 2016 oroboto. All rights reserved.
//

@interface ProbeThread (oroboto_Private)

- (unsigned short)internetChecksum:(unsigned char*)data length:(unsigned short)length;
- (float)msElapsedBetween:(struct timeval)startTime endTime:(struct timeval)endTime;

@end
