//
//  Host.h
//  Interconnect
//
//  Created by oroboto on 16/04/2016.
//  Copyright © 2016 oroboto. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "Node.h"

@interface Host : Node

@property (nonatomic, copy) NSString* ipAddress;
@property (nonatomic, copy) NSString* hostname;
@property (nonatomic, copy) NSString* autonomousSystem;
@property (nonatomic, copy) NSString* autonomousSystemDesc;
@property (nonatomic) NSUInteger bytesSent;
@property (nonatomic) NSUInteger bytesReceived;
@property (nonatomic) NSUInteger firstPortSeen;
@property (nonatomic) float rtt;
@property (nonatomic) NSUInteger hopCount;

+ (instancetype)createInGroup:(NSUInteger)group withIdentifier:(NSString*)identifier andVolume:(float)volume;

- (NSUInteger)bytesTransferred;

@end
