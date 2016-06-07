//
//  OpenGLView.h
//  Interconnect
//
//  Created by oroboto on 10/04/2016.
//  Copyright © 2016 oroboto. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class CaptureWorker;

@interface OpenGLView : NSOpenGLView

@property (nonatomic, strong) CaptureWorker* captureWorker;

@end

