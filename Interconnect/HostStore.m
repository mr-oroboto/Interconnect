//
//  HostStore.m
//  Interconnect
//
//  Created by jjs on 20/04/2016.
//  Copyright © 2016 oroboto. All rights reserved.
//

#import "HostStore.h"
#import "Node.h"
#import "Host.h"

#define kMaxVolume  0.3
#define kMinVolume  0.05

@interface HostStore ()

@property (nonatomic) NSUInteger largestBytesSeen;

@end

@implementation HostStore

#pragma mark - Initialisation

+ (instancetype)sharedStore
{
    static HostStore *sharedStore;
    static dispatch_once_t token;
    
    dispatch_once(&token, ^{
        sharedStore = [[self alloc] initPrivate];
    });
    
    return sharedStore;
}

- (instancetype)init
{
    [NSException raise:@"Singleton" format:@"Use +[HostStore sharedStore]"];
    return nil;
}

- (instancetype)initPrivate
{
    if (self = [super init])
    {
        _largestBytesSeen = 0.0;
    }
    
    return self;
}

#pragma mark - Host Management

- (void)updateHost:(NSString*)identifier withHopCount:(NSUInteger)hopCount addBytesIn:(NSUInteger)bytesIn addBytesOut:(NSUInteger)bytesOut
{
    Host* host = (Host*)[self node:identifier];
    
    // @todo: deal with hop count changes
    
    /**
     * A volume of kMaxVolume is reserved for the host(s) that have transferred the largest number of bytes,
     * the volume of all other nodes is based on the ratio of the number of bytes they have transferred vs
     * the number of bytes that the largest node has transferred.
     *
     * @todo:
     *
     * Node size is only reassessed when new bytes arrive so the sizing algorithm will sometimes show some 
     * older nodes as bigger than they should be: we should periodically sweep the nodes and recalculate the
     * size.
     */

    if ( ! host)
    {
        // All nodes will grow from 0.01 to their initial volume size anyway
        host = [Host createInOrbital:hopCount withIdentifier:identifier andVolume:0.01];
        [self addNode:host];
    }
    
    NSUInteger totalBytesTransferredByNode = [host bytesTransferred] + bytesIn + bytesOut;
    if ( ! _largestBytesSeen || totalBytesTransferredByNode > _largestBytesSeen)
    {
        _largestBytesSeen = totalBytesTransferredByNode;    // first host or newest largest host
        NSLog(@"New largest bytes seen: %lu for host %@", (unsigned long)_largestBytesSeen, identifier);
    }
    
    // We (localhost) are considered the source, so for another host bytesIn is bytes sent from us to them etc.
    [host setBytesReceived:[host bytesReceived] + bytesIn];
    [host setBytesSent:[host bytesSent] + bytesOut];
    
    NSLog(@"Host %@ sent us %lu bytes and received %lu bytes from us", identifier, [host bytesSent], [host bytesReceived]);
    
    float volume = (totalBytesTransferredByNode / _largestBytesSeen) * kMaxVolume;
    
    if (volume < kMinVolume)
    {
        NSLog(@"Capping volume at minimum of %.2f", kMinVolume);
        volume = kMinVolume;
    }

    [host setTargetVolume:volume];
}

- (void)updateHost:(NSString*)identifier withHopCount:(NSUInteger)hopCount
{
    Host* host = (Host*)[self node:identifier];

    if (host)
    {
        [super updateNode:host withOrbital:hopCount];
    }
}

@end