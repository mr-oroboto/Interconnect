//
//  ProbeThread.m
//  Interconnect
//
//  Created by oroboto on 15/05/2016.
//  Copyright © 2016 oroboto. All rights reserved.
//

#import "ProbeThread.h"

@interface ProbeThread ()

@property (nonatomic, strong) NSThread* probeThread;
@property (nonatomic) BOOL stopThread;
@property (nonatomic) CFRunLoopRef cfRunLoop;
@property (nonatomic, strong) NSLock* probeQueueLock;
@property (nonatomic, strong) NSMutableArray* probeQueue;
@property (nonatomic) CFRunLoopSourceRef probeQueueInputSource;

@end

@implementation ProbeThread

- (instancetype)init
{
    if (self = [super init])
    {
        NSLog(@"ProbeThread initialised");

        _probeThread = [[NSThread alloc] initWithTarget:self selector:@selector(threadMain:) object:nil];
        _cfRunLoop = NULL;
        _probeQueueLock = [[NSLock alloc] init];
        _probeQueueInputSource = NULL;
        _probeQueue = [NSMutableArray arrayWithCapacity:16];
        _stopThread = NO;
    }
    
    return self;
}

- (void)start
{
    [self.probeThread start];
}

- (void)stop
{
    self.stopThread = YES;
}

#pragma mark - ProbeInterface

- (void)sendProbe:(NSString*)toHostIdentifier onCompletion:(void (^)(Probe*))completionBlock
{
    [NSException raise:@"sendProbe" format:@"Must be over-ridden"];
}

/**
 * Should be overridden by derived classes.
 */
- (int)getNativeSocket
{
    [NSException raise:@"getSocketInputSource" format:@"Must be over-ridden"];
    return 0;
}

/**
 * Should be overridden by derived classes.
 */
- (void)processIncomingSocketData
{
    [NSException raise:@"processIncomingSocketData" format:@"Must be over-ridden"];
}

/**
 * Should be overridden by derived classes.
 */
- (void)cleanupProbes
{
    [NSException raise:@"cleanupProbes" format:@"Must be over-ridden"];
}

#pragma mark - Custom Run Loop Input Source (Public Interface)

/**
 * Add a host to the probe queue. 
 *
 * Expected to be called in the context of the client thread.
 */
- (void)queueProbeForHost:(NSString *)hostIdentifier withPriority:(BOOL)priority onCompletion:(void (^)(Probe*))completionBlock
{
    [self.probeQueueLock lock];
    
    NSDictionary* probeQueueEntry = @{
                                      @"hostIdentifier": hostIdentifier,
                                      @"completionBlock": completionBlock
    };
    
    [self.probeQueue addObject:probeQueueEntry];

    [self.probeQueueLock unlock];
    
    if (priority)
    {
        [self processHostQueue];    // signal worker
    }
}

/**
 * Can be called by a client thread to trigger processing of hosts in the probe queue.
 */
- (void)processHostQueue
{
    if (self.cfRunLoop && self.probeQueueInputSource)
    {
        CFRunLoopSourceSignal(self.probeQueueInputSource);
        CFRunLoopWakeUp(self.cfRunLoop);
    }
}

#pragma mark - Custom Run Loop Input Source (Private)

/**
 * This callback is called when the input source is added to a new run loop. 
 *
 * We don't need to inform any clients about the addition of the source to the run loop so it's a no-op.
 */
void RunLoopSourceScheduleRoutine(void *context, CFRunLoopRef runLoop, CFStringRef mode)
{
    NSLog(@"RunLoopSourceScheduleRoutine called on %@", [NSThread currentThread]);
}

/**
 * This callback is called when the input source itself fires on the run loop. 
 *
 * It's a wrapper to our "wake up and process new probe hosts" method.
 */
void RunLoopSourcePerformRoutine(void *context)
{
    ProbeThread* probeThread = (__bridge ProbeThread*)context;
    [probeThread processNewHosts];
}

/**
 * This callback is called when the input source is removed from a run loop. It's a balancing callback to the schedule one.
 */
void RunLoopSourceCancelRoutine(void *context, CFRunLoopRef runLoop, CFStringRef mode)
{
    NSLog(@"RunLoopSourceCancelRoutine called on %@", [NSThread currentThread]);
}

/**
 * The callback called by the run loop when the custom input source has data to process (ie. hosts to drain from probe queue)
 */
- (void)processNewHosts
{
    [self.probeQueueLock lock];

    NSLog(@"Worker found %lu hosts to probe", self.probeQueue.count);

    NSDictionary* probeQueueEntry;
    
    while ((probeQueueEntry = [self.probeQueue firstObject]))
    {
        [self sendProbe:probeQueueEntry[@"hostIdentifier"] onCompletion:probeQueueEntry[@"completionBlock"]];
        [self.probeQueue removeObjectAtIndex:0];
    }

    [self.probeQueueLock unlock];
}

#pragma mark - Socket Run Loop Input Source

/**
 * Callback for kCFSocketReadCallBack
 */
void SocketCallback(CFSocketRef s, CFSocketCallBackType callbackType, CFDataRef address, const void* data, void* info)
{
    if (callbackType == kCFSocketReadCallBack)
    {
        ProbeThread* probeThread = (__bridge ProbeThread *)(info);
        [probeThread processIncomingSocketData];
    }
}

#pragma mark - Worker Logic

- (void)threadMain:(id)context
{
    NSRunLoop* runLoop = [NSRunLoop currentRunLoop];

    CFSocketRef cfSocketRef = NULL;
    CFRunLoopSourceRef cfSocketSource = NULL;
    
    @try
    {
        NSLog(@"ProbeThread::threadMain running on %@", [NSThread currentThread]);
        
        self.cfRunLoop = CFRunLoopGetCurrent();
        
        // Install custom input source (used to signal that new hosts are present on the queue) on the run loop
        CFRunLoopSourceContext inputSourceContext = {
            0,
            (__bridge void *)(self),
            NULL, NULL, NULL, NULL, NULL,
            &RunLoopSourceScheduleRoutine,
            RunLoopSourceCancelRoutine,
            RunLoopSourcePerformRoutine
        };
        
        self.probeQueueInputSource = CFRunLoopSourceCreate(NULL, 0, &inputSourceContext);
        CFRunLoopAddSource(self.cfRunLoop, self.probeQueueInputSource, kCFRunLoopDefaultMode);
        
        // Install socket input source on the run loop
        int socket = [self getNativeSocket];
        if (socket)
        {
            CFSocketContext socketContext;
            
            socketContext.version = 0;
            socketContext.info = (__bridge void *)(self);
            socketContext.retain = NULL;
            socketContext.release = NULL;
            socketContext.copyDescription = NULL;
            
            if ( ! (cfSocketRef = CFSocketCreateWithNative(kCFAllocatorDefault, socket, kCFSocketReadCallBack, &SocketCallback, &socketContext)))
            {
                [NSException raise:@"socket" format:@"Could not create CFSocket from defined socket input source"];
            }
            else
            {
                if ( ! (cfSocketSource = CFSocketCreateRunLoopSource(kCFAllocatorDefault, cfSocketRef, 0)))
                {
                    [NSException raise:@"socket" format:@"Could not add CFSocket to run loop"];
                }

                CFRunLoopAddSource(self.cfRunLoop, cfSocketSource, kCFRunLoopDefaultMode);
            }
        }

        do
        {
            // Run the run loop but time out after 1 second if no input sources or timers have caused it to exit sooner
            [runLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1]];
            
            [self cleanupProbes];
        }
        while ( ! self.stopThread);
    }
    @catch (NSException *e)
    {
        NSLog(@"ProbeThread::threadMain caught exception: %@", e);
    }
    @finally
    {
        NSLog(@"ProbeThread::threadMain exiting");
        
        if (cfSocketRef)
        {
            CFRelease(cfSocketRef);
        }
        
        if (cfSocketSource)
        {
            CFRelease(cfSocketSource);
        }
    }
}

#pragma mark - Common Probe Methods

/**
 * From Apple's SimplePing example code
 */
- (unsigned short)internetChecksum:(unsigned char*)data length:(unsigned short)length
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

- (float)msElapsedBetween:(struct timeval)startTime endTime:(struct timeval)endTime
{
    float msElapsed = (endTime.tv_usec - startTime.tv_usec) / 1000.0;
    
    if (endTime.tv_sec - startTime.tv_sec)
    {
        msElapsed = ((((endTime.tv_sec - startTime.tv_sec) - 1) * 1000000) + (1000000 - startTime.tv_usec) + endTime.tv_usec) / 1000.0;
    }
    
    return msElapsed;
}

@end
