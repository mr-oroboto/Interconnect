//
//  ICMPProbe.h
//  Interconnect
//
//  Created by oroboto on 17/05/2016.
//  Copyright © 2016 oroboto. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface ICMPProbe : NSObject

+ (instancetype)probeWithIPAddress:(NSString*)ipAddress;

@end
