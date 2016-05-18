//
//  Probe.h
//  Interconnect
//
//  Created by oroboto on 15/05/2016.
//  Copyright © 2016 oroboto. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <sys/time.h>

@interface Probe : NSObject

@property (nonatomic, copy) NSString* hostIdentifier;
@property (nonatomic) uint16_t icmpIdentifier;
@property (nonatomic) uint16_t sequenceNumber;
@property (nonatomic) uint8_t currentTTL;
@property (nonatomic) float rttToHost;
@property (nonatomic) uint16_t dstPort;
@property (nonatomic) struct timeval timeSent;
@property (nonatomic) uint8_t retries;
@property (nonatomic) BOOL inflight;
@property (nonatomic) BOOL complete;
@property (nonatomic, copy) void (^completionBlock)(Probe*);

@end
