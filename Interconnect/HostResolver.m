//
//  HostResolver.m
//  Interconnect
//
//  Created by oroboto on 5/05/2016.
//  Copyright © 2016 oroboto. All rights reserved.
//

#import "HostResolver.h"
#import <arpa/inet.h>
#import <netdb.h>

#define kASWhoisService @"v4.whois.cymru.com"       // Team Cymru

@interface HostResolver ()

@property (nonatomic, copy) NSString* ipAddress;

@end

@implementation HostResolver

- (instancetype)initWithIPAddress:(NSString *)ipAddress
{
    if (self = [super init])
    {
        self.ipAddress = ipAddress;
    }
    
    return self;
}

- (NSString*)resolveHostName
{
    struct in_addr sin_addr;
    
    if ( ! inet_aton([self.ipAddress cStringUsingEncoding:NSASCIIStringEncoding], &sin_addr))
    {
        NSLog(@"Could not convert IP address [%@]", self.ipAddress);
        return @"";
    }
    
    char hostname[NI_MAXHOST];
    struct sockaddr_in saddr;
    memset(&saddr, 0, sizeof(saddr));
    saddr.sin_addr = sin_addr;
    saddr.sin_family = AF_INET;
    saddr.sin_len = sizeof(saddr);
    
    if (getnameinfo((const struct sockaddr*)&saddr, saddr.sin_len, hostname, sizeof(hostname), NULL, 0, NI_NOFQDN | NI_NAMEREQD) != 0)
    {
        NSLog(@"Could not resolve IP address [%@]", self.ipAddress);
        return @"";
    }
    
    return [NSString stringWithFormat:@"%s", hostname];
}

- (NSDictionary*)resolveASDetails
{
    NSMutableDictionary *asDetails = [NSMutableDictionary dictionary];

    CFHostRef whoisHost = NULL;
    CFReadStreamRef cfStreamRead = NULL;
    CFWriteStreamRef cfStreamWrite = NULL;
    
    @try
    {
        whoisHost = CFHostCreateWithName(NULL, kASWhoisService);
        if ( ! CFHostStartInfoResolution(whoisHost, kCFHostAddresses, NULL))
        {
            [NSException raise:@"" format:@"Unable to create CFHost for resolution of whois server"];
        }
        
        CFStreamCreatePairWithSocketToCFHost(NULL, whoisHost, 43, &cfStreamRead, &cfStreamWrite);
        if ( ! cfStreamRead || ! cfStreamWrite)
        {
            [NSException raise:@"" format:@"Unable to create stream pair for socket"];
        }
        
        NSInputStream* streamIn = CFBridgingRelease(cfStreamRead);   // let ARC take ownership of CF stream, no need to release it now
        NSOutputStream* streamOut = CFBridgingRelease(cfStreamWrite); // as above
        
        [streamIn open];
        [streamOut open];
        
        // Perform blocking I/O, we're on our own thread.
        NSString *request = [NSString stringWithFormat:@"%@\r\n", self.ipAddress];
        uint8_t* sendBuf = (uint8_t*)[request cStringUsingEncoding:NSASCIIStringEncoding];
        NSInteger bytesWritten = 0, bytesToWrite = strlen((char*)sendBuf);
        
        while (bytesWritten < bytesToWrite)
        {
            bytesWritten += [streamOut write:sendBuf+bytesWritten maxLength:bytesToWrite];
            if ([streamOut streamStatus] == NSStreamStatusError)
            {
                [NSException raise:@"" format:@"Error writing to whois stream, wrote %ld bytes: %@", (long)bytesWritten, [[streamOut streamError] localizedDescription]];
            }
        }
        
        NSMutableData* recvBuf = [NSMutableData dataWithCapacity:1024];
        uint8_t recvChunkBuf[1024];
        NSInteger bytesRead = 0;
        
        while (true)
        {
            if ((bytesRead = [streamIn read:recvChunkBuf maxLength:sizeof(recvChunkBuf)]) > 0)
            {
                [recvBuf appendBytes:(const void*)recvChunkBuf length:bytesRead];
            }

            if ([streamIn streamStatus] != NSStreamStatusOpen && [streamIn streamStatus] != NSStreamStatusReading)
            {
                break;
            }
        }
        
        // If we read any bytes, try to interpret the output
        if ([recvBuf length])
        {
            char null = 0x00;
            [recvBuf appendBytes:&null length:1];       // null terminate it
            NSString *whoisResult = [NSString stringWithCString:(const char*)[recvBuf bytes] encoding:NSASCIIStringEncoding];
            NSArray* lines = [whoisResult componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
            
            // Cymru should return at least two lines, the second is the one we're interested in.
            if (lines.count >= 2)
            {
                NSArray* tokens = [lines[1] componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"|"]];
                if (tokens.count >= 3)
                {
                    asDetails[@"as"] = [tokens[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                    asDetails[@"asDesc"] = [tokens[2] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                }
            }
        }
    }
    @catch (NSException *e)
    {
        NSLog(@"AS detail resolution failed: %@", e.reason);
    }
    @finally
    {
        if (whoisHost)
        {
            CFRelease(whoisHost);
        }
        
    }
    
    return asDetails;
}

@end
