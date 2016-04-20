//
//  NodeStore.m
//  Interconnect
//
//  Created by oroboto on 16/04/2016.
//  Copyright © 2016 oroboto. All rights reserved.
//

#import "NodeStore.h"
#import "Node.h"

@interface NodeStore ()

@property (nonatomic, strong) NSMutableDictionary* orbitals;
@property (nonatomic, strong) NSMutableDictionary* nodes;
@property (nonatomic, strong) NSLock* lock;

@end

@implementation NodeStore

#pragma mark - Initialisation

- (instancetype)init
{
    if (self = [super init])
    {
        _orbitals = [[NSMutableDictionary alloc] init];
        _nodes = [[NSMutableDictionary alloc] init];
        _lock = [[NSLock alloc] init];
    }
    
    return self;
}

#pragma mark - Synchronisation

- (void)lockStore
{
    [self.lock lock];
}

- (void)unlockStore
{
    [self.lock unlock];
}

#pragma mark - Node Management

- (void)addNode:(Node*)node
{
    // Do we already have this node? If so, this is a no-op (even if the orbital is different).
    if ([self node:node.identifier])
    {
        NSLog(@"%@ already exists in store, not adding", node.identifier);
        return;
    }
    
    self.nodes[node.identifier] = node;

    // Do we already have nodes in this orbital?
    NSNumber* orbitalName = [NSNumber numberWithUnsignedInteger:node.orbital];
    if (self.orbitals[orbitalName])
    {
        NSMutableArray* orbitalNodes = self.orbitals[orbitalName];
        [orbitalNodes addObject:node];
    }
    else
    {
        NSLog(@"Creating new orbital: %@", orbitalName);
        self.orbitals[orbitalName] = [[NSMutableArray alloc] initWithObjects:node, nil];
    }
}

- (void)updateNode:(Node*)node withOrbital:(NSUInteger)orbital
{
    NSNumber* oldOrbitalName = [NSNumber numberWithUnsignedInteger:node.orbital];
    NSNumber* newOrbitalName = [NSNumber numberWithUnsignedInteger:orbital];

    // Remove the node from its current orbital
    [self.orbitals[oldOrbitalName] removeObject:node];
    
    // Add the new to its new orbital
    if (self.orbitals[newOrbitalName])
    {
        NSMutableArray* orbitalNodes = self.orbitals[newOrbitalName];
        [orbitalNodes addObject:node];
    }
    else
    {
        NSLog(@"Creating new orbital: %@", newOrbitalName);
        self.orbitals[newOrbitalName] = [[NSMutableArray alloc] initWithObjects:node, nil];
    }
    
    node.orbital = orbital;
}

- (Node*)node:(NSString*)identifier
{
    return self.nodes[identifier];
}

- (NSDictionary*)inhabitedOrbitals
{
    return self.orbitals;
}

@end
