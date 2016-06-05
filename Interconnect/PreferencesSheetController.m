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
    [super windowDidLoad];
    // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
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

- (IBAction)displayModallyInWindow:(NSWindow *)window
{
    [self.selectProbe setTag:self.captureWorker.probeType];
    [self probeTypeChanged:self];
    
    self.btnDisplayOriginConnector.state = [[HostStore sharedStore] showOriginConnectorOnTrafficUpdate] ? NSOnState : NSOffState;
    
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
        NSLog(@"Capture Thread was stopped, restarting");
        self.progressMessage.stringValue = @"Reconfiguring capture thread ...";
        
        [self.captureWorker setProbeMethod:(ProbeType)self.selectProbe.selectedTag completeTimedOutProbes:(self.btnCompleteTimedOutProbes.state == NSOnState) ? YES : NO];
        [[HostStore sharedStore] setShowOriginConnectorOnTrafficUpdate:(self.btnDisplayOriginConnector.state == NSOnState) ? YES : NO];

        self.progressMessage.stringValue = @"Restarting capture thread ...";

        [sender setEnabled:YES];
        [NSApp endSheet:self.progressPanel];

        [self.captureWorker startCapture];
        [NSApp endSheet:self.window];
    };
        
    [self.captureWorker stopCapture:stopBlock];
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

