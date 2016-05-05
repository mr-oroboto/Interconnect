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
@property (nonatomic) NSUInteger orbital;
@property (nonatomic) float radius;
@property (nonatomic) float targetVolume;
@property (nonatomic) float volume;
@property (nonatomic) float rotation;
@property (nonatomic) BOOL selected;
@property (nonatomic) float pulseIntensity;
@property (nonatomic) BOOL pulseBegin;
@property (nonatomic) float originConnector;

+ (instancetype)createInOrbital:(NSUInteger)orbital withIdentifier:(NSString*)identifier andVolume:(float)volume;
- (instancetype)initInOrbital:(NSUInteger)orbital withIdentifier:(NSString*)identifier andVolume:(float)volume;

- (void)growRadius:(float)delta;
- (void)shrinkRadius:(float)delta;
- (void)growVolume:(float)delta;
- (void)shrinkVolume:(float)delta;

@end
