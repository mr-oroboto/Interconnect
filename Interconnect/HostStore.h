//
//  HostStore.h
//  Interconnect
//
//  Created by oroboto on 20/04/2016.
//  Copyright © 2016 oroboto. All rights reserved.
//

#import "NodeStore.h"

@interface HostStore : NodeStore

+ (instancetype)sharedStore;
- (void)updateHost:(NSString*)identifier withHopCount:(NSUInteger)hopCount addBytesIn:(NSUInteger)bytesIn addBytesOut:(NSUInteger)bytesOut;
- (void)updateHost:(NSString*)identifier withHopCount:(NSUInteger)hopCount;

@end
