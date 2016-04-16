//
//  Node.h
//  Interconnect
//
//  Created by oroboto on 16/04/2016.
//  Copyright © 2016 oroboto. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface Node : NSObject

@property (nonatomic, readonly) NSString* identifier;
@property (nonatomic, readonly) NSUInteger orbital;
@property (nonatomic, readonly) float volume;
@property (nonatomic, readonly) float radius;

+ (instancetype)createInOrbital:(NSUInteger)orbital withIdentifier:(NSString*)identifier andVolume:(float)volume;

@end
