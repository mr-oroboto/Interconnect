//
//  HelpSheetController.m
//  Interconnect
//
//  Created by oroboto on 21/05/2016.
//  Copyright © 2016 oroboto. All rights reserved.
//

#import "HelpSheetController.h"

@interface HelpSheetController ()

@end

@implementation HelpSheetController

- (void)windowDidLoad
{
    [super windowDidLoad];
    
    // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
}

- (void)displayModallyInWindow:(NSWindow *)window
{
    [NSApp beginSheet:self.window
       modalForWindow:window
        modalDelegate:self
       didEndSelector:@selector(didEndSheet:returnCode:contextInfo:)
          contextInfo:nil];
}

- (IBAction)closeSheet:(id)sender
{
    [NSApp endSheet:self.window];
}

- (void)didEndSheet:(NSWindow*)sheet returnCode:(NSInteger)returnCode contextInfo:(void*)contextInfo
{
    [sheet orderOut:self];
}

@end
