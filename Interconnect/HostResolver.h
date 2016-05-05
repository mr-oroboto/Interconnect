//
//  HostResolver.h
//  Interconnect
//
//  Created by oroboto on 5/05/2016.
//  Copyright © 2016 oroboto. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface HostResolver : NSObject

- (instancetype)initWithIPAddress:(NSString*)ipAddress;
- (NSString*)resolveHostName;
- (NSDictionary*)resolveASDetails;

@end
