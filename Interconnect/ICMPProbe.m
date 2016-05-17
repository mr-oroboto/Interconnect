//
//  ICMPProbe.m
//  Interconnect
//
//  Created by oroboto on 17/05/2016.
//  Copyright © 2016 oroboto. All rights reserved.
//

#import "ICMPProbe.h"

@implementation ICMPProbe

+ (instancetype)probeWithIPAddress:(NSString*)ipAddress
{
    [NSException raise:@"probeWithIPAddress" format:@"Must be over-ridden by derived class"];
    return nil;
}

/**
 * From Apple's SimplePing example code
 */
- (unsigned short)internetChecksum:(unsigned char*)data length:(unsigned short)length
{
    size_t bytesLeft;
    int sum;
    const unsigned short* cursor;
    union
    {
        unsigned short us;
        unsigned char uc[2];
    } last;
    unsigned short answer;
    
    bytesLeft = length;
    sum = 0;
    cursor = (unsigned short*)data;
    
    /*
     * Our algorithm is simple, using a 32 bit accumulator (sum), we add
     * sequential 16 bit words to it, and at the end, fold back all the
     * carry bits from the top 16 bits into the lower 16 bits.
     */
    while (bytesLeft > 1)
    {
        sum += *cursor;
        cursor += 1;
        bytesLeft -= 2;
    }
    
    /* mop up an odd byte, if necessary */
    if (bytesLeft == 1)
    {
        last.uc[0] = * (const unsigned char *) cursor;
        last.uc[1] = 0;
        sum += last.us;
    }
    
    /* add back carry outs from top 16 bits to low 16 bits */
    sum = (sum >> 16) + (sum & 0xffff); /* add hi 16 to low 16 */
    sum += (sum >> 16);         /* add carry */
    answer = (unsigned short) ~sum;   /* truncate to 16 bits */
    
    return answer;
}

- (float)msElapsedBetween:(const struct timeval*)startTime endTime:(const struct timeval*)endTime
{
    float msElapsed = (endTime->tv_usec - startTime->tv_usec) / 1000.0;
    
    if (endTime->tv_sec - startTime->tv_sec)
    {
        msElapsed = ((((endTime->tv_sec - startTime->tv_sec) - 1) * 1000000) + (1000000 - startTime->tv_usec) + endTime->tv_usec) / 1000.0;
    }
    
    return msElapsed;
}

@end
