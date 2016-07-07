//
//  PreferencesController.m
//  Interconnect
//
//  Created by oroboto on 4/06/2016.
//  Copyright © 2016 oroboto. All rights reserved.
//

#import "PreferencesSheetController.h"
#import "CaptureWorker.h"
#import "HostStore.h"

@interface PreferencesSheetController ()

@property (nonatomic, strong) CaptureWorker* captureWorker;
@property (nonatomic, strong) NSArray* captureDevices;

@property (nonatomic, strong) IBOutlet NSPanel* progressPanel;
@property (nonatomic, strong) IBOutlet NSTextField* progressMessage;
@property (nonatomic, strong) IBOutlet NSProgressIndicator* progressIndicator;
@property (nonatomic, strong) IBOutlet NSTextField* textFilter;
@property (nonatomic, strong) IBOutlet NSPopUpButton* selectInterface;
@property (nonatomic, strong) IBOutlet NSPopUpButton* selectProbe;
@property (nonatomic, strong) IBOutlet NSButton* btnUnusualPortsOnly;
@property (nonatomic, strong) IBOutlet NSButton* btnDisplayIntermediateRouters;
@property (nonatomic, strong) IBOutlet NSButton* btnCompleteTimedOutProbes;
@property (nonatomic, strong) IBOutlet NSButton* btnDisplayOriginConnector;

@end

@implementation PreferencesSheetController

- (instancetype)initWithCaptureWorker:(CaptureWorker*)captureWorker
{
    if (self = [super initWithWindowNibName:@"PreferencesSheet"])
    {
        _captureWorker = captureWorker;
    }
    
    return self;
}

- (void)windowDidLoad
{
    // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
    [super windowDidLoad];

    // Need to wait until the NIB file has loaded before our outlets are connected
    [self setupControls];
}

- (void)probeTypeChanged:(id)sender
{
    if (self.selectProbe.selectedTag == kProbeTypeThreadTraceroute)
    {
        self.btnCompleteTimedOutProbes.enabled = YES;
        self.btnCompleteTimedOutProbes.state = self.captureWorker.completeTimedOutProbes ? NSOnState : NSOffState;
    }
    else
    {
        self.btnCompleteTimedOutProbes.state = NSOffState;
        self.btnCompleteTimedOutProbes.enabled = NO;
    }
}

- (void)setupControls
{
    if (self.window)
    {
        [self.selectInterface removeAllItems];
        self.captureDevices = [self.captureWorker captureDevices];
        
        NSString *currentCaptureInterface = self.captureWorker.captureInterface;
        NSUInteger interfaceIndex = 0;
        
        for (NSDictionary* interfaceDetails in self.captureDevices)
        {
            if (interfaceDetails[@"desc"])
            {
                [self.selectInterface addItemWithTitle:[NSString stringWithFormat:@"%@ (%@)", interfaceDetails[@"name"], interfaceDetails[@"description"]]];
            }
            else
            {
                [self.selectInterface addItemWithTitle:[NSString stringWithFormat:@"%@", interfaceDetails[@"name"]]];
            }
            
            if ([interfaceDetails[@"name"] isEqualToString:currentCaptureInterface])
            {
                [self.selectInterface selectItemAtIndex:interfaceIndex];
            }
            
            interfaceIndex++;
        }
        
        [self.textFilter setStringValue:self.captureWorker.captureFilter];
        
        [self.selectProbe setTag:self.captureWorker.probeType];
        self.btnDisplayIntermediateRouters.state = self.captureWorker.ignoreProbeIntermediateTraffic ? NSOffState : NSOnState;
        [self probeTypeChanged:self];
        
        self.btnDisplayOriginConnector.state = [[HostStore sharedStore] showOriginConnectorOnTrafficUpdate] ? NSOnState : NSOffState;
    }
}

- (IBAction)displayModallyInWindow:(NSWindow *)window
{
    /**
     * Our outlets won't be connected until the window is loaded from the NIB file. The window isn't loaded from
     * the NIB file until it is first requested for display by beginSheet:. We set up our controls on the first
     * load of the window in windowDidLoad: and subsequent displays of the already loaded window here.
     */
    [self setupControls];
    
    [NSApp beginSheet:self.window
       modalForWindow:window
        modalDelegate:self
       didEndSelector:@selector(didEndSheet:returnCode:contextInfo:)
          contextInfo:nil];
}

- (IBAction)applyChanges:(id)sender
{
    [sender setEnabled:NO];
    
    self.progressMessage.stringValue = @"Reticulating splines ...";
    [self.progressIndicator startAnimation:nil];
    
    [NSApp beginSheet:self.progressPanel
       modalForWindow:self.window
        modalDelegate:self
       didEndSelector:@selector(didEndSheet:returnCode:contextInfo:)
          contextInfo:nil];
    
    void (^stopBlock)() = ^() {
        NSLog(@"Capture thread was stopped, reconfiguring");

        [self applyConfiguration];
        
        [sender setEnabled:YES];
        [NSApp endSheet:self.progressPanel];

        [NSApp endSheet:self.window];
    };
        
    if ( ! [self.captureWorker stopCapture:stopBlock])
    {
        NSLog(@"Capture thread was not stopped, it was probably never running");
        
        [self applyConfiguration];
        
        [sender setEnabled:YES];
        [NSApp endSheet:self.progressPanel];
        
        [NSApp endSheet:self.window];
    }
}

- (void)applyConfiguration
{
    self.progressMessage.stringValue = @"Reconfiguring display options ...";
    
    [[HostStore sharedStore] setShowOriginConnectorOnTrafficUpdate:(self.btnDisplayOriginConnector.state == NSOnState) ? YES : NO];
    
    if ([self.captureDevices objectAtIndex:self.selectInterface.indexOfSelectedItem])
    {
        self.progressMessage.stringValue = @"Restarting capture thread ...";
        
        [self.captureWorker setProbeMethod:(ProbeType)self.selectProbe.selectedTag
                    completeTimedOutProbes:(self.btnCompleteTimedOutProbes.state == NSOnState) ? YES : NO
                 ignoreIntermediateTraffic:(self.btnDisplayIntermediateRouters.state == NSOnState) ? NO : YES];
        [self.captureWorker startCapture:[[self.captureDevices objectAtIndex:self.selectInterface.indexOfSelectedItem] objectForKey:@"name"] withFilter:self.textFilter.stringValue];
    }
}

- (IBAction)cancelChanges:(id)sender
{
    [NSApp endSheet:self.window];   
}

- (void)didEndSheet:(NSWindow*)sheet returnCode:(NSInteger)returnCode contextInfo:(void*)contextInfo
{
    [sheet orderOut:self];
}

@end

