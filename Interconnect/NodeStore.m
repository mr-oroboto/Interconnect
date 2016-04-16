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

@end

@implementation NodeStore

#pragma mark - Initialisation

+ (instancetype)sharedStore
{
    static NodeStore *sharedStore;
    static dispatch_once_t token;
    
    dispatch_once(&token, ^{
        sharedStore = [[self alloc] initPrivate];
    });
    
    return sharedStore;
}

- (instancetype)init
{
    [NSException raise:@"Singleton" format:@"Use +[NodeStore sharedStore]"];
    return nil;
}

- (instancetype)initPrivate
{
    if (self = [super init])
    {
        _orbitals = [[NSMutableDictionary alloc] init];
        _nodes = [[NSMutableDictionary alloc] init];
    }
    
    return self;
}

#pragma mark - Node Management

- (void)addNode:(Node*)node
{
    // Do we already have this node? If so, this is a no-op (even if the orbital is different).
    if (self.nodes[node.identifier])
    {
        NSLog(@"%@ already exists in store, not adding", node.identifier);
        return;
    }

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

- (NSDictionary*)inhabitedOrbitals
{
    return self.orbitals;
}

@end
