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
    if (radius > (float)_orbital)
    {
        NSLog(@"Limiting radius %.2f to %.2f", radius, (float)_orbital);
        radius = (float)_orbital;
    }
    else if (radius < 0.0)
    {
        NSLog(@"Limiting radius %.2f to 0.0", radius);
        radius = 0.0;
    }
    
    _radius = radius;
    
    NSLog(@"Node[%@]: Set radius to %.2f", _identifier, _radius);
}

- (void)setVolume:(float)volume
{
    if (volume > _targetVolume)
    {
        NSLog(@"Limiting volume %.2f to %.2f", volume, _targetVolume);
        volume = (float)_targetVolume;
    }
    else if (volume < 0.0)
    {
        NSLog(@"Limiting volume %.2f to 0.0", volume);
        volume = 0.0;
    }
    
    _volume = volume;
    
    NSLog(@"Node[%@]: Set volume to %.2f", _identifier, _volume);
}

@end
