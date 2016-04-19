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

- (void)addNode:(Node*)node;
- (void)updateNode:(Node*)node withOrbital:(NSUInteger)orbital;
- (Node*)node:(NSString*)identifier;
- (NSDictionary*)inhabitedOrbitals;

@end
