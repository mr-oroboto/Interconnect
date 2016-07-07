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
#import <sys/types.h>
#import <pcap/pcap.h>
#import <arpa/inet.h>
#import <net/if.h>
#import <netinet/ip.h>
#import <netinet/ip_icmp.h>
#import <sys/ioctl.h>
#import "Probe.h"
#import "ICMPEchoProbe.h"
#import "ICMPTimeExceededProbe.h"
#import "ICMPEchoProbeThread.h"
#import "ICMPTimeExceededProbeThread.h"
#import "HostResolver.h"

#define kLogTraffic NO
#define kMaxConcurrentResolutionTasks   5                   // how many name resolution threads can run concurrently?
#define kRecalculateHostSizePeriodMs 10000                  // recalculate how big hosts should be (based on bytes transferred) this often

@interface CaptureWorker ()

@property (nonatomic, copy) void (^stopBlock)(void);        // used to signal capture thread exit
@property (nonatomic, strong) NSLock* startStopLock;

@property (nonatomic) dispatch_queue_t captureQueue;        // libpcap runs here
@property (nonatomic) NSOperationQueue* probeQueue;         // serialise probes that require it (legacy ICMP echo & traceroute)
@property (nonatomic) NSOperationQueue* resolverQueue;      // allows multiple concurrent resolutions

@property (nonatomic) bpf_u_int32 interfaceAddress;         // IPv4 address of capture interface
@property (nonatomic) bpf_u_int32 interfaceMask;            // IPv4 netmask of capture interface

@property (nonatomic, strong) ProbeThread* probeThread;             // for threaded probes

@property (nonatomic) float msSinceLastHostResize;

@end

@implementation CaptureWorker

#pragma mark - Initialisation

- (instancetype)init
{
    if (self = [super init])
    {
        _startStopLock = [[NSLock alloc] init];
        _workerRunning = NO;
        _stopBlock = nil;

        // Ensure our header definitions will work
        if (sizeof(unsigned short) != 2)
        {
            [NSException raise:@"Expected unsigned short to be 2 bytes" format:@""];
        }
        
        if (sizeof(unsigned int) != 4)
        {
            [NSException raise:@"Expected unsigned int to be 4 bytes" format:@""];
        }

        _msSinceLastHostResize = 0;
        _probeQueue = nil;
        _probeThread = nil;

        [self setProbeMethod:kProbeTypeThreadTraceroute completeTimedOutProbes:YES ignoreIntermediateTraffic:YES];
        
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

- (BOOL)setProbeMethod:(ProbeType)probeType completeTimedOutProbes:(BOOL)completeTimedOutProbes ignoreIntermediateTraffic:(BOOL)ignoreIntermediateTraffic
{
    if (self.workerRunning)
    {
        NSLog(@"Probe type cannot be changed while worker is running");
        return NO;
    }

    _probeType = probeType;
    _completeTimedOutProbes = completeTimedOutProbes;
    _ignoreProbeIntermediateTraffic = ignoreIntermediateTraffic;

    return YES;
}

- (void)initialiseProbeMethod
{
    if (self.probeQueue)
    {
        self.probeQueue = nil;
    }
    
    if (self.probeThread)
    {
        // If previously started it should have been stopped and we get to recreate it
        assert( ! self.probeThread.threadRunning);
        self.probeThread = nil;
    }
    
    switch (self.probeType)
    {
        case kProbeTypeICMPEcho:
        case kProbeTypeTraceroute:
            self.probeQueue = [[NSOperationQueue alloc] init];
            [self.probeQueue setMaxConcurrentOperationCount:1]; // ICMP DGRAM socket requires serialised access or per probe identification
            break;
            
        case kProbeTypeThreadICMPEcho:
            self.probeThread = [[ICMPEchoProbeThread alloc] init];
            [self.probeThread start];
            break;
            
        case kProbeTypeThreadTraceroute:
            self.probeThread = [[ICMPTimeExceededProbeThread alloc] init];
            self.probeThread.completeTimedOutProbes = self.completeTimedOutProbes;
            [self.probeThread start];
            break;
            
        default:
            [NSException raise:@"CaptureWorker" format:@"Unknown probe type"];
    }
}

#pragma mark - Worker Control

- (BOOL)stopCapture:(void (^)(void))threadStoppedBlock
{
    BOOL stopRequested = YES;
    
    [self.startStopLock lock];
    
    if ( ! self.workerRunning)
    {
        NSLog(@"Could not stop capture thread, it's not running");
        stopRequested = NO;
    }
    
    /**
     * If we didn't test for this there is a race condition when stopCapture is called when the worker thread is stopping
     * but hasn't yet exited. We'd be allowed to request a stop but our block would never be called.
     */
    if (self.stopBlock)
    {
        NSLog(@"Could not stop capture thread, a stop is already requested");
        stopRequested = NO;
    }

    if (stopRequested)
    {
        // Signal the stop
        self.stopBlock = threadStoppedBlock;
    }
    
    [self.startStopLock unlock];
    
    return stopRequested;
}

- (void)startCapture:(NSString*)captureInterface withFilter:(NSString*)filter
{
    void (^captureBlock)() = ^() {
        [self.startStopLock lock];
        _workerRunning = YES;           // self.stopBlock could already have been set by now (race condition, if so we'll exit immediately below)
        [self.startStopLock unlock];

        void (^stopBlock)(void) = nil;

        NSLog(@"CaptureWorker started on thread %@", [NSThread currentThread]);
        
        @try
        {
            char errbuf[PCAP_ERRBUF_SIZE];
            const char *device;
            pcap_t *capture_handle;

            if (captureInterface.length == 0)
            {
                if ( ! (device = pcap_lookupdev(errbuf)))
                {
                    [NSException raise:@"pcap_lookupdev" format:@"pcap_lookupdev failed: %s", errbuf];
                }
            }
            else
            {
                device = [captureInterface cStringUsingEncoding:NSASCIIStringEncoding];
            }
            
            _captureInterface = [NSString stringWithFormat:@"%s", device];
            _captureFilter = [filter copy];

            // Get network *number* (currently unused) and mask (required for filter)
            if (pcap_lookupnet(device, &_interfaceAddress, &_interfaceMask, errbuf) < 0)
            {
                [NSException raise:@"pcap_lookupnet" format:@"pcap_lookupnet failed: %s", errbuf];
            }
            
            // Get interface address (if defined)
            int fd = socket(AF_INET, SOCK_DGRAM, 0);
            struct ifreq ifr;
            strncpy(ifr.ifr_name, device, IFNAMSIZ-1);
            ioctl(fd, SIOCGIFADDR, &ifr);
            close(fd);

            self.interfaceAddress = ((struct sockaddr_in*)&ifr.ifr_ifru.ifru_addr)->sin_addr.s_addr;
            NSLog(@"Opened [%s (%s)] for live capture", device, inet_ntoa(((struct sockaddr_in*)&ifr.ifr_ifru.ifru_addr)->sin_addr));
            
            if ( ! (capture_handle = pcap_open_live(device, 4096 /* snaplen: max bytes to capture */, 1 /* promisc */, 1000 /* to_ms: 1 second */, errbuf)))
            {
                [NSException raise:@"pcap_open_live" format:@"pcap_open_live failed"];
            }
            else
            {
                if (filter.length)
                {
                    struct bpf_program filter;
                    
                    if (pcap_compile(capture_handle, &filter, [self.captureFilter cStringUsingEncoding:NSASCIIStringEncoding], 0, _interfaceMask) < 0)
                    {
                        [NSException raise:@"pcap_compile" format:@"pcap_compile failed: %s", pcap_geterr(capture_handle)];
                    }
                    
                    if (pcap_setfilter(capture_handle, &filter) < 0)
                    {
                        [NSException raise:@"pcap_setfilter" format:@"pcap_setfilter failed: %s", pcap_geterr(capture_handle)];
                    }
                }
                
                [self initialiseProbeMethod];
                
                struct pcap_pkthdr header;
                const unsigned char* packet;
                int linklayer_hdr_type = pcap_datalink(capture_handle);
                
                if ([self logDataLinkHeaderType:linklayer_hdr_type])
                {
                    struct timeval timeStart, timeEnd;
                    
                    while ( ! stopBlock)
                    {
                        gettimeofday(&timeStart, NULL);

                        if ((packet = pcap_next(capture_handle, &header)) != NULL)
                        {
                            [self processEthernetFrame:packet header:&header];
                        }

                        gettimeofday(&timeEnd, NULL);

                        self.msSinceLastHostResize += [self msElapsedBetween:&timeStart endTime:&timeEnd];
                        if (self.msSinceLastHostResize >= kRecalculateHostSizePeriodMs)
                        {
                            [self recalculateHostSizes];
                        }
                        
                        [self.startStopLock lock];
                        if (self.stopBlock)
                        {
                            stopBlock = self.stopBlock;     // remember we were signaled to stop
                        }
                        [self.startStopLock unlock];
                    }
                }
                else
                {
                    [NSException raise:@"Unsupported data-link layer" format:@"Unsupported data-link layer"];
                }
                
                pcap_close(capture_handle);
            }
        }
        @catch (NSException* e)
        {
            NSLog(@"CaptureWorker caught exception %@", e);
        }

        NSLog(@"CaptureWorker exiting, waiting for probe and resolve threads to clear");
        
        /**
         * Wait for all existing probes and host resolutions to finish so that when the capture thread stops all 
         * related concurrent operations are also finished.
         *
         * The NSOperationQueues will simply not run any queued NSInvocationOperations that have not yet started and
         * those that have started should return quite quickly anyway.
         *
         * For our probes, we ask them to drain their probe queues before we allow ourselves to finish. That way any
         * in flight probe that is received after clearing will be ignored (the threads themselves are not stopped).
         */
        [self.resolverQueue cancelAllOperations];
        while (self.resolverQueue.operationCount)
        {
            NSLog(@"Waiting for %lu outstanding host resolutions", (unsigned long)self.resolverQueue.operationCount);
            usleep(100000);
        }

        NSLog(@"All outstanding resolution operations have been cancelled");
        
        if (self.probeQueue)
        {
            [self.probeQueue cancelAllOperations];
            while (self.probeQueue.operationCount)
            {
                NSLog(@"Waiting for %lu outstanding probe operations to be cancelled", self.probeQueue.operationCount);
                usleep(100000);
            }
            
            NSLog(@"All outstanding probe operations have been cancelled");
        }
        
        if (self.probeThread)
        {
            NSLog(@"Signalling probe thread to exit");
            
            void (^probeThreadStopBlock)() = ^() {
                NSLog(@"Probe thread was stopped");
                self.probeThread = nil;
                [self signalCaptureThreadIsStopped:stopBlock];
            };

            [self.probeThread stop:probeThreadStopBlock];
        }
        else
        {
            [self signalCaptureThreadIsStopped:stopBlock];
        }
    };
    
    dispatch_async(_captureQueue, captureBlock);
}

- (void)signalCaptureThreadIsStopped:(void (^)(void))stopBlock
{
    [self.startStopLock lock];
    _workerRunning = NO;
    self.stopBlock = nil;               // subsequent starts should not immediately stop unless stopCapture was called
    [self.startStopLock unlock];
    
    if (stopBlock)
    {
        // This is not called with the lock held or it could never be used to restart the thread
        dispatch_async(dispatch_get_main_queue(), stopBlock);
    }
    
    NSLog(@"CaptureWorker exited");
}

- (NSArray*)captureDevices
{
    NSMutableArray* captureDevices = [[NSMutableArray alloc] init];
    
    char errbuf[PCAP_ERRBUF_SIZE];
    pcap_if_t* deviceList;
    
    if (pcap_findalldevs(&deviceList, errbuf) == 0)
    {
        pcap_if_t *device = deviceList;
        
        do
        {
            NSMutableDictionary* deviceEntry = [NSMutableDictionary dictionaryWithCapacity:2];
            
            deviceEntry[@"name"] = [NSString stringWithFormat:@"%s", device->name];
            if (device->description)
            {
                deviceEntry[@"description"] = [NSString stringWithFormat:@"%s", device->description];
            }
            
            [captureDevices addObject:deviceEntry];
        } while((device = device->next));
        
        pcap_freealldevs(deviceList);
    }

    return captureDevices;
}

#pragma mark - Packet Processing

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

    BOOL trafficIsGeneratedByProbe = NO;
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
        struct hdr_udp* udp_hdr = (struct hdr_udp*)(packet + ETHER_HEADER_LEN + ip_hdr_len);
        if (ntohs(udp_hdr->udp_len) < 4)
        {
            NSLog(@"%@ -> %@: Invalid UDP header length (%d bytes)", srcHost, dstHost, ntohs(udp_hdr->udp_len));
            return;
        }
        
        srcPort = ntohs(udp_hdr->udp_sport);
        dstPort = ntohs(udp_hdr->udp_dport);

        if (kLogTraffic)
        {
            NSLog(@"UDP  %@:%lu -> %@:%lu", srcHost, srcPort, dstHost, dstPort);
        }
        
        /**
         * If the source port is a high port and we are the source and running a traceroute probe then this 
         * traffic is most likely probe related.
         */
        if ((self.probeType == kProbeTypeTraceroute || self.probeType == kProbeTypeThreadTraceroute) &&
            ip_hdr->ip_saddr.s_addr == _interfaceAddress &&
            dstPort >= kBaseTracerouteUDPPort)
        {
            trafficIsGeneratedByProbe = YES;
        }
    }
    else if (ip_hdr->ip_proto == IPPROTO_ICMP)
    {
        struct icmp* icmp_hdr = (struct icmp*)(packet + ETHER_HEADER_LEN + ip_hdr_len);
        
        if (kLogTraffic)
        {
            NSLog(@"ICMP %@ -> %@ (type: %d)", srcHost, dstHost, icmp_hdr->icmp_type);
        }
        
        /**
         * @todo: better check for ICMP type, if time exceeded or port unreachable with us as destination
         * and we are running a traceroute probe then this traffic is probe related.
         */
        if ((self.probeType == kProbeTypeTraceroute || self.probeType == kProbeTypeThreadTraceroute)
            && ip_hdr->ip_daddr.s_addr == _interfaceAddress
            && (icmp_hdr->icmp_type == ICMP_TIMXCEED || icmp_hdr->icmp_type == ICMP_UNREACH_PORT))
        {
            trafficIsGeneratedByProbe = YES;
        }
    }
    else
    {
        NSLog(@"**** %@ -> %@: Unsupported IP protocol [%d]", srcHost, dstHost, ip_hdr->ip_proto);
    }

    if ( ! self.ignoreProbeIntermediateTraffic || ! trafficIsGeneratedByProbe)
    {
        if (ip_hdr->ip_saddr.s_addr == _interfaceAddress)
        {
            // traffic from us
            [self updateHost:dstHost addBytesToUs:0 addBytesFromUs:transferBytes port:dstPort];
        }
        else if (ip_hdr->ip_daddr.s_addr == _interfaceAddress)
        {
            // traffic to us
            [self updateHost:srcHost addBytesToUs:transferBytes addBytesFromUs:0 port:srcPort];
        }
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
    BOOL hostIsNew = [[HostStore sharedStore] updateHostBytesTransferred:ipAddress addBytesIn:bytesFromUs addBytesOut:bytesToUs port:port];
    
    if ( ! hostIsNew)
    {
        return;
    }
    
    // First time we've seen this host, resolve its name and send off a probe to work out what its orbital should be.
    NSInvocationOperation* resolverOperation = [[NSInvocationOperation alloc] initWithTarget:self selector:@selector(resolveHostDetailsForAddress:) object:ipAddress];
    [self.resolverQueue addOperation:resolverOperation];

    if (self.probeType == kProbeTypeICMPEcho)
    {
        /**
         * Using a "connected" SOCK_DGRAM for ICMP echos does not demultiplex ICMP echo responses from different
         * hosts to the "right" socket. Until the ICMP echo probe is implemented as a single thread that consumes
         * multiple probe requests at once (and resolves them out of order) the ICMP echo task must be serialised.
         */
        NSBlockOperation* probeOperation = [NSBlockOperation blockOperationWithBlock: ^{
            ICMPEchoProbe* probe = [ICMPEchoProbe probeWithIPAddress:ipAddress];
            float rttToHost = [probe measureAverageRTT];
            
            if (rttToHost > 0)
            {
                [[HostStore sharedStore] updateHost:ipAddress withRTT:rttToHost andHopCount:-1];
            }
            else
            {
                NSLog(@"Failed to get average RTT to %@", ipAddress);
            }
        }];
        
        [self.probeQueue addOperation:probeOperation];
    }
    else if (self.probeType == kProbeTypeTraceroute)
    {
        NSBlockOperation* probeOperation = [NSBlockOperation blockOperationWithBlock: ^{
            ICMPTimeExceededProbe* probe = [ICMPTimeExceededProbe probeWithIPAddress:ipAddress];
            NSInteger hopCount = [probe measureHopCount];
            
            if (hopCount > 0)
            {
                [[HostStore sharedStore] updateHost:ipAddress withRTT:0 andHopCount:hopCount];
            }
            else
            {
                NSLog(@"Failed to get hop count to %@", ipAddress);
            }
        }];
        
        [self.probeQueue addOperation:probeOperation];
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
                [[HostStore sharedStore] updateHost:probe.hostIdentifier withRTT:probe.rttToHost andHopCount:probe.currentTTL];
            }
            else if (self.probeType == kProbeTypeThreadICMPEcho && probe.rttToHost > 0)
            {
                NSLog(@"Updating %@ with RTT %.2fms from probe", probe.hostIdentifier, probe.rttToHost);
                [[HostStore sharedStore] updateHost:probe.hostIdentifier withRTT:probe.rttToHost andHopCount:-1];
            }
        };
        
        [self.probeThread queueProbeForHost:ipAddress withPriority:YES onCompletion:probeFinishedBlock];
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
