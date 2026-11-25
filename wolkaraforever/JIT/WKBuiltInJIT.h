// Built-in JIT: the app enables JIT for itself through its bundled StikJIT helper extension,
// over the device's own developer services (reached through LocalDevVPN), when Play is
// pressed. It replaces the separate JIT-enabler app the External JIT route otherwise needs.
//
// Nothing here changes how memory is prepared or checked: the helper runs StikJIT's universal
// script, which answers the same JIT26 breakpoint protocol the runtime already speaks
// (runtime/DebuggerArena.c), and the existing gates still refuse guest entry while anything is
// attached or the arena is not executable.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Where the Remote Pairing file lives: Library/StikJIT/pairingFile.plist in the app's own
// container - private to the app, not in the Files-visible Documents folder.
FOUNDATION_EXPORT NSString *WKBuiltInJITPairingFilePath(void);

// nil when Built-in JIT can be attempted, otherwise the reason it cannot, worded for the user.
FOUNDATION_EXPORT NSString *_Nullable WKBuiltInJITUnavailableReason(void);

// YES while an acquisition is attached or preparing memory: the launcher's own
// foreground-time arena reservation must stay out of the way then.
FOUNDATION_EXPORT BOOL WKBuiltInJITInProgress(void);

@interface WKBuiltInJIT : NSObject
// Main thread only. Starts the helper, waits for its debugger to attach to this process,
// then calls `reserve` once on a background thread (it issues the JIT26 breakpoints, which the
// helper's script services, and ends by asking the debugger to detach) and reports its result.
// `progress` and `completion` run on the main thread; `failure` is nil only when `reserve`
// returned YES and the helper reported that the script finished.
- (void)acquireWithReserve:(BOOL (^)(void))reserve
                  progress:(void (^)(NSString *stage))progress
                completion:(void (^)(NSString *_Nullable failure))completion;
@end

NS_ASSUME_NONNULL_END
