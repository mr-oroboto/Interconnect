//
//  Node.m
//  Interconnect
//
//  Created by oroboto on 16/04/2016.
//  Copyright © 2016 oroboto. All rights reserved.
//

#import "Node.h"

@interface Node ()
@end

@implementation Node

+ (instancetype)createInOrbital:(NSUInteger)orbital withIdentifier:(NSString*)identifier andVolume:(float)volume
{
    return [[Node alloc] initInOrbital:orbital withIdentifier:identifier andVolume:volume];
}

- (instancetype)initInOrbital:(NSUInteger)orbital withIdentifier:(NSString*)identifier andVolume:(float)volume
{
    if (self = [super init])
    {
        _orbital = orbital;
        _volume = volume;
        _radius = orbital;
        _identifier = [identifier copy];
    }
    
    return self;
}

@end
