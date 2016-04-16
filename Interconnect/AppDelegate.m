//
//  AppDelegate.m
//  Interconnect
//
//  Created by oroboto on 10/04/2016.
//  Copyright © 2016 oroboto. All rights reserved.
//

#import "AppDelegate.h"
#import <pcap/pcap.h>
#import "NodeStore.h"
#import "Host.h"

@interface AppDelegate ()

@property (weak) IBOutlet NSWindow *window;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    NodeStore* nodeStore = [NodeStore sharedStore];
    for (int i = 1; i < 3; i++)
    {
        for (int j = 0; j < 512; j++)
        {
            if (i == 2)
            {
                i = 4;
            }

            Node* node = [Host createInOrbital:i withIdentifier:[NSString stringWithFormat:@"%d%.d",i,j] andVolume:0.02];
            [nodeStore addNode:node];
            [node setRadius:0.0];
        }
    }
    
    return;
    
    struct pcap_pkthdr header;
    const u_char *packet;
    char errbuf[PCAP_ERRBUF_SIZE];
    char *device;
    pcap_t *pcap_handle;
    int i;
    
    device = pcap_lookupdev(errbuf);
    if (device == NULL)
    {
        NSLog(@"pcap_lookupdev failed");
    }
    
    printf("Sniffing on device %s\n", device);
    
    pcap_handle = pcap_open_live("en0", 4096, 1, 0, errbuf);
    if (pcap_handle == NULL)
    {
        NSLog(@"pcap_open_live failed");
    }
    else
    {
        for(i=0; i < 5; i++) {
            packet = pcap_next(pcap_handle, &header);
            printf("Got a %d byte packet\n", header.len);
        }
    }
    
}

- (void)applicationWillTerminate:(NSNotification *)aNotification
{
    // Insert code here to tear down your application
}

@end
