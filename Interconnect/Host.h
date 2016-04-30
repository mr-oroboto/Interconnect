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
@property (nonatomic) NSUInteger bytesSent;
@property (nonatomic) NSUInteger bytesReceived;

+ (instancetype)createInGroup:(NSUInteger)group withIdentifier:(NSString*)identifier andVolume:(float)volume;

- (NSUInteger)bytesTransferred;

@end
