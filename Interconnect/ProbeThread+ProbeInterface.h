//
//  ProbeThread+ProbeInterface.h
//  Interconnect
//
//  Any probe types that inherit from ProbeThread must implement these interface methods in order to do meaningful work.
//
//  Created by oroboto on 15/05/2016.
//  Copyright © 2016 oroboto. All rights reserved.
//

@class Probe;

@interface ProbeThread (oroboto_ProbeInterface)

- (int)getNativeSocket;
- (void)processIncomingSocketData;

- (void)sendProbe:(NSString*)toHostIdentifier onCompletion:(void (^)(Probe*))completionBlock;
- (void)cleanupProbes;

@end
