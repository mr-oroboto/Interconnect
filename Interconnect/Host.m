//
//  Host.m
//  Interconnect
//
//  Created by oroboto on 16/04/2016.
//  Copyright © 2016 oroboto. All rights reserved.
//

#import "Host.h"

@implementation Host

+ (instancetype)createInOrbital:(NSUInteger)orbital withIdentifier:(NSString*)identifier andVolume:(float)volume
{
    return [[Host alloc] initInOrbital:orbital withIdentifier:identifier andVolume:volume];
}

- (instancetype)init
{
    if (self = [super init])
    {
        _bytesSent = 0;
        _bytesReceived = 0;
    }
    
    return self;
}

- (NSUInteger)bytesTransferred
{
    return _bytesSent + _bytesReceived;
}

@end
