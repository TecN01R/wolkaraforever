// The two halves of Built-in JIT, as they speak to each other over XPC.
//
// The app (the target of JIT) cannot attach a debugger to itself, so it starts its bundled
// helper extension as a second process, hands it an anonymous XPC endpoint inside the
// extension request (key WKJITEndpointKey), and the helper connects back. The helper exports
// WKJITWorker; the app exports WKJITHostEvents for progress. No game bytes cross this line:
// only the app's own process ID, the pairing file and human-readable progress.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// The NSExtensionItem userInfo key that carries the app's NSXPCListenerEndpoint.
// The helper spells the same string itself (Swift cannot import this macro).
#define WK_JIT_ENDPOINT_KEY @"WKJITEndpoint"

@protocol WKJITHostEvents
// A preparation stage ("Mounting the developer disk image 40 %"), for the app's status line.
- (void)jitStage:(NSString *)stage NS_SWIFT_NAME(jitStage(_:));
// One line of the JIT script's own log, for the app's diagnostics log.
- (void)jitLog:(NSString *)line NS_SWIFT_NAME(jitLog(_:));
@end

@protocol WKJITWorker
// Prepare the device (reachability, developer disk image) and run the universal JIT script
// against `pid`. Replies once the script has finished, which is after the app has asked the
// debugger to detach; `failure` is nil on success and says what went wrong otherwise.
- (void)enableJITForProcess:(int)pid
                pairingFile:(NSData *)pairingFile
                      reply:(void (^)(NSString *_Nullable failure))reply
    NS_SWIFT_NAME(enableJIT(forProcess:pairingFile:reply:));
@end

NS_ASSUME_NONNULL_END
