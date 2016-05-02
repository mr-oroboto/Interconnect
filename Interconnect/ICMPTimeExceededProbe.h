//
//  ICMPTimeExceededProbe.h
//  Interconnect
//
//  Created by jjs on 1/05/2016.
//  Copyright © 2016 oroboto. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface ICMPTimeExceededProbe : NSObject

+ (ICMPTimeExceededProbe*)probeWithIPAddress:(NSString*)ipAddress;
- (NSInteger)measureHopCount;

@end
