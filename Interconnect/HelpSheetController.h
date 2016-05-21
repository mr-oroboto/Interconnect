//
//  HelpSheetController.h
//  Interconnect
//
//  Created by oroboto on 21/05/2016.
//  Copyright © 2016 oroboto. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface HelpSheetController : NSWindowController

- (void)displayModallyInWindow:(NSWindow*)window;
- (IBAction)closeSheet:(id)sender;


@end
