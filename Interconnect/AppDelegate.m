//
//  AppDelegate.m
//  Interconnect
//
//  Created by oroboto on 10/04/2016.
//  Copyright © 2016 oroboto. All rights reserved.
//

#import "AppDelegate.h"
#import "HostStore.h"
#import "Host.h"
#import "CaptureWorker.h"

@interface AppDelegate ()

@property (weak) IBOutlet NSWindow *window;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    CaptureWorker* worker = [[CaptureWorker alloc] init];
    [self createSampleData];
//  [worker startCapture];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification
{
    // Insert code here to tear down your application
}

#pragma mark - Demo

- (void)createSampleData
{
    HostStore* hostStore = [HostStore sharedStore];
    for (int i = 1; i < 5; i += 3)
    {
        for (int j = 0; j < 256; j++)
        {
            Host* host = [Host createInOrbital:i withIdentifier:[NSString stringWithFormat:@"%d.%d",i,j] andVolume:0.02];
            [hostStore addNode:host];
            [host setRadius:0.0];
            
            if (j == 128)
            {
                [host setTargetVolume:0.5];
                [hostStore updateHost:host withHopCount:8];
            }
        }
    }
    
    NSTimeInterval interval = 10.0;
    [NSTimer scheduledTimerWithTimeInterval:interval target:self selector:@selector(go) userInfo:nil repeats:NO];
}

- (void)go
{
    NSLog(@"firing timer");
    [[HostStore sharedStore] updateHost:@"1.128" withHopCount:5];
}

@end
