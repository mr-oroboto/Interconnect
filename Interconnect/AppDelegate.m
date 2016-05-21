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
#import "ICMPTimeExceededProbeThread.h"
#import "HelpSheetController.h"

@interface AppDelegate ()

@property (weak) IBOutlet NSWindow *window;
@property (nonatomic, strong) ProbeThread* thread;
@property (nonatomic, strong) HelpSheetController* helpSheet;

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    CaptureWorker* worker = [[CaptureWorker alloc] init];
//  [self createSampleData];
    [worker startCapture];

    return;
}

- (void)applicationWillTerminate:(NSNotification *)aNotification
{
    // Insert code here to tear down your application
}

- (IBAction)displayHelpSheet:(id)sender
{
    if ( ! self.helpSheet)
    {
        self.helpSheet = [[HelpSheetController alloc] initWithWindowNibName:@"HelpSheet"];
    }
    
    [self.helpSheet displayModallyInWindow:self.window];
}

#pragma mark - Demo

- (void)createSampleData
{
    HostStore* hostStore = [HostStore sharedStore];
    for (int i = 1; i < 5; i += 3)
    {
        for (int j = 0; j < 8; j++)
        {
            Host* host = [Host createInGroup:i withIdentifier:[NSString stringWithFormat:@"%d.%d",i,j] andVolume:0.02];
            [hostStore lockStore];
            [hostStore addNode:host];
            [host setRadius:0.0];
            [hostStore unlockStore];
            
            if (j == 128)
            {
                [host setTargetVolume:0.5];
                [hostStore updateHost:host.identifier withGroup:8];
            }
        }
    }
    
    NSTimeInterval interval = 20.0;
    [NSTimer scheduledTimerWithTimeInterval:interval target:self selector:@selector(sampleOrbitalChange) userInfo:nil repeats:NO];
}

- (void)sampleOrbitalChange
{
    [[HostStore sharedStore] updateHost:@"1.128" withGroup:5];
}

@end
