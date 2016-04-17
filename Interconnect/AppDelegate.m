//
//  AppDelegate.m
//  Interconnect
//
//  Created by oroboto on 10/04/2016.
//  Copyright © 2016 oroboto. All rights reserved.
//

#import "AppDelegate.h"
#import "NodeStore.h"
#import "Host.h"
#import "CaptureWorker.h"

@interface AppDelegate ()

@property (weak) IBOutlet NSWindow *window;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    CaptureWorker* worker = [[CaptureWorker alloc] init];
    [worker startCapture];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification
{
    // Insert code here to tear down your application
}

#pragma mark - Demo

- (void)createSampleData
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
            
            Node* node = [Host createInOrbital:i withIdentifier:[NSString stringWithFormat:@"%d.%d",i,j] andVolume:0.02];
            [nodeStore addNode:node];
            [node setRadius:0.0];
            
            if (j == 256)
            {
                [node setTargetVolume:0.5];
            }
        }
    }
}

@end
