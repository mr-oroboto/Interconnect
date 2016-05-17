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
#import "Probe.h"
#import "ICMPEchoProbe.h"
#import "ICMPTimeExceededProbe.h"
#import "ICMPEchoProbeThread.h"
#import "ICMPTimeExceededProbeThread.h"
#import "HostResolver.h"

#define kLogTraffic NO
#define kMaxConcurrentResolutionTasks   5
#define kRecalculateHostSizeEachSecs 10000

@interface CaptureWorker ()

@property (nonatomic) BOOL stopWorker;                      // set from main, read from worker
@property (nonatomic) BOOL workerRunning;                   // set from worker, read from main
@property (nonatomic) dispatch_queue_t captureQueue;
@property (nonatomic) dispatch_queue_t probeQueue;          // serialise probes
@property (nonatomic) NSOperationQueue* resolverQueue;      // allows multiple concurrent resolutions
@property (nonatomic) bpf_u_int32 interfaceAddress;         // IPv4 address of capture interface
@property (nonatomic) bpf_u_int32 interfaceMask;            // IPv4 netmask of capture interface
@property (nonatomic) NSUInteger probeType;
@property (nonatomic) float msSinceLastHostResize;
@property (nonatomic) ProbeThread* probeThread;

@end

@implementation CaptureWorker

- (instancetype)init
{
    if (self = [super init])
    {
        _workerRunning = NO;
        _stopWorker = NO;
        _msSinceLastHostResize = 0;
        _probeType = kProbeTypeTraceroute;
//      _probeType = kProbeTypeICMPEcho;
        _probeType = kProbeTypeThreadICMPEcho;

        // Ensure our header definitions will work
        if (sizeof(unsigned short) != 2)
        {
            [NSException raise:@"Expected unsigned short to be 2 bytes" format:@""];
        }

        if (sizeof(unsigned int) != 4)
        {
            [NSException raise:@"Expected unsigned int to be 4 bytes" format:@""];
        }
        
        _probeQueue = nil;
        _probeThread = nil;
        
        switch (_probeType)
        {
            case kProbeTypeICMPEcho:
            case kProbeTypeTraceroute:
                _probeQueue = dispatch_queue_create("net.oroboto.Interconnect.Probes", NULL);
                break;
                
            case kProbeTypeThreadICMPEcho:
                _probeThread = [[ICMPEchoProbeThread alloc] init];
                [_probeThread start];
                break;
                
            case kProbeTypeThreadTraceroute:
                _probeThread = [[ICMPTimeExceededProbeThread alloc] init];
                [_probeThread start];
                break;
                
            default:
                [NSException raise:@"CaptureWorker" format:@"Unknown probe type"];
        }
        
        // Create a serial dispatch queue, we'll only ever queue up one task on it.
        _captureQueue = dispatch_queue_create("net.oroboto.Interconnect.CaptureWorker", NULL);
        
        // Whereas we can run multiple resolver tasks concurrently
        _resolverQueue = [[NSOperationQueue alloc] init];
        [_resolverQueue setMaxConcurrentOperationCount:kMaxConcurrentResolutionTasks];
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
                
                struct timeval timeStart, timeEnd;
                
                while ( ! _stopWorker)
                {
                    gettimeofday(&timeStart, NULL);

                    packet = pcap_next(capture_handle, &header);
                    [self processEthernetFrame:packet header:&header];

                    gettimeofday(&timeEnd, NULL);

                    self.msSinceLastHostResize += [self msElapsedBetween:&timeStart endTime:&timeEnd];
                    if (self.msSinceLastHostResize >= kRecalculateHostSizeEachSecs)
                    {
                        [self recalculateHostSizes];
                    }
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
    
    NSString* srcHost = [NSString stringWithCString:inet_ntoa(ip_hdr->ip_saddr) encoding:NSASCIIStringEncoding];
    NSString* dstHost = [NSString stringWithCString:inet_ntoa(ip_hdr->ip_daddr) encoding:NSASCIIStringEncoding];
    NSUInteger srcPort = 0, dstPort = 0;
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

        srcPort = ntohs(tcp_hdr->tcp_sport);
        dstPort = ntohs(tcp_hdr->tcp_dport);

        if (kLogTraffic)
        {
            NSLog(@"TCP  %@:%lu -> %@:%lu  %d bytes", srcHost, srcPort, dstHost, dstPort, payload_len);
        }
    }
    else if (ip_hdr->ip_proto == IPPROTO_UDP)
    {
        if (kLogTraffic)
        {
          NSLog(@"UDP  %@ -> %@", srcHost, dstHost);
        }
    }
    else if (ip_hdr->ip_proto == IPPROTO_ICMP)
    {
        if (kLogTraffic)
        {
            NSLog(@"ICMP %@ -> %@", srcHost, dstHost);            
        }
    }
    else
    {
        NSLog(@"**** %@ -> %@: Unsupported IP protocol [%d]", srcHost, dstHost, ip_hdr->ip_proto);
    }
    
    if (ip_hdr->ip_saddr.s_addr == _interfaceAddress)
    {
        // traffic from us to them
        [self updateHost:dstHost addBytesToUs:0 addBytesFromUs:transferBytes port:dstPort];
    }
    else if (ip_hdr->ip_daddr.s_addr == _interfaceAddress)
    {
        // traffic from them to us
        [self updateHost:srcHost addBytesToUs:transferBytes addBytesFromUs:0 port:srcPort];
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

- (void)updateHost:(NSString*)ipAddress addBytesToUs:(NSUInteger)bytesToUs addBytesFromUs:(NSUInteger)bytesFromUs port:(NSUInteger)port
{
    if ([[HostStore sharedStore] updateHostBytesTransferred:ipAddress addBytesIn:bytesFromUs addBytesOut:bytesToUs port:port])
    {
        // First time we've seen this host, resolve its name and send off a probe to work out what its orbital should be.
        NSInvocationOperation* resolverOperation = [[NSInvocationOperation alloc] initWithTarget:self selector:@selector(resolveHostDetailsForAddress:) object:ipAddress];
        [self.resolverQueue addOperation:resolverOperation];

        if (self.probeType == kProbeTypeICMPEcho)
        {
            // Using a "connected" SOCK_DGRAM for ICMP echos does not demultiplex ICMP echo responses from different
            // hosts to the "right" socket. Until the ICMP echo probe is implemented as a single thread that consumes
            // multiple probe requests at once (and resolves them out of order) the ICMP echo task must be serialised.
            dispatch_async(_probeQueue, ^{
                ICMPEchoProbe* probe = [ICMPEchoProbe probeWithIPAddress:ipAddress];
                float rttToHost = [probe measureAverageRTT];
                
                if (rttToHost > 0)
                {
                    [[HostStore sharedStore] updateHost:ipAddress withRTT:rttToHost];
                }
                else
                {
                    NSLog(@"Failed to get average RTT to %@", ipAddress);
                }
            });
        }
        else if (self.probeType == kProbeTypeTraceroute)
        {
            dispatch_async(_probeQueue, ^{
                ICMPTimeExceededProbe* probe = [ICMPTimeExceededProbe probeWithIPAddress:ipAddress];
                NSInteger hopCount = [probe measureHopCount];
                
                if (hopCount >= 0)
                {
                    [[HostStore sharedStore] updateHost:ipAddress withHopCount:hopCount];
                }
                else
                {
                    NSLog(@"Failed to get hop count to %@", ipAddress);
                }
            });
        }
        else if (self.probeType == kProbeTypeThreadICMPEcho || self.probeType == kProbeTypeThreadTraceroute)
        {
            /**
             * This block will be called on the probe thread itself, which is important because only that thread
             * can clean up (and invalidate) probe objects.
             */
            void (^probeFinishedBlock)(Probe*) = ^void(Probe* probe) {
                if (self.probeType == kProbeTypeThreadTraceroute && probe.currentTTL > 0)
                {
                    NSLog(@"Updating %@ with hop count %u from probe", probe.hostIdentifier, probe.currentTTL);
                    [[HostStore sharedStore] updateHost:probe.hostIdentifier withHopCount:probe.currentTTL];
                }
                else if (self.probeType == kProbeTypeThreadICMPEcho && probe.rttToHost > 0)
                {
                    NSLog(@"Updating %@ with RTT %.2fms from probe", probe.hostIdentifier, probe.rttToHost);
                    [[HostStore sharedStore] updateHost:probe.hostIdentifier withRTT:probe.rttToHost];
                }
            };
            
            [self.probeThread queueProbeForHost:ipAddress withPriority:YES onCompletion:probeFinishedBlock];
        }
    }
}

- (void)recalculateHostSizes
{
    NSLog(@"%.2f ms have elapsed since last host resizing, resizing hosts", self.msSinceLastHostResize);
    
    [[HostStore sharedStore] recalculateHostSizesBasedOnBytesTransferred];
    
    self.msSinceLastHostResize = 0;
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

#pragma mark - Host Detail Resolution

- (void)resolveHostDetailsForAddress:(NSString*)ipAddress
{
    HostResolver* resolver = [[HostResolver alloc] initWithIPAddress:ipAddress];
    
    NSString *resolvedName = [resolver resolveHostName];
    if (resolvedName.length)
    {
//      NSLog(@"Resolved [%@] to [%@]", ipAddress, resolvedName);
        [[HostStore sharedStore] updateHost:ipAddress withName:resolvedName];        
    }
    
    NSDictionary *asDetails = [resolver resolveASDetails];
    if (asDetails[@"as"] && asDetails[@"asDesc"])
    {
        [[HostStore sharedStore] updateHost:ipAddress withAS:asDetails[@"as"] andASDescription:asDetails[@"asDesc"]];
    }
}

@end
