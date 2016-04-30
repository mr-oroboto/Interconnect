//
//  CaptureWorker.m
//  Interconnect
//
//  Created by oroboto on 17/04/2016.
//  Copyright © 2016 oroboto. All rights reserved.
//

#import "CaptureWorker.h"
#import "HostStore.h"
#import "Host.h"
#import "PacketHeaders.h"
#import <pcap/pcap.h>
#import <arpa/inet.h>
#import <net/if.h>
#import <sys/ioctl.h>
#import <netdb.h>
#import "ICMPEchoProbe.h"

#define kLogTraffic NO
#define kMaxConcurrentResolutionTasks   5

@interface CaptureWorker ()

@property (nonatomic) BOOL stopWorker;                      // set from main, read from worker
@property (nonatomic) BOOL workerRunning;                   // set from worker, read from main
@property (nonatomic) dispatch_queue_t captureQueue;
@property (nonatomic) dispatch_queue_t probeQueue;          // serialise probes
@property (nonatomic) NSOperationQueue* resolverQueue;      // allows multiple concurrent resolutions
@property (nonatomic) bpf_u_int32 interfaceAddress;         // IPv4 address of capture interface
@property (nonatomic) bpf_u_int32 interfaceMask;            // IPv4 netmask of capture interface
@property (nonatomic) NSUInteger probeType;

@end

@implementation CaptureWorker

- (instancetype)init
{
    if (self = [super init])
    {
        _workerRunning = NO;
        _stopWorker = NO;
        _probeType = kProbeTypeICMPEcho;
        
        // Create a serial dispatch queue, we'll only ever queue up one task on it.
        _captureQueue = dispatch_queue_create("net.oroboto.Interconnect.CaptureWorker", NULL);
        _probeQueue = dispatch_queue_create("net.oroboto.Interconnect.Probes", NULL);
        _resolverQueue = [[NSOperationQueue alloc] init];
        [_resolverQueue setMaxConcurrentOperationCount:kMaxConcurrentResolutionTasks];

        // Ensure our header definitions will work
        if (sizeof(unsigned short) != 2)
        {
            [NSException raise:@"Expected unsigned short to be 2 bytes" format:@""];
        }

        if (sizeof(unsigned int) != 4)
        {
            [NSException raise:@"Expected unsigned int to be 4 bytes" format:@""];
        }
    }
    
    return self;
}

- (void)dealloc
{
}

- (void)stopCapture
{
    _stopWorker = YES;
}

- (void)startCapture
{
    _stopWorker = NO;
    
    void (^completionBlock)() = ^() {
        NSLog(@"captureBlock finished on thread %@", [NSThread currentThread]);
    };
    
    void (^captureBlock)() = ^() {
        _workerRunning = YES;
        
        NSLog(@"captureBlock started on thread %@", [NSThread currentThread]);

        char errbuf[PCAP_ERRBUF_SIZE];
        char *device;
        pcap_t *capture_handle;
        
        if ( ! (device = pcap_lookupdev(errbuf)))
        {
            NSLog(@"pcap_lookupdev failed: %s", errbuf);
            return;
        }

        // Get network *number* (currently unused) and mask
        if (pcap_lookupnet(device, &_interfaceAddress, &_interfaceMask, errbuf) < 0)
        {
            NSLog(@"pcap_lookupnet failed: %s", errbuf);
            return;
        }
        
        // Get interface address
        int fd = socket(AF_INET, SOCK_DGRAM, 0);
        struct ifreq ifr;
        strncpy(ifr.ifr_name, device, IFNAMSIZ-1);
        ioctl(fd, SIOCGIFADDR, &ifr);
        close(fd);

        _interfaceAddress = ((struct sockaddr_in*)&ifr.ifr_ifru.ifru_addr)->sin_addr.s_addr;
        NSLog(@"Opened [%s (%s)] for live capture", device, inet_ntoa(((struct sockaddr_in*)&ifr.ifr_ifru.ifru_addr)->sin_addr));
        
        if ( ! (capture_handle = pcap_open_live("en0", 4096 /* snaplen: max bytes to capture */, 1 /* promisc */, 0 /* to_ms: infinite */, errbuf)))
        {
            NSLog(@"pcap_open_live failed");
        }
        else
        {
            struct pcap_pkthdr header;
            const unsigned char* packet;
            int linklayer_hdr_type = pcap_datalink(capture_handle);
            
            if ([self logDataLinkHeaderType:linklayer_hdr_type])
            {
                /*
                 pcap_compile()
                 pcap_setfilter()
                 */
                
                while ( ! _stopWorker)
                {
                    packet = pcap_next(capture_handle, &header);
                    [self processEthernetFrame:packet header:&header];
                }
            }
            else
            {
                NSLog(@"Unsupported data-link layer");
            }
            
            pcap_close(capture_handle);
        }
        
        NSLog(@"captureBlock exiting");
        
        _workerRunning = NO;
        
        dispatch_async(dispatch_get_main_queue(), completionBlock);
    };
    
    dispatch_async(_captureQueue, captureBlock);
}

- (void)processEthernetFrame:(const unsigned char*)packet header:(struct pcap_pkthdr*)header
{
//  NSLog(@"Processing %d byte packet", header->len);
    
    struct hdr_ethernet* ether_hdr = (struct hdr_ethernet*)(packet);
    
    if (ntohs(ether_hdr->ether_type) != ETHER_TYPE_IP4)
    {
        NSLog(@"Unsupported Ethertype: %04X", ntohs(ether_hdr->ether_type));
        return;
    }

    struct hdr_ip* ip_hdr = (struct hdr_ip*)(packet + ETHER_HEADER_LEN);
    unsigned int ip_hdr_len = IP_HDR_LEN(ip_hdr);
    if (ip_hdr_len < 20)
    {
        NSLog(@"Invalid IPv4 header length (%d bytes)", ip_hdr_len);
        return;
    }
    
    NSString* srcHost = [NSString stringWithCString:inet_ntoa(ip_hdr->ip_saddr)];
    NSString* dstHost = [NSString stringWithCString:inet_ntoa(ip_hdr->ip_daddr)];
    unsigned int transferBytes = ntohs(ip_hdr->ip_len);     // don't include ethernet frame etc
    
    if (ip_hdr->ip_proto == IPPROTO_TCP)
    {
        // This assumes the IP packet is carrying TCP, could be ICMP etc.
        struct hdr_tcp* tcp_hdr = (struct hdr_tcp*)(packet + ETHER_HEADER_LEN + ip_hdr_len);
        unsigned int tcp_hdr_len = TCP_HDR_LEN(tcp_hdr);
        if (tcp_hdr_len < 20)
        {
            NSLog(@"%@ -> %@: Invalid TCP header length (%d bytes)", srcHost, dstHost, tcp_hdr_len);
            return;
        }
        
        // TCP segment
        unsigned char* payload = (unsigned char*)(packet + ETHER_HEADER_LEN + ip_hdr_len + tcp_hdr_len);
        unsigned int payload_len = ntohs(ip_hdr->ip_len) - ip_hdr_len - tcp_hdr_len;
        
        if (kLogTraffic)
        {
            NSLog(@"%@ -> %@: TCP srcPort[%d] -> dstPort[%d] of %d bytes", srcHost, dstHost, ntohs(tcp_hdr->tcp_sport), ntohs(tcp_hdr->tcp_dport), payload_len);
        }
    }
    else if (ip_hdr->ip_proto == IPPROTO_UDP)
    {
        if (kLogTraffic)
        {
            NSLog(@"%@ -> %@: UDP", srcHost, dstHost);
        }
    }
    else if (ip_hdr->ip_proto == IPPROTO_ICMP)
    {
        NSLog(@"%@ -> %@: ICMP", srcHost, dstHost);
    }
    else
    {
        NSLog(@"%@ -> %@: Unsupported IP protocol [%d]", srcHost, dstHost, ip_hdr->ip_proto);
    }
    
    if (ip_hdr->ip_saddr.s_addr == _interfaceAddress)
    {
        // traffic from us to them
        [self updateHost:dstHost addBytesToUs:0 addBytesFromUs:transferBytes];
    }
    else if (ip_hdr->ip_daddr.s_addr == _interfaceAddress)
    {
        // traffic from them to us
        [self updateHost:srcHost addBytesToUs:transferBytes addBytesFromUs:0];
    }
}

- (BOOL)logDataLinkHeaderType:(int)headerType
{
    switch (headerType)
    {
        case DLT_EN10MB:
            NSLog(@"Data-link: IEEE 802.3 Ethernet");
            return YES;
            
        case DLT_NULL:
            NSLog(@"Data-link: BSD loopback");
            break;
            
        case DLT_RAW:
            NSLog(@"Data-link: Raw IP");
            break;
            
        default:
            NSLog(@"Unsupported data-link layer type [%d]", headerType);
    }
    
    return NO;
}

- (void)updateHost:(NSString*)ipAddress addBytesToUs:(NSUInteger)bytesToUs addBytesFromUs:(NSUInteger)bytesFromUs
{
    if ([[HostStore sharedStore] updateHostBytesTransferred:ipAddress addBytesIn:bytesFromUs addBytesOut:bytesToUs])
    {
        // First time we've seen this host, resolve its name and send off a probe to work out what its orbital should be.
        NSInvocationOperation* resolverOperation = [[NSInvocationOperation alloc] initWithTarget:self selector:@selector(resolveNameForAddress:) object:ipAddress];
        [self.resolverQueue addOperation:resolverOperation];

        if (_probeType == kProbeTypeICMPEcho)
        {
            // Using a "connected" SOCK_DGRAM for ICMP echos does not demultiplex ICMP echo responses from different
            // hosts to the "right" socket. Until the ICMP echo probe is implemented as a single thread that consumes
            // multiple probe requests at once (and resolves them out of order) the ICMP echo task must be serialised.
            dispatch_async(_probeQueue, ^{
                ICMPEchoProbe* probe = [ICMPEchoProbe probeWithIPAddress:ipAddress];
                float rttToHost = [probe measureAverageRTT];
                
                if (rttToHost > 0)
                {
                    NSUInteger hostGroup = (rttToHost / 50.0) + 1;      // 50ms bands
                    
                    if (hostGroup > 12)
                    {
                        hostGroup = 12;
                    }
                    
                    NSLog(@"Updating host %@ group to %lu based on RTT of %.2fms", ipAddress, hostGroup, rttToHost);
                    [[HostStore sharedStore] updateHost:ipAddress withGroup:hostGroup];
                }
                else
                {
                    NSLog(@"Failed to get average RTT to %@", ipAddress);
                }
            });
        }
    }
}

#pragma mark - Name Resolution

- (void)resolveNameForAddress:(NSString*)ipAddress
{
    struct in_addr sin_addr;
    
    if ( ! inet_aton([ipAddress cStringUsingEncoding:NSASCIIStringEncoding], &sin_addr))
    {
        NSLog(@"Could not convert IP address [%@]", ipAddress);
        return;
    }

    char hostname[NI_MAXHOST];
    struct sockaddr_in saddr;
    memset(&saddr, 0, sizeof(saddr));
    saddr.sin_addr = sin_addr;
    saddr.sin_family = AF_INET;
    saddr.sin_len = sizeof(saddr);
    
    if (getnameinfo((const struct sockaddr*)&saddr, saddr.sin_len, hostname, sizeof(hostname), NULL, 0, NI_NOFQDN | NI_NAMEREQD) != 0)
    {
        NSLog(@"Could not resolve IP address [%@]", ipAddress);
        return;
    }

    NSString* resolvedName = [NSString stringWithFormat:@"%s", hostname];
    NSLog(@"Resolved [%@] to [%@]", ipAddress, resolvedName);
    [[HostStore sharedStore] updateHost:ipAddress withName:resolvedName];
}

@end
