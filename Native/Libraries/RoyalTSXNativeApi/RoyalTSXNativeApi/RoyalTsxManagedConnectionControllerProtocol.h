#import <Cocoa/Cocoa.h>
#import "ConnectionStatusArguments.h"

@protocol RoyalTsxManagedConnectionControllerProtocol <NSObject>

- (void)sessionResized;
- (void)sessionStatusChanged:(ConnectionStatusArguments*)args;

- (NSArray*)performARDAuthWithPrime:(NSData*)prime generator:(NSData*)generator peerKey:(NSData*)peerKey keyLength:(NSNumber*)keyLength;
- (NSArray*)performMSLogon2AuthWithGenerator:(NSData*)generator mod:(NSData*)mod resp:(NSData*)resp;

@end
