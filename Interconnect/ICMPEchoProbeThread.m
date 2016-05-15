//
//  ICMPEchoProbeThread.m
//  Interconnect
//
//  Created by oroboto on 15/05/2016.
//  Copyright © 2016 oroboto. All rights reserved.
//

#import "ICMPEchoProbeThread.h"
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

#define kICMPEchoProbePayloadBytes 56

@interface ICMPEchoProbeThread ()

@property (nonatomic) int socket;
@property (nonatomic) NSMutableDictionary* probesByICMPIdentifier;
@property (nonatomic) NSMutableDictionary* probesByHostIdentifier;

@end

@implementation ICMPEchoProbeThread

- (instancetype)init
{
    if (self = [super init])
    {
        NSLog(@"ICMPEchoProbeThread initialised");
        
        _probesByHostIdentifier = [[NSMutableDictionary alloc] init];
        _probesByICMPIdentifier = [[NSMutableDictionary alloc] init];
        
        _socket = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP);
        if (_socket < 0)
        {
            NSLog(@"Could not create ICMP socket");
        }
    }
    
    return self;
}

- (int)getNativeSocket
{
    return self.socket;
}

- (void)sendProbe:(NSString*)toHostIdentifier
{
    [self pingIPAddress:toHostIdentifier];
}

- (NSInteger)pingIPAddress:(NSString*)ipAddress
{
    NSLog(@"Sending ICMP ping to %@", ipAddress);
    
    // Have we already sent a probe to this host?
    Probe* probe = nil;
    
    if ((probe = self.probesByHostIdentifier[ipAddress]))
    {
        NSLog(@"Host %@ already exists (identifier: %hu, sequence: %hu)", ipAddress, probe.icmpIdentifier, probe.sequenceNumber);
        
        if (probe.inflight)
        {
            [NSException raise:@"pingIPAddress" format:@"Cannot send probe to %@ as there is already a probe in flight", ipAddress];
        }

        // Ensure we never send anything else with this sequence number and ID combination
        probe.sequenceNumber++;
    }
    else
    {
        probe = [[Probe alloc] init];

        probe.hostIdentifier = ipAddress;
        probe.icmpIdentifier = arc4random();
        probe.sequenceNumber = 0;

        self.probesByHostIdentifier[ipAddress] = probe;
        self.probesByICMPIdentifier[[NSNumber numberWithInt:probe.icmpIdentifier]] = probe;
    }
    
    struct sockaddr_in dstAddr;
    memset(&dstAddr, 0, sizeof(dstAddr));
    dstAddr.sin_family = AF_INET;
    dstAddr.sin_addr.s_addr = inet_addr([ipAddress cStringUsingEncoding:NSASCIIStringEncoding]);

    // Create ICMP packet (header + payload, 56 byte payload is standard)
    NSData* payload = [[NSString stringWithFormat:@"%32zd echoes in an empty room", probe.sequenceNumber] dataUsingEncoding:NSASCIIStringEncoding];
    assert([payload length] == 56);
    
    NSMutableData* packet = [NSMutableData dataWithLength:sizeof(struct icmp) + [payload length]];
    if ( ! packet)
    {
        NSLog(@"Failed to create ICMP echo request packet");
        return -1;
    }

    struct icmp* icmpSendHdr;
    icmpSendHdr = [packet mutableBytes];
    icmpSendHdr->icmp_type = ICMP_ECHO;
    icmpSendHdr->icmp_code = 0;
    icmpSendHdr->icmp_cksum = 0;      // must be 0 for checksum calculation to work correctly
    icmpSendHdr->icmp_hun.ih_idseq.icd_id = htons(probe.icmpIdentifier);
    icmpSendHdr->icmp_hun.ih_idseq.icd_seq = htons(probe.sequenceNumber);
    memcpy(&icmpSendHdr[1], [payload bytes], [payload length]);
    
    // Calculate the ICMP checksum (no need for endian swap, checksum calculated appropriately)
    icmpSendHdr->icmp_cksum = [self internetChecksum:(unsigned char*)[packet bytes] length:[packet length]];
    
    // Send it
    struct timeval timeSent;
    if (gettimeofday(&timeSent, NULL))
    {
        NSLog(@"Could not get send time");
        return -1;
    }
    probe.timeSent = timeSent;
    probe.inflight = YES;
    
    ssize_t bytesSent = sendto(self.socket, [packet bytes], [packet length], 0, (const struct sockaddr*)&dstAddr, sizeof(dstAddr));
    if (bytesSent < [packet length])
    {
        NSLog(@"Failed while sending ICMP echo request (%lu bytes sent)", bytesSent);
        return -1;
    }
    
    NSLog(@"Sent ICMP echo request with ID %u (seq: %hu) to %@", probe.icmpIdentifier, probe.sequenceNumber, probe.hostIdentifier);

    return 0;
}

- (void)processIncomingSocketData
{
    float rtt = [self readICMPResponse];
    NSLog(@"RTT was %.2f", rtt);
}

- (float)readICMPResponse
{
    NSMutableData *packetRecv = [NSMutableData dataWithLength:65535];

    struct sockaddr srcAddr;
    socklen_t srcAddrLen = sizeof(srcAddr);
    ssize_t bytesRead = recvfrom(self.socket, [packetRecv mutableBytes], [packetRecv length], 0, &srcAddr, &srcAddrLen);
    if (bytesRead <= 0)
    {
        NSLog(@"Failed to read packet from socket");
        return -1;
    }
    
    NSLog(@"Read %lu bytes from %s", bytesRead, inet_ntoa(((struct sockaddr_in*)&srcAddr)->sin_addr));

    struct timeval timeRecv;
    if (gettimeofday(&timeRecv, NULL))
    {
        NSLog(@"Could not get receive time");
        return -1;
    }
    
    // Does this look like a valid ICMP echo response? The returned packet will include the IP header.
    if (bytesRead < (sizeof(struct hdr_ip) + sizeof(struct icmp)))
    {
        NSLog(@"Received packet was not long enough to be an ICMP echo response");
        return -1;
    }
    
    struct hdr_ip* ipHdr = (struct hdr_ip*)[packetRecv bytes];
    if (IP_VERSION(ipHdr) != 0x04)
    {
        NSLog(@"Received packet was not IPv4");
        return -1;
    }
    
    if (ipHdr->ip_proto != IPPROTO_ICMP)
    {
        NSLog(@"Received packet was not ICMP");
        return -1;
    }
    
    if (bytesRead < IP_HDR_LEN(ipHdr) + sizeof(struct icmp))
    {
        NSLog(@"Received packet was not long enough to contain full ICMP header");
        return -1;
    }
    
    // Validate the checksum
    struct icmp* icmpRecvHdr = (struct icmp*)((unsigned char*)[packetRecv bytes] + IP_HDR_LEN(ipHdr));
    uint16_t checksumRecv = icmpRecvHdr->icmp_cksum;
    icmpRecvHdr->icmp_cksum = 0;
    uint16_t checksumNeeded = [self internetChecksum:(unsigned char*)icmpRecvHdr length:(bytesRead - IP_HDR_LEN(ipHdr))];
    
    if (checksumRecv != checksumNeeded)
    {
        NSLog(@"Received ICMP packet had incorrect checksum %X (needed %X)", checksumRecv, checksumNeeded);
        return -1;
    }
    
    // Is this an echo response?
    if (icmpRecvHdr->icmp_type != ICMP_ECHOREPLY || icmpRecvHdr->icmp_code != 0)
    {
        NSLog(@"Received ICMP packet was not an ECHO reply");
        return -1;
    }
    
    // Try to find the probe that generated this response
    uint16_t icmpIdentifier = ntohs(icmpRecvHdr->icmp_hun.ih_idseq.icd_id);
    Probe* probe;
    
    if ((probe = self.probesByICMPIdentifier[[NSNumber numberWithInt:icmpIdentifier]]))
    {
        probe.inflight = NO;
        NSLog(@"Found probe record for ICMP identifier %hu and host %@ (actual host: %s)", probe.icmpIdentifier, probe.hostIdentifier, inet_ntoa(((struct sockaddr_in*)&srcAddr)->sin_addr));
    }
    else
    {
        NSLog(@"Could not find probe record for ICMP identifier %hu", icmpIdentifier);
        return -1;
    }
    
    if (ntohs(icmpRecvHdr->icmp_hun.ih_idseq.icd_seq) != probe.sequenceNumber)
    {
        NSLog(@"Received ICMP packet had incorrect sequence number %u (needed %u)", ntohs(icmpRecvHdr->icmp_hun.ih_idseq.icd_seq), probe.sequenceNumber);
        return -1;
    }
    
    // Calculate the number of ms elapsed between send and receive
    return [self msElapsedBetween:probe.timeSent endTime:timeRecv];
}

@end
