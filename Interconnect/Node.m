//
//  Node.m
//  Interconnect
//
//  Created by oroboto on 16/04/2016.
//  Copyright © 2016 oroboto. All rights reserved.
//

#import "Node.h"

#define kMinRadius 0
#define kMinVolume 0.001

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
        _volume = _targetVolume = volume;
        _radius = (float)orbital;
        _rotation = 0.0f;
        _identifier = [identifier copy];
        
        NSLog(@"Node[%@]: Initialised with orbital: %lu, radius: %.2f", identifier, (unsigned long)_orbital, _radius);
    }
    
    return self;
}

- (void)setRadius:(float)radius
{
    if (radius < kMinRadius)
    {
        NSLog(@"Limiting radius %.2f to %.2f", radius, kMinRadius);
        radius = kMinRadius;
    }
    
    _radius = radius;
    
    NSLog(@"Node[%@]: Set radius to %.2f", _identifier, _radius);
}

- (void)setVolume:(float)volume
{
    if (volume < kMinVolume)
    {
        NSLog(@"Limiting volume %.2f to %.2f", volume, kMinVolume);
        volume = kMinVolume;
    }
    
    _volume = volume;
    
    NSLog(@"Node[%@]: Set volume to %.2f", _identifier, _volume);
}

@end
