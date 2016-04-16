//
//  NodeStore.h
//  Interconnect
//
//  Created by oroboto on 16/04/2016.
//  Copyright © 2016 oroboto. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class Node;

@interface NodeStore : NSObject

+ (instancetype)sharedStore;

- (void)addNode:(Node*)node;
- (NSDictionary*)inhabitedOrbitals;

@end
