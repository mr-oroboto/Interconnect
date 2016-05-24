//
//  ICMPEchoProbeThread.m
//  Interconnect
//
//  Created by oroboto on 15/05/2016.
//  Copyright © 2016 oroboto. All rights reserved.
//

#import "ICMPTimeExceededProbeThread.h"
#import "ProbeThread+Private.h"
#import "ProbeThread+ProbeInterface.h"
#import "Probe.h"
#import "PacketHeaders.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <sys/types.h>
#import <netinet/ip.h>
#import <netinet/in_systm.h>
#import <netinet/ip_icmp.h>
#import <sys/select.h>
#import <sys/time.h>

#define kMaxAttemptsToFindUnusedPort            10
#define kBaseUDPPort                            30000
#define kCompleteTimedOutProbes                 YES

#define kMaxProbeTTL                            30
#define kMaxProbeFlightTimeMs                   10000
#define kMaxProbeRetries                        3

#define kRetriesExceeded                       -2
#define kError                                 -1
#define kSuccess                                0

typedef enum
{
    kNextHopIsDestination = 0,
    kNextHopIsRouter
} NextHopType;

#pragma pack(1)
struct payload
{
    uint16_t        sequence;
    unsigned char   ttl;
    time_t          time_sent;
    unsigned char   pad;
};
#pragma options align=reset

@interface ICMPTimeExceededProbeThread ()

@property (nonatomic) int icmpSocket;
@property (nonatomic) int udpSocket;
@property (nonatomic) NSMutableDictionary* probesByDstUDPPort;
@property (nonatomic) NSMutableDictionary* probesByHostIdentifier;

@end

@implementation ICMPTimeExceededProbeThread

- (instancetype)init
{
    if (self = [super init])
    {
        NSLog(@"ICMPTimeExceededProbeThread initialised");
        
        _probesByHostIdentifier = [[NSMutableDictionary alloc] init];
        _probesByDstUDPPort = [[NSMutableDictionary alloc] init];
        
        _icmpSocket = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP);
        if (_icmpSocket < 0)
        {
            NSLog(@"Could not create ICMP socket");
        }

        _udpSocket = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
        if (_udpSocket < 0)
        {
            NSLog(@"Could not create ICMP socket");
        }
    }
    
    return self;
}

- (int)getNativeSocket
{
    return self.icmpSocket;
}

- (void)sendProbe:(NSString*)toHostIdentifier onCompletion:(void (^)(Probe*))completionBlock retrying:(BOOL)retrying
{
    NSInteger sendStatus = [self sendPortUnreachableUDPPacketToIPAddress:toHostIdentifier onCompletion:completionBlock retrying:retrying];
    
    if (sendStatus == kRetriesExceeded && kCompleteTimedOutProbes)
    {
        Probe* probe = self.probesByHostIdentifier[toHostIdentifier];

        NSLog(@"*** COMPLETING TIMED OUT PROBE to %@", toHostIdentifier);
        if (probe.completionBlock)
        {
            probe.completionBlock(probe);
        }
    }
    
    if (sendStatus == kRetriesExceeded || sendStatus == kError)
    {
        [self resetProbe:toHostIdentifier allowRemovalOfInflightProbes:YES];
    }
}

/**
 * Reset probe status for a given host.
 *
 * This allows the host to be reprobed or the UDP port that was being used for probing that host to be reused.
 */
- (void)resetProbe:(NSString*)forHostIdentifier allowRemovalOfInflightProbes:(BOOL)allowRemovalInFlight
{
    Probe* probe = self.probesByHostIdentifier[forHostIdentifier];
    
    if (probe)
    {
        if (probe.inflight && ! allowRemovalInFlight)
        {
            NSLog(@"Cannot reset probe for %@ as the probe is still in flight", forHostIdentifier);
            return;
        }
        
        [self.probesByDstUDPPort removeObjectForKey:[NSNumber numberWithInt:probe.dstPort]];
        [self.probesByHostIdentifier removeObjectForKey:forHostIdentifier];
    }
}

/**
 * Send the (next) UDP packet to the host while ramping up the TTL in order to effect a UDP based traceroute.
 */
- (NSInteger)sendPortUnreachableUDPPacketToIPAddress:(NSString*)ipAddress onCompletion:(void (^)(Probe*))completionBlock retrying:(BOOL)retrying
{
    /**
     * Have we already sent a UDP packet to this IP address? If so, it could be because we're in the middle of a traceroute,
     * but it could also be because we've already finished a complete traceroute to the host.
     */
    Probe* probe = nil;
    
    if ((probe = self.probesByHostIdentifier[ipAddress]))
    {
        NSLog(@"Host %@ already exists (sequence: %hu, currentTTL: %hhu), sending next probe", ipAddress, probe.sequenceNumber, probe.currentTTL);
        
        if (probe.complete)
        {
            // Must call resetProbe: if we want to reprobe the host.
            [NSException raise:@"sendPortUnreachableUDPPacketToIPAddress" format:@"Cannot send probe to %@ as we have already completed a full probe for it.", ipAddress];
        }

        if ( ! retrying)
        {
            if (probe.inflight)
            {
                [NSException raise:@"sendPortUnreachableUDPPacketToIPAddress" format:@"Cannot send UDP packet to %@ as there is already a packet in flight", ipAddress];
            }

            // Get ready to send the next probe to find the next hop (otherwise we're retrying last hop)
            probe.sequenceNumber++;
            probe.currentTTL++;
            probe.retries = 0;              // reset retry count, it's per hop
        }
        else
        {
            if (++probe.retries > kMaxProbeRetries)
            {
                NSLog(@"Retry limit (%d) exceeded for %@", kMaxProbeRetries, probe.hostIdentifier);
                return kRetriesExceeded;
            }
            
            // Need to change the destination port in case the response comes back (if it does, we should ignore it)
            [self.probesByDstUDPPort removeObjectForKey:[NSNumber numberWithInt:probe.dstPort]];
            
            probe.dstPort = [self generateDestinationPortForProbe];
            if ( ! probe.dstPort)
            {
                NSLog(@"Could not resend probe to %@ as an unused UDP port is not available", ipAddress);
                return kError;
            }
            
            self.probesByDstUDPPort[[NSNumber numberWithInt:probe.dstPort]] = probe;
        }
        
        if (probe.currentTTL > kMaxProbeTTL)
        {
            NSLog(@"TTL exceeded for %@", probe.hostIdentifier);
            return kRetriesExceeded;        // this ensures we complete the probe (if set) at the maximum TTL
        }
    }
    else
    {
        uint16_t dstPort = [self generateDestinationPortForProbe];
        if ( ! dstPort)
        {
            NSLog(@"Could not send probe to %@ as an unused UDP port is not available", ipAddress);
            return kError;
        }
        
        probe = [[Probe alloc] init];

        probe.hostIdentifier = ipAddress;
        probe.dstPort = dstPort;
        probe.sequenceNumber = 0;
        probe.currentTTL = 1;
        probe.retries = 0;
        probe.complete = NO;
        probe.completionBlock = completionBlock;
        
        self.probesByHostIdentifier[ipAddress] = probe;
        self.probesByDstUDPPort[[NSNumber numberWithInt:probe.dstPort]] = probe;
    }
    
    struct sockaddr_in dstAddr;
    memset(&dstAddr, 0, sizeof(dstAddr));
    dstAddr.sin_family = AF_INET;
    dstAddr.sin_port = htons(probe.dstPort);
    dstAddr.sin_addr.s_addr = inet_addr([ipAddress cStringUsingEncoding:NSASCIIStringEncoding]);
    
    // Create UDP packet (IP header + UDP header + payload)
    NSMutableData* payload = [NSMutableData dataWithLength:sizeof(struct payload)];
    struct payload* pPayload = (struct payload*)[payload mutableBytes];
    assert([payload length] == sizeof(struct payload));
    pPayload->sequence = htons(probe.sequenceNumber);
    pPayload->ttl = probe.currentTTL;
    
    time_t timer = time(NULL);
    pPayload->time_sent = htonl(timer);
    
    NSMutableData* packet = [NSMutableData dataWithLength:[payload length]];
    if ( ! packet)
    {
        NSLog(@"Failed to create UDP request packet");
        return kError;
    }
    
    // Set the appropriate TTL
    int ttl = probe.currentTTL;
    if (setsockopt(self.udpSocket, IPPROTO_IP, IP_TTL, &ttl, sizeof(ttl)) < 0)
    {
        NSLog(@"Could not set IP TTL on UDP socket: %s", strerror(errno));
        return kError;
    }
    
    // Send it
    struct timeval timeSent;
    if (gettimeofday(&timeSent, NULL))
    {
        NSLog(@"Could not get send time");
        return kError;
    }
    probe.timeSent = timeSent;
    probe.inflight = YES;

    ssize_t bytesSent = sendto(self.udpSocket, [packet bytes], [packet length], 0, (struct sockaddr*)&dstAddr, sizeof(dstAddr));
    if (bytesSent < [packet length])
    {
        NSLog(@"Failed while sending UDP echo request (%lu bytes sent): %s", bytesSent, strerror(errno));
        return kError;
    }
    
    NSLog(@"Sent UDP probe with TTL %u (seq: %u) to %@:%hu (payload length: %lu)", probe.currentTTL, probe.sequenceNumber, probe.hostIdentifier, probe.dstPort, (unsigned long)[payload length]);
    
    return kSuccess;
}

/**
 * Data is available to read on the ICMP socket, should be either ICMP time exceeded (we hit a router) or ICMP port unreachable (we hit the host)
 */
- (void)processIncomingSocketData
{
    switch ([self readICMPResponse])
    {
        case kNextHopIsDestination:
            break;
            
        case kNextHopIsRouter:
            break;
            
        case kError:
            break;
    }
}

- (NSInteger)readICMPResponse
{
    NSMutableData *packetRecv = [NSMutableData dataWithLength:65535];
    ssize_t bytesNeeded;
    
    /**
     * Returned ICMP time exceeded or destination unreachable packet should contain IP header, ICMP header, sent IP 
     * header and 8 bytes of sent UDP datagram. It may also include our payload (12 bytes) but this is highly router 
     * dependant and we do not require it.
     */
    bytesNeeded = sizeof(struct hdr_ip) + 8 /* icmp hdr */ + sizeof(struct hdr_ip) + sizeof(struct hdr_udp);

    // @todo: support reading partial packets as per ICMPTimeExceededProbe
    
    struct sockaddr srcAddr;
    socklen_t srcAddrLen = sizeof(srcAddr);
    ssize_t bytesRead = recvfrom(self.icmpSocket, [packetRecv mutableBytes], [packetRecv length], 0, &srcAddr, &srcAddrLen);
    if (bytesRead <= 0)
    {
        NSLog(@"Failed to read packet from socket");
        return kError;
    }
    
    struct timeval timeRecv;
    if (gettimeofday(&timeRecv, NULL))
    {
        NSLog(@"Could not get receive time");
        return kError;
    }
    
//  NSLog(@"Read %lu bytes from %s", bytesRead, inet_ntoa(((struct sockaddr_in*)&srcAddr)->sin_addr));
    
    // Does this look like a valid ICMP error response? The returned packet will include the IP header.
    if (bytesRead < bytesNeeded)
    {
        NSLog(@"Received packet was not long enough to be an ICMP error response");
        return kError;
    }
    
    struct hdr_ip* ipHdr = (struct hdr_ip*)[packetRecv bytes];
    if (IP_VERSION(ipHdr) != 0x04)
    {
        NSLog(@"Received packet was not IPv4");
        return kError;
    }
    
    if (ipHdr->ip_proto != IPPROTO_ICMP)
    {
        NSLog(@"Received packet was not ICMP");
        return kError;
    }
    
    // Validate the checksum
    struct icmp* icmpRecvHdr = (struct icmp*)((unsigned char*)[packetRecv mutableBytes] + IP_HDR_LEN(ipHdr));
    
    /**
     * NOTE: Unprivileged ICMP sockets contain two IP header fields that are converted by the kernel to host byte order
     *       on reception (even though they're in NBO on the wire). We must convert them back in order for the checksum
     *       to match (we only need to do this in the reflected IP header contained in the data section of the ICMP packet
     *       itself because we're calculating the ICMP checksum only over the ICMP portion of the packet, not including
     *       the wrapping received IP header).
     */
    struct hdr_ip* ipHdrReflected = (struct hdr_ip*)((unsigned char*)[packetRecv mutableBytes] + IP_HDR_LEN(ipHdr) + 8 /* skip over ICMP header */);
    ipHdrReflected->ip_len = htons(ipHdrReflected->ip_len);
    ipHdrReflected->ip_flags_offset = htons(ipHdrReflected->ip_flags_offset);
    
    uint16_t checksumRecv = icmpRecvHdr->icmp_cksum;
    icmpRecvHdr->icmp_cksum = 0;    // if left at received value the checksum should compute as 0
    unsigned short checksumNeeded = [self internetChecksum:(unsigned char*)icmpRecvHdr length:(bytesRead - IP_HDR_LEN(ipHdr))];
    
    if (checksumRecv != checksumNeeded)
    {
        NSLog(@"Received ICMP packet had incorrect checksum %04X (needed %04X)", checksumRecv, checksumNeeded);
        return kError;
    }
    
    // Is this a time exceeded or port unreachable?
    if (icmpRecvHdr->icmp_type != ICMP_TIMXCEED && icmpRecvHdr->icmp_type != ICMP_UNREACH_PORT)
    {
        NSLog(@"Received ICMP packet was not time exceeded or port unreachable (type: %X)", icmpRecvHdr->icmp_type);
        return kError;
    }
    
    // @todo: verification of payload
    NSLog(@"Received ICMP %@ from %s", icmpRecvHdr->icmp_type == ICMP_TIMXCEED ? @"time exceeded" : @"port unreachable", inet_ntoa(((struct sockaddr_in*)&srcAddr)->sin_addr));

    struct hdr_udp* udpHdrReflected = (struct hdr_udp*)((unsigned char*)[packetRecv mutableBytes] + IP_HDR_LEN(ipHdr) + 8 /* skip over ICMP header */ + IP_HDR_LEN(ipHdrReflected));

    // Try to find the probe that generated this response
    uint16_t dstPort = ntohs(udpHdrReflected->udp_dport);
    Probe* probe;
    
    if ((probe = self.probesByDstUDPPort[[NSNumber numberWithInt:dstPort]]))
    {
//      NSLog(@"Found probe record for UDP port %hu and host %@ (actual host: %s)", probe.dstPort, probe.hostIdentifier, inet_ntoa(((struct sockaddr_in*)&srcAddr)->sin_addr));
        probe.inflight = NO;

        if (icmpRecvHdr->icmp_type == ICMP_TIMXCEED)
        {
            // We hit a router, keep going.
            if ([self sendPortUnreachableUDPPacketToIPAddress:probe.hostIdentifier onCompletion:nil retrying:NO] != kError)
            {
                return kNextHopIsRouter;
            }
        }
        else
        {
            // End of the line.
            probe.complete = YES;

            // Calculate the number of ms elapsed between send and receive
            probe.rttToHost = [self msElapsedBetween:probe.timeSent endTime:timeRecv];
            
            NSLog(@"Finished traceroute %@ (hops: %hhu, RTT: %.2fms)", probe.hostIdentifier, probe.currentTTL, probe.rttToHost);
            
            if (probe.completionBlock)
            {
                probe.completionBlock(probe);
            }

            return kNextHopIsDestination;
        }
    }
    else
    {
        NSLog(@"Could not find probe record for UDP port %hu", dstPort);
    }

    return kError;
}

- (void)cleanupProbes
{
    struct timeval now;
    if (gettimeofday(&now, NULL))
    {
        NSLog(@"Cannot determine time to cleanup probes");
        return;
    }

    NSArray* keys = self.probesByHostIdentifier.allKeys;
    
    for (NSString* hostIdentifier in keys)
    {
        Probe* probe = self.probesByHostIdentifier[hostIdentifier];
        
        if (probe.complete)
        {
            NSLog(@"Removing complete probe %@", probe.hostIdentifier);
            [self resetProbe:probe.hostIdentifier allowRemovalOfInflightProbes:NO];
        }
        else if ([self msElapsedBetween:probe.timeSent endTime:now] > kMaxProbeFlightTimeMs)
        {
            // This will remove or complete (depending on kCompleteTimedOutProbes) the probe if the number of retries has been exceeded
            NSLog(@"Retry (%d) for hop %u for timed out probe %@", probe.retries + 1, probe.currentTTL, probe.hostIdentifier);
            [self sendProbe:probe.hostIdentifier onCompletion:probe.completionBlock retrying:YES];
        }
    }
}

- (uint16_t)generateDestinationPortForProbe
{
    uint16_t dstPort, attempts = 0;
    
    do
    {
        dstPort = kBaseUDPPort + (arc4random() % (65535 - kBaseUDPPort));
        NSNumber *portKey = [NSNumber numberWithInt:dstPort];
        
        // Have we already sent a probe to this port? If so, we can only reuse it if the probe is complete.
        if (self.probesByDstUDPPort[[NSNumber numberWithInt:dstPort]])
        {
            Probe* existingProbe = self.probesByDstUDPPort[portKey];
            if (existingProbe.complete)
            {
                // Good, we can reuse this port.
                [self resetProbe:existingProbe.hostIdentifier allowRemovalOfInflightProbes:NO];
            }
            else
            {
                dstPort = 0;
            }
        }
        
        attempts++;
    } while ( ! dstPort && attempts < kMaxAttemptsToFindUnusedPort);

    return dstPort;
}

@end
