//
//  ICMPTimeExceededProbe.m
//  Interconnect
//
//  Created by oroboto on 29/04/2016.
//  Copyright © 2016 oroboto. All rights reserved.
//

#import "ICMPTimeExceededProbe.h"
#import "PacketHeaders.h"
#import <stdio.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <sys/types.h>
#import <netinet/ip.h>
#import <netinet/in_systm.h>
#import <netinet/ip_icmp.h>
#import <sys/select.h>
#import <sys/time.h>

#define kICMPTimeExceededProbeReadTimeout       2
#define kICMPTimeExceededProbeMaxTTL            30

#define kICMPTimeExceededNextHopError           -1
#define kICMPTimeExceededNextHopIsDestination   0
#define kICMPTimeExceededNextHopIsRouter        1

#pragma pack(1)
struct payload
{
    uint16_t        sequence;
    unsigned char   ttl;
    time_t          time_sent;
    unsigned char   pad;
};
#pragma options align=reset

@interface ICMPTimeExceededProbe ()

@property (nonatomic, strong) NSString* ipAddress;
@property (nonatomic) int icmpSocket;
@property (nonatomic) int udpSocket;
@property (nonatomic) uint16_t sequenceNumber;
@property (nonatomic) uint8_t currentTTL;
@property (nonatomic) uint16_t dstPort;

@end

@implementation ICMPTimeExceededProbe

+ (ICMPTimeExceededProbe*)probeWithIPAddress:(NSString*)ipAddress
{
    return [[ICMPTimeExceededProbe alloc] initWithIPAddress:ipAddress];
}

- (instancetype)initWithIPAddress:(NSString*)ipAddress
{
    if (self = [super init])
    {
        self.ipAddress  = ipAddress;
        self.sequenceNumber = 0;
    }
    
    return self;
}

- (NSInteger)measureHopCount
{
    self.icmpSocket = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP);
    if (self.icmpSocket < 0)
    {
        NSLog(@"Could not create ICMP socket");
        return -1;
    }

    self.udpSocket = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (self.udpSocket < 0)
    {
        NSLog(@"Could not create UDP socket");
        return -1;
    }
    
    return [self traceroute];
}

- (NSInteger)traceroute
{
    NSInteger hopCount = 0;
    
    self.sequenceNumber = 0;
    self.currentTTL = 1;
    self.dstPort = 30000;
    
    while (self.currentTTL < kICMPTimeExceededProbeMaxTTL)
    {
        if ([self nextHop] <= 0)
        {
            break;      // we'll return whatever the last hop count we successfully found was rather than an error
        }

        hopCount++;
        self.sequenceNumber++;
        self.currentTTL++;
    }
    
    return hopCount;
}

- (NSInteger)nextHop
{
    NSInteger nextHop = kICMPTimeExceededNextHopError;
    
    struct sockaddr_in dstAddr;
    memset(&dstAddr, 0, sizeof(dstAddr));
    dstAddr.sin_family = AF_INET;
    dstAddr.sin_addr.s_addr = inet_addr([self.ipAddress cStringUsingEncoding:NSASCIIStringEncoding]);
    dstAddr.sin_port = htons(self.dstPort);
    
    // Create UDP packet (IP header + UDP header + payload)
    NSMutableData* payload = [NSMutableData dataWithLength:sizeof(struct payload)];
    struct payload* pPayload = (struct payload*)[payload mutableBytes];
    assert([payload length] == sizeof(struct payload));
    pPayload->sequence = htons(self.sequenceNumber);
    pPayload->ttl = self.currentTTL;
    
    time_t timer = time(NULL);
    pPayload->time_sent = htonl(timer);
    
    NSMutableData* packet = [NSMutableData dataWithLength:[payload length]];
    if ( ! packet)
    {
        NSLog(@"Failed to create UDP request packet");
        return kICMPTimeExceededNextHopError;
    }
    
    // Set the appropriate TTL
    int ttl = self.currentTTL;
    if (setsockopt(self.udpSocket, IPPROTO_IP, IP_TTL, &ttl, sizeof(ttl)) < 0)
    {
        NSLog(@"Could not set IP TTL on UDP socket: %s", strerror(errno));
        return kICMPTimeExceededNextHopError;
    }
    
    ssize_t bytesSent = sendto(self.udpSocket, [packet bytes], [packet length], 0, (struct sockaddr*)&dstAddr, sizeof(dstAddr));
    if (bytesSent < [packet length])
    {
        NSLog(@"Failed while sending UDP echo request (%lu bytes sent): %s", bytesSent, strerror(errno));
        return kICMPTimeExceededNextHopError;
    }
    
    NSLog(@"Sent UDP probe with TTL %u (seq: %u) to %@ (payload length: %lu)", self.currentTTL, self.sequenceNumber, self.ipAddress, (unsigned long)[payload length]);
    
    NSMutableData *packetRecv = [NSMutableData dataWithLength:65535];
    ssize_t totalBytesRead, bytesNeeded;
    struct timeval timeStart, timeEnd;
    float totalMsElapsed;
    struct sockaddr srcAddr;
    
    // Returned ICMP time exceeded or destination unreachable packet should contain IP header, ICMP header, IP header
    // and 8 bytes of UDP datagram. It may also include our payload (12 bytes) but this is highly router dependant
    // and we do not require it.
    bytesNeeded = sizeof(struct hdr_ip) + 8 /* icmp hdr */ + sizeof(struct hdr_ip) + sizeof(struct hdr_udp);

    for (totalMsElapsed = 0, totalBytesRead = 0; totalMsElapsed < (kICMPTimeExceededProbeReadTimeout * 1000) && totalBytesRead < bytesNeeded;)
    {
        if (gettimeofday(&timeStart, NULL))
        {
            NSLog(@"Could not get start time");
            return kICMPTimeExceededNextHopError;
        }

        // Block (up to n seconds) and wait for response
        fd_set readSet;
        memset(&readSet, 0, sizeof(readSet));
        FD_SET(self.icmpSocket, &readSet);
        struct timeval timeout = {kICMPTimeExceededProbeReadTimeout, 0};
        int ret = select(self.icmpSocket + 1, &readSet, NULL, NULL, &timeout);
        if (ret == 0)
        {
            NSLog(@"Timed out while waiting for ICMP time exceeded or port unreachable response (total ms elapsed: %.2f after reading %lu bytes)", totalMsElapsed, totalBytesRead);
            return kICMPTimeExceededNextHopError;
        }
        else if (ret < 0)
        {
            NSLog(@"Failed while waiting for ICMP time exceeded or port unreachable response");
            return kICMPTimeExceededNextHopError;
        }
        
        socklen_t srcAddrLen = sizeof(srcAddr);
        ssize_t bytesRead = recvfrom(self.icmpSocket, ((unsigned char*)[packetRecv mutableBytes])+totalBytesRead, [packetRecv length]-totalBytesRead, 0, &srcAddr, &srcAddrLen);
        if (bytesRead <= 0)
        {
            NSLog(@"Failed to read packet from socket: %s", strerror(errno));
            return kICMPTimeExceededNextHopError;
        }

        if (gettimeofday(&timeEnd, NULL))
        {
            NSLog(@"Could not get end time");
            return kICMPTimeExceededNextHopError;
        }
        
        totalMsElapsed += [self msElapsedBetween:&timeStart endTime:&timeEnd];
        totalBytesRead += bytesRead;
        
        NSLog(@"Read %lu of %lu bytes over %.2fms", totalBytesRead, bytesNeeded, totalMsElapsed);
    }
    
    // Does this look like a valid ICMP error response? The returned packet will include the IP header.
    if (totalBytesRead < bytesNeeded)
    {
        NSLog(@"Received packet was not long enough to be an ICMP error response");
        return kICMPTimeExceededNextHopError;
    }

    struct hdr_ip* ipHdr = (struct hdr_ip*)[packetRecv bytes];
    if (IP_VERSION(ipHdr) != 0x04)
    {
        NSLog(@"Received packet was not IPv4");
        return kICMPTimeExceededNextHopError;
    }
    
    if (ipHdr->ip_proto != IPPROTO_ICMP)
    {
        NSLog(@"Received packet was not ICMP");
        return kICMPTimeExceededNextHopError;
    }
    
    // Validate the checksum
    struct icmp* icmpRecvHdr = (struct icmp*)((unsigned char*)[packetRecv mutableBytes] + IP_HDR_LEN(ipHdr));
    
    // NOTE: Unprivileged ICMP sockets contain two IP header fields that are converted by the kernel to host byte order
    //       on reception (even though they're in NBO on the wire). We must convert them back in order for the checksum
    //       to match (we only need to do this in the reflected IP header contained in the data section of the ICMP packet
    //       itself because we're calculating the ICMP checksum only over the ICMP portion of the packet, not including
    //       the wrapping received IP header).
    struct hdr_ip* ipHdrReflected = (struct hdr_ip*)((unsigned char*)[packetRecv mutableBytes] + IP_HDR_LEN(ipHdr) + 8);
    ipHdrReflected->ip_len = htons(ipHdrReflected->ip_len);
    ipHdrReflected->ip_flags_offset = htons(ipHdrReflected->ip_flags_offset);
    
    uint16_t checksumRecv = icmpRecvHdr->icmp_cksum;
    icmpRecvHdr->icmp_cksum = 0;    // if left at received value the checksum should compute as 0
    unsigned short checksumNeeded = [self icmpChecksum:(unsigned char*)icmpRecvHdr length:(totalBytesRead - IP_HDR_LEN(ipHdr))];
    
    if (checksumRecv != checksumNeeded)
    {
        NSLog(@"Received ICMP packet had incorrect checksum %04X (needed %04X)", checksumRecv, checksumNeeded);
        return kICMPTimeExceededNextHopError;
    }
    
    // Is this a time exceeded or port unreachable?
    if (icmpRecvHdr->icmp_type != ICMP_TIMXCEED && icmpRecvHdr->icmp_type != ICMP_UNREACH_PORT)
    {
        NSLog(@"Received ICMP packet was not time exceeded or port unreachable (type: %X)", icmpRecvHdr->icmp_type);
        return kICMPTimeExceededNextHopError;
    }
    
    // @todo: verification of payload
    NSLog(@"Received ICMP %@ from %s with TTL %d", icmpRecvHdr->icmp_type == ICMP_TIMXCEED ? @"time exceeded" : @"port unreachable", inet_ntoa(((struct sockaddr_in*)&srcAddr)->sin_addr), self.currentTTL);
    
    return icmpRecvHdr->icmp_type == ICMP_TIMXCEED ? kICMPTimeExceededNextHopIsRouter : kICMPTimeExceededNextHopIsDestination;
}

/**
 * From Apple's SimplePing example code
 */
- (unsigned short)icmpChecksum:(unsigned char*)data length:(unsigned short)length
{
    size_t bytesLeft;
    int sum;
    const unsigned short* cursor;
    union
    {
        unsigned short us;
        unsigned char uc[2];
    } last;
    unsigned short answer;
    
    bytesLeft = length;
    sum = 0;
    cursor = (unsigned short*)data;
    
    /*
     * Our algorithm is simple, using a 32 bit accumulator (sum), we add
     * sequential 16 bit words to it, and at the end, fold back all the
     * carry bits from the top 16 bits into the lower 16 bits.
     */
    while (bytesLeft > 1)
    {
        sum += *cursor;
        cursor += 1;
        bytesLeft -= 2;
    }
    
    /* mop up an odd byte, if necessary */
    if (bytesLeft == 1)
    {
        last.uc[0] = * (const unsigned char *) cursor;
        last.uc[1] = 0;
        sum += last.us;
    }
    
    /* add back carry outs from top 16 bits to low 16 bits */
    sum = (sum >> 16) + (sum & 0xffff); /* add hi 16 to low 16 */
    sum += (sum >> 16);         /* add carry */
    answer = (unsigned short) ~sum;   /* truncate to 16 bits */
    
    return answer;
}

- (float)msElapsedBetween:(const struct timeval*)startTime endTime:(const struct timeval*)endTime
{
    float msElapsed = (endTime->tv_usec - startTime->tv_usec) / 1000.0;

    if (endTime->tv_sec - startTime->tv_sec)
    {
        msElapsed = ((((endTime->tv_sec - startTime->tv_sec) - 1) * 1000000) + (1000000 - startTime->tv_usec) + endTime->tv_usec) / 1000.0;
    }

    return msElapsed;
}

@end
