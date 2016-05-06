//
//  HostStore.h
//  Interconnect
//
//  The public interface only allows mutation of the underlying store (addition and removal of hosts) or mutation of
//  objects in the store (hosts) by their IDs, not by direct access to the objects themselves. This allows the store
//  to manage synchronisation to both the store and the objects inside it.
//
//  Created by oroboto on 20/04/2016.
//  Copyright © 2016 oroboto. All rights reserved.
//

#import "NodeStore.h"

@interface HostStore : NodeStore

+ (instancetype)sharedStore;

- (BOOL)updateHostBytesTransferred:(NSString*)identifier addBytesIn:(NSUInteger)bytesIn addBytesOut:(NSUInteger)bytesOut port:(NSUInteger)port;
- (void)updateHost:(NSString*)identifier withGroup:(NSUInteger)group;
- (void)updateHost:(NSString*)identifier withName:(NSString*)name;
- (void)updateHost:(NSString*)identifier withAS:(NSString*)as andASDescription:(NSString*)asDesc;
- (void)recalculateHostSizesBasedOnBytesTransferred;

@end
