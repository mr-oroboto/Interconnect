//
//  NodeStore.h
//  Interconnect
//
//  Do not call methods on this class directly, use a subclass such as HostStore to ensure thread safety.
//
//  @todo: Move the below interface into a private category for subclasses.
//
//  Created by oroboto on 16/04/2016.
//  Copyright © 2016 oroboto. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class Node;

@interface NodeStore : NSObject

- (void)addNode:(Node*)node;
- (void)updateNode:(Node*)node withOrbital:(NSUInteger)orbital;
- (Node*)node:(NSString*)identifier;
- (NSDictionary*)inhabitedOrbitals;
- (NSDictionary*)nodes;

- (void)lockStore;
- (void)unlockStore;

@end
