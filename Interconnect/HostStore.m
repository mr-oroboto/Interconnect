//
//  HostStore.m
//  Interconnect
//
//  Created by oroboto on 20/04/2016.
//  Copyright © 2016 oroboto. All rights reserved.
//

#import "HostStore.h"
#import "Node.h"
#import "Host.h"

#define kMaxVolume      0.3
#define kMinVolume      0.05
#define kMaxHostGroups  12
#define kShowOriginConnectorOnTrafficUpdate YES

typedef enum
{
    kPreferredColourBasedProtocol = 0,      // set node preferred colour based on first protocol we saw it use
    kPreferredColourBaseAS                  // set node preferred colour based on its AS (@todo)
} PreferredColourMode;

@interface HostStore ()

@property (nonatomic) NSUInteger largestBytesSeen;              // what is the largest number of bytes we seen a host transfer? (used for sizing)

@property (nonatomic) PreferredColourMode preferredColorMode;   // how should a host's preferred colour be set?
@property (nonatomic) NSDictionary* protocolColourMap;          // when colouring based on protocol, use these colours

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
        _largestBytesSeen = 0;

        _protocolColourMap = @{
                               @0:   @[@0.3, @0.3, @0.3],         // non-TCP
                               @20:  @[@0.87, @0.0, @0.49],       // ftp-data
                               @21:  @[@0.87, @0.0, @0.49],       // ftp
                               @22:  @[@0.48, @0.62, @0.20],      // ssh
                               @23:  @[@0.48, @0.62, @0.20],      // telnet
                               @25:  @[@1.0, @0.99, @0.0],        // smtp
                               @43:  @[@0.1, @0.1, @0.1],         // whois
                               @80:  @[@0.21, @0.0, @0.80],       // http
                               @110: @[@1.0, @0.99, @0.0],        // pop3
                               @137: @[@0.13, @0.40, @0.40],      // netbios name
                               @138: @[@0.13, @0.40, @0.40],      // netbios data
                               @139: @[@0.13, @0.40, @0.40],      // netbios session
                               @143: @[@1.0, @0.99, @0.0],        // imap
                               @443: @[@0.21, @0.0, @0.80],       // ssl
        };
        
        /**
         * If hosts will be coloured based on their preferred colour (which is up to the renderer) then
         * how do we determine what their preferred colour is?
         */
        _preferredColorMode = kPreferredColourBasedProtocol;
        
        /**
         * How will hosts be grouped?
         */
        _groupingStrategy = kHostStoreGroupBasedOnNetworkClass;
        
        _showOriginConnectorOnTrafficUpdate = kShowOriginConnectorOnTrafficUpdate;
    }
    
    return self;
}

#pragma mark - Host Management

- (BOOL)updateHostBytesTransferred:(NSString*)identifier addBytesIn:(NSUInteger)bytesIn addBytesOut:(NSUInteger)bytesOut port:(NSUInteger)port
{
    BOOL hostCreated = NO;
    
    [self lockStore];

    Host* host = (Host*)[self node:identifier];
    
    if ( ! host)
    {
        // All nodes start off in the first orbital (grouping occurs when more details are known) unless grouping by net class
        NSUInteger hostGroup = 1;
        if (self.groupingStrategy == kHostStoreGroupBasedOnNetworkClass)
        {
            hostGroup = [self hostGroupBasedOnNetworkClass:identifier];     // @dragon: assumes identifiers are always IPv4 addresses
        }

        // All nodes will grow from 0.01 to their initial volume size
        host = [Host createInGroup:hostGroup withIdentifier:identifier andVolume:0.01];
        host.ipAddress = identifier;
        host.originConnector = 2.0;
        host.firstPortSeen = port;
        
        if (self.preferredColorMode == kPreferredColourBasedProtocol)
        {
            // Do we have a preferred colour for the protocol?
            NSNumber* portNumber = [NSNumber numberWithUnsignedInteger:port];
            NSArray* preferredColour = self.protocolColourMap[portNumber];

            if (preferredColour)
            {
                host.preferredRed = [preferredColour[0] floatValue];
                host.preferredGreen = [preferredColour[1] floatValue];
                host.preferredBlue = [preferredColour[2] floatValue];
            }
        }

        [self addNode:host];
        hostCreated = YES;
    }
    else if (self.showOriginConnectorOnTrafficUpdate)
    {
        host.originConnector = 1.0;
    }
    
    /**
     * A volume of kMaxVolume is reserved for the host(s) that have transferred the largest number of bytes,
     * the volume of all other nodes is based on the ratio of the number of bytes they have transferred vs
     * the number of bytes that the largest node has transferred.
     */

    NSUInteger totalBytesTransferredByNode = [host bytesTransferred] + bytesIn + bytesOut;
    if ( ! self.largestBytesSeen || totalBytesTransferredByNode > self.largestBytesSeen)
    {
        self.largestBytesSeen = totalBytesTransferredByNode;    // first host or newest largest host
//      NSLog(@"New largest bytes seen: %lu for host %@", (unsigned long)_largestBytesSeen, identifier);
    }
    
    // We (localhost) are considered the source, so for another host bytesIn is bytes sent from us to them etc.
    [host setBytesReceived:[host bytesReceived] + bytesIn];
    [host setBytesSent:[host bytesSent] + bytesOut];
    
//  NSLog(@"Host %@ sent us %lu bytes and received %lu bytes from us", identifier, [host bytesSent], [host bytesReceived]);
    
    float volume = (totalBytesTransferredByNode / self.largestBytesSeen) * kMaxVolume;
    
    if (volume < kMinVolume)
    {
//      NSLog(@"Capping volume at minimum of %.2f", kMinVolume);
        volume = kMinVolume;
    }

    [host setTargetVolume:volume];
    
    [self unlockStore];
    
    return hostCreated;
}

/**
 * This method can be periodically called to resize the node set based on the number of bytes the host has 
 * transferred vs the largest number of bytes we've ever seen transferred by a host. This is required because
 * host resizing only occurs when new bytes are seen: old hosts won't ever be appropriately resized.
 */
- (void)recalculateHostSizesBasedOnBytesTransferred
{
    [self lockStore];
    
    NSDictionary* hosts = [self nodes];
    
    for (id hostIdentifier in hosts)
    {
        Host* host = hosts[hostIdentifier];
        
        float volume = ([host bytesTransferred] / self.largestBytesSeen) * kMaxVolume;
            
        if (volume < kMinVolume)
        {
           volume = kMinVolume;
        }
            
        [host setTargetVolume:volume];
    }
    
    [self unlockStore];
}

- (void)updateHost:(NSString*)identifier withName:(NSString*)name
{
    [self lockStore];
    
    Host* host = (Host*)[self node:identifier];
    if (host)
    {
        [host setHostname:name];
    }
    
    [self unlockStore];
}

- (void)updateHost:(NSString*)identifier withAS:(NSString*)as andASDescription:(NSString*)asDesc
{
    [self lockStore];
    
    Host* host = (Host*)[self node:identifier];
    if (host)
    {
        [host setAutonomousSystem:as];
        [host setAutonomousSystemDesc:asDesc];
    }
    
    [self unlockStore];
    
    if (self.groupingStrategy == kHostStoreGroupBasedOnAS)
    {
        NSUInteger hostGroup = [self hostGroupBasedOnAS:as];
        NSLog(@"Updating host %@ group to %lu based on %@", identifier, hostGroup, as);
        [self updateHost:identifier withGroup:hostGroup];
    }
}

- (void)updateHost:(NSString*)identifier withRTT:(float)rtt andHopCount:(NSInteger)hopCount
{
    [self lockStore];
    
    Host* host = (Host*)[self node:identifier];
    if (host)
    {
        if (rtt > 0)
        {
            host.rtt = rtt;
        }
        
        if (hopCount > 0)
        {
            host.hopCount = hopCount;
        }
    }
    
    [self unlockStore];

    if (rtt > 0 && self.groupingStrategy == kHostStoreGroupBasedOnRTT)
    {
        NSUInteger hostGroup = [self hostGroupBasedOnRTT:rtt];
        NSLog(@"Updating host %@ group to %lu based on RTT of %.2fms", identifier, hostGroup, rtt);
        [self updateHost:identifier withGroup:hostGroup];
    }
    else if (hopCount > 0 && self.groupingStrategy == kHostStoreGroupBasedOnHopCount)
    {
        NSUInteger hostGroup = [self hostGroupBasedOnHopCount:hopCount];
        NSLog(@"Updating host %@ group to %ld based on hop count %ld", identifier, hostGroup, hopCount);
        [self updateHost:identifier withGroup:hostGroup];
    }
}

#pragma mark - Group Management

- (NSUInteger)hostGroupBasedOnRTT:(float)rtt
{
    NSUInteger hostGroup = (rtt / 50.0) + 1;      // 50ms bands
    
    if (hostGroup > kMaxHostGroups)
    {
        hostGroup = kMaxHostGroups;
    }

    return hostGroup;
}

- (NSUInteger)hostGroupBasedOnHopCount:(NSUInteger)hopCount
{
    if (hopCount > kMaxHostGroups)
    {
        hopCount = kMaxHostGroups;
    }
    
    if (hopCount == 0)
    {
        hopCount = 1;
    }

    return hopCount;
}

- (NSUInteger)hostGroupBasedOnAS:(NSString*)as
{
    NSUInteger hostGroup = [as integerValue] % kMaxHostGroups;

    if (hostGroup == 0)
    {
        hostGroup = 1;
    }
    
    return hostGroup;
}

- (NSUInteger)hostGroupBasedOnNetworkClass:(NSString*)ipAddress
{
    // At present this just groups hosts based on the first 8 bits of their network address (modulo max groups)
    NSArray* dottedQuads = [ipAddress componentsSeparatedByString:@"."];
    
    if (dottedQuads.count != 4)
    {
        NSLog(@"Cannot determine host group for IP address %@", ipAddress);
        return 1;
    }
    
    return ([dottedQuads[0] integerValue] % kMaxHostGroups + 1);
}

/**
 * Hosts can be grouped based on common attributes (ie. their hop count from us, the average RTT to them, their AS etc).
 *
 * Host groups are implemented as orbitals, hosts in the same group appear in the same orbital.
 */
- (void)updateHost:(NSString*)identifier withGroup:(NSUInteger)group
{
    [self lockStore];
    
    Host* host = (Host*)[self node:identifier];
    if (host)
    {
        [super updateNode:host withOrbital:group];
    }
    
    [self unlockStore];
}

- (void)regroupHostsBasedOnStrategy:(HostStoreGroupingStrategy)strategy
{
    [self lockStore];
    
    NSDictionary* hosts = [self nodes];
    
    for (id hostIdentifier in hosts)
    {
        Host* host = hosts[hostIdentifier];
        NSUInteger hostGroup = 1;       // default if host does not have enough information for grouping
        
        switch (strategy)
        {
            case kHostStoreGroupBasedOnHopCount:
                hostGroup = [self hostGroupBasedOnHopCount:host.hopCount];
                break;
                
            case kHostStoreGroupBasedOnRTT:
                hostGroup = [self hostGroupBasedOnRTT:host.rtt];
                break;
                
            case kHostStoreGroupBasedOnAS:
                hostGroup = [self hostGroupBasedOnAS:host.autonomousSystem];
                break;
                
            case kHostStoreGroupBasedOnNetworkClass:
                hostGroup = [self hostGroupBasedOnNetworkClass:host.ipAddress];
                break;
                
            default:
                NSLog(@"Unknown grouping strategy, will not regroup hosts");
        }

        [super updateNode:host withOrbital:hostGroup];
    }

    self.groupingStrategy = strategy;

    [self unlockStore];
}

- (void)resetStore
{
    [self lockStore];

    [self clearNodes];
    self.largestBytesSeen = 0;

    [self unlockStore];
}

@end
