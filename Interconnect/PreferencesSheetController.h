//
//  PreferencesController.h
//  Interconnect
//
//  Created by oroboto on 4/06/2016.
//  Copyright © 2016 oroboto. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class CaptureWorker;

@interface PreferencesSheetController : NSWindowController

- (instancetype)initWithCaptureWorker:(CaptureWorker*)captureWorker;

- (void)displayModallyInWindow:(NSWindow*)window;

- (IBAction)probeTypeChanged:(id)sender;

- (IBAction)cancelChanges:(id)sender;
- (IBAction)applyChanges:(id)sender;

@end
