//
//  ICMPEchoProbe.m
//  Interconnect
//
//  NOTE: Using a "connected" SOCK_DGRAM for ICMP echos does not demultiplex ICMP echo responses from different
//        hosts to the "right" socket. Until the ICMP echo probe is implemented as a single thread that consumes
//        multiple probe requests at once (and resolves them out of order) the ICMP echo task must be serialised.
//
//  Created by oroboto on 29/04/2016.
//  Copyright © 2016 oroboto. All rights reserved.
//

#import "ICMPEchoProbe.h"
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
#define kICMPEchoProbeTimeoutSecs  1
#define kICMPEchoProbeNumberEchos  1

@interface ICMPEchoProbe ()

@property (nonatomic, strong) NSString* ipAddress;
@property (nonatomic) int socket;
@property (nonatomic) uint16_t identifier;
@property (nonatomic) uint16_t sequenceNumber;

@end

@implementation ICMPEchoProbe

+ (ICMPEchoProbe*)probeWithIPAddress:(NSString*)ipAddress
{
    return [[ICMPEchoProbe alloc] initWithIPAddress:ipAddress];
}

- (instancetype)initWithIPAddress:(NSString*)ipAddress
{
    if (self = [super init])
    {
        self.ipAddress  = ipAddress;
        self.lastError  = kICMPEchoProbeErrorNone;
        self.identifier = arc4random();  // identifies this ICMP echo request amongst others to the destination
        self.sequenceNumber = 0;
    }
    
    return self;
}

- (float)measureAverageRTT
{
    self.socket = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP);
    if (self.socket < 0)
    {
        self.lastError = kICMPEchoProbeErrorNoSocket;
        return -1;
    }

    struct sockaddr_in dstAddr;
    memset(&dstAddr, 0, sizeof(dstAddr));
    dstAddr.sin_family = AF_INET;
    dstAddr.sin_addr.s_addr = inet_addr([self.ipAddress cStringUsingEncoding:NSASCIIStringEncoding]);

    if (connect(self.socket, (const struct sockaddr*)&dstAddr, sizeof(dstAddr)) < 0)
    {
        NSLog(@"Could not set destination address to limit received packets");
        self.lastError = kICMPEchoProbeErrorNoSocket;
        return -1;
    }
    
    float msElapsedTotal = 0;
    for (int i = 0; i < kICMPEchoProbeNumberEchos; i++)
    {
        float msElapsed = [self ping];
        if (msElapsed < 0)
        {
            msElapsedTotal = -1;
            break;
        }
        
        msElapsedTotal += msElapsed;
    }
    
    close(self.socket);
    
    if (msElapsedTotal >= 0)
    {
        return msElapsedTotal / kICMPEchoProbeNumberEchos;
    }
    
    return msElapsedTotal;
}

- (float)ping
{
    struct icmp* icmpSendHdr;
    uint16_t sentSequenceNumber = self.sequenceNumber;
    uint16_t identifier = self.identifier;
    
    // Create ICMP packet (header + payload, 56 byte payload is standard)
    NSData* payload = [[NSString stringWithFormat:@"%32zd echoes in an empty room", sentSequenceNumber] dataUsingEncoding:NSASCIIStringEncoding];
    assert([payload length] == 56);
    
    NSMutableData* packet = [NSMutableData dataWithLength:sizeof(struct icmp) + [payload length]];
    if ( ! packet)
    {
        NSLog(@"Failed to create ICMP echo request packet");
        self.lastError = kICMPEchoProbeErrorPacket;
        return -1;
    }
    
    icmpSendHdr = [packet mutableBytes];
    icmpSendHdr->icmp_type = ICMP_ECHO;
    icmpSendHdr->icmp_code = 0;
    icmpSendHdr->icmp_cksum = 0;      // must be 0 for checksum calculation to work correctly
    icmpSendHdr->icmp_hun.ih_idseq.icd_id = htons(identifier);
    icmpSendHdr->icmp_hun.ih_idseq.icd_seq = htons(sentSequenceNumber);
    memcpy(&icmpSendHdr[1], [payload bytes], [payload length]);
    
    // Ensure we never send anything else with this sequence number and ID combination
    self.sequenceNumber++;
    
    // Calculate the ICMP checksum (no need for endian swap, checksum calculated appropriately)
    icmpSendHdr->icmp_cksum = [self icmpChecksum:(unsigned char*)[packet bytes] length:[packet length]];

    // Send it
    struct timeval timeSent, timeRecv;
    
    if (gettimeofday(&timeSent, NULL))
    {
        NSLog(@"Could not get send time");
        self.lastError = kICMPEchoProbeErrorSend;
        return -1;
    }

    ssize_t bytesSent = send(self.socket, [packet bytes], [packet length], 0);
    if (bytesSent < [packet length])
    {
        NSLog(@"Failed while sending ICMP echo request (%lu bytes sent)", bytesSent);
        self.lastError = kICMPEchoProbeErrorSend;
        return -1;
    }
    
    NSLog(@"Sent ICMP echo request with ID %u (seq: %u) to %@", identifier, sentSequenceNumber, self.ipAddress);
    
    // Block (up to n seconds) and wait for response
    fd_set readSet;
    memset(&readSet, 0, sizeof(readSet));
    FD_SET(self.socket, &readSet);
    struct timeval timeout = {kICMPEchoProbeTimeoutSecs, 0};
    int ret = select(self.socket + 1, &readSet, NULL, NULL, &timeout);
    if (ret == 0)
    {
        NSLog(@"Timed out while waiting for ICMP echo response");
        self.lastError = kICMPEchoProbeErrorRecvTimeout;
        return -1;
    }
    else if (ret < 0)
    {
        NSLog(@"Failed while waiting for ICMP echo response");
        self.lastError = kICMPEchoProbeErrorRecvWait;
        return -1;
    }
    
    NSMutableData *packetRecv = [NSMutableData dataWithLength:65535];
    struct sockaddr srcAddr;
    socklen_t srcAddrLen = sizeof(srcAddr);
    ssize_t bytesRead = recvfrom(self.socket, [packetRecv mutableBytes], [packetRecv length], 0, &srcAddr, &srcAddrLen);
    if (bytesRead <= 0)
    {
        NSLog(@"Failed to read packet from socket");
        self.lastError = kICMPEchoProbeErrorRecv;
        return -1;
    }

    if (gettimeofday(&timeRecv, NULL))
    {
        NSLog(@"Could not get receive time");
        self.lastError = kICMPEchoProbeErrorRecv;
        return -1;
    }

    // Does this look like a valid ICMP echo response? The returned packet will include the IP header.
    if (bytesRead < (sizeof(struct hdr_ip) + sizeof(struct icmp)))
    {
        NSLog(@"Received packet was not long enough to be an ICMP echo response");
        self.lastError = kICMPEchoProbeErrorPacket;
        return -1;
    }
    
    struct hdr_ip* ipHdr = (struct hdr_ip*)[packetRecv bytes];
    if (IP_VERSION(ipHdr) != 0x04)
    {
        NSLog(@"Received packet was not IPv4");
        self.lastError = kICMPEchoProbeErrorPacket;
        return -1;
    }
    
    if (ipHdr->ip_proto != IPPROTO_ICMP)
    {
        NSLog(@"Received packet was not ICMP");
        self.lastError = kICMPEchoProbeErrorPacket;
        return -1;
    }
    
    if (bytesRead < IP_HDR_LEN(ipHdr) + sizeof(struct icmp))
    {
        NSLog(@"Received packet was not long enough to contain full ICMP header");
        self.lastError = kICMPEchoProbeErrorPacket;
        return -1;
    }
    
    // Validate the checksum
    struct icmp* icmpRecvHdr = (struct icmp*)((unsigned char*)[packetRecv bytes] + IP_HDR_LEN(ipHdr));
    uint16_t checksumRecv = icmpRecvHdr->icmp_cksum;
    icmpRecvHdr->icmp_cksum = 0;
    uint16_t checksumNeeded = [self icmpChecksum:(unsigned char*)icmpRecvHdr length:(bytesRead - IP_HDR_LEN(ipHdr))];
    
    if (checksumRecv != checksumNeeded)
    {
        NSLog(@"Received ICMP packet had incorrect checksum %X (needed %X)", checksumRecv, checksumNeeded);
        self.lastError = kICMPEchoProbeErrorPacket;
        return -1;
    }
    
    // Is this an echo response?
    if (icmpRecvHdr->icmp_type != ICMP_ECHOREPLY || icmpRecvHdr->icmp_code != 0)
    {
        NSLog(@"Received ICMP packet was not an ECHO reply");
        self.lastError = kICMPEchoProbeErrorPacket;
        return -1;
    }
    
    if (ntohs(icmpRecvHdr->icmp_hun.ih_idseq.icd_id) != identifier)
    {
        NSLog(@"Received ICMP packet from %s had incorrect identifier %u (needed %u)", inet_ntoa(((struct sockaddr_in*)&srcAddr)->sin_addr), ntohs(icmpRecvHdr->icmp_hun.ih_idseq.icd_id), identifier);
        self.lastError = kICMPEchoProbeErrorPacket;
        return -1;
    }

    if (ntohs(icmpRecvHdr->icmp_hun.ih_idseq.icd_seq) != sentSequenceNumber)
    {
        NSLog(@"Received ICMP packet had incorrect sequence number %u (needed %u)", ntohs(icmpRecvHdr->icmp_hun.ih_idseq.icd_seq), sentSequenceNumber);
        self.lastError = kICMPEchoProbeErrorPacket;
        return -1;
    }

    // Calculate the number of ms elapsed between send and receive
    float returnTripMs = (timeRecv.tv_usec - timeSent.tv_usec) / 1000.0;
    if (timeRecv.tv_sec - timeSent.tv_sec)
    {
        returnTripMs = ((((timeRecv.tv_sec - timeSent.tv_sec) - 1) * 1000000) + (1000000 - timeSent.tv_usec) + timeRecv.tv_usec) / 1000.0;
    }
    
    return returnTripMs;
}

/**
 * From Apple's SimplePing example code
 */
- (uint16_t)icmpChecksum:(unsigned char*)data length:(uint16_t)length
{
    size_t bytesLeft;
    int32_t sum;
    const uint16_t* cursor;
    union
    {
        uint16_t us;
        uint8_t uc[2];
    } last;
    uint16_t answer;
    
    bytesLeft = length;
    sum = 0;
    cursor = (uint16_t*)data;
    
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
        last.uc[0] = * (const uint8_t *) cursor;
        last.uc[1] = 0;
        sum += last.us;
    }
    
    /* add back carry outs from top 16 bits to low 16 bits */
    sum = (sum >> 16) + (sum & 0xffff); /* add hi 16 to low 16 */
    sum += (sum >> 16);         /* add carry */
    answer = (uint16_t) ~sum;   /* truncate to 16 bits */
    
    return answer;
}

@end
