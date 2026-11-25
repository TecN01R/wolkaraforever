#import "WKBuiltInJIT.h"
#import "WKJITProtocol.h"
#import "WolkaraForeverLog.h"
#include "HostDiagnostics.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <unistd.h>

// Security framework SPI (as StikJIT's integration guide uses it): read one of this process's
// own entitlements. Not App Store API; this build is sideloaded.
extern CFTypeRef SecTaskCreateFromSelf(CFAllocatorRef allocator);
extern CFTypeRef SecTaskCopyValueForEntitlement(CFTypeRef task, CFStringRef entitlement, CFErrorRef *error);

// Private NSExtension API: start one of this app's own embedded extensions as a process.
@interface NSObject (WKBuiltInJITExtension)
+ (id)extensionWithIdentifier:(NSString *)identifier error:(NSError **)error;
- (NSUUID *)beginExtensionRequestWithInputItems:(NSArray *)items error:(NSError **)error;
- (pid_t)pidForRequestIdentifier:(NSUUID *)request;
- (void)cancelExtensionRequestWithIdentifier:(NSUUID *)request;
@end

static NSString *const WKJITHelperBundleName = @"WolkaraJITHelper.appex";
// The first preparation downloads the developer disk image (tens of MB), so allow minutes.
static const NSTimeInterval WKJITTimeout = 300;
static atomic_bool inProgress;

NSString *WKBuiltInJITPairingFilePath(void) {
    NSString *library = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject;
    return [[library stringByAppendingPathComponent:@"StikJIT"] stringByAppendingPathComponent:@"pairingFile.plist"];
}

BOOL WKBuiltInJITInProgress(void) { return atomic_load(&inProgress); }

static BOOL HasGetTaskAllow(void) {
    CFTypeRef task = SecTaskCreateFromSelf(NULL);
    if (!task) return NO;
    CFTypeRef value = SecTaskCopyValueForEntitlement(task, CFSTR("get-task-allow"), NULL);
    BOOL allowed = value && CFEqual(value, kCFBooleanTrue);
    if (value) CFRelease(value);
    CFRelease(task);
    return allowed;
}

static NSString *HelperIdentifier(void) {
    NSURL *url = [NSBundle.mainBundle.builtInPlugInsURL URLByAppendingPathComponent:WKJITHelperBundleName];
    return url ? [NSBundle bundleWithURL:url].bundleIdentifier : nil;
}

NSString *WKBuiltInJITUnavailableReason(void) {
    if (@available(iOS 17.4, *)) {} else return @"Built-in JIT needs iOS 17.4 or later.";
    if (getenv("LC_HOME_PATH"))
        return @"Built-in JIT cannot start its helper inside LiveContainer.";
    if (!HasGetTaskAllow())
        return @"This installation was signed without get-task-allow, so nothing can enable JIT for it. "
               @"Reinstall it with a development signature (duo/install.sh does).";
    if (!HelperIdentifier())
        return @"This build has no JIT helper (WolkaraJITHelper.appex is missing).";
    if (![NSFileManager.defaultManager isReadableFileAtPath:WKBuiltInJITPairingFilePath()])
        return @"No pairing file is installed yet. Create a Remote Pairing file for this phone "
               @"(idevice_pair) and copy it into the app with duo/push_pairing.sh on your computer.";
    return nil;
}

@interface WKBuiltInJIT () <NSXPCListenerDelegate, WKJITHostEvents>
@end

@implementation WKBuiltInJIT {
    NSXPCListener *_listener;
    NSXPCConnection *_connection;
    id _extension;
    NSUUID *_request;
    pid_t _helperPID;
    NSData *_pairing;
    BOOL (^_reserve)(void);
    void (^_progress)(NSString *);
    void (^_completion)(NSString *);
    dispatch_queue_t _watchQueue;
    dispatch_source_t _poll;
    NSString *_stage;
    // Main-thread state.
    BOOL _attached, _reserveDone, _reserved, _replyDone, _finished;
    NSString *_replyFailure;
}

- (void)acquireWithReserve:(BOOL (^)(void))reserve
                  progress:(void (^)(NSString *))progress
                completion:(void (^)(NSString *))completion {
    NSAssert(NSThread.isMainThread, @"Built-in JIT starts on the main thread");
    _reserve = [reserve copy]; _progress = [progress copy]; _completion = [completion copy];
    NSString *unavailable = WKBuiltInJITUnavailableReason();
    if (unavailable) { [self finish:unavailable]; return; }
    NSError *error = nil;
    _pairing = [NSData dataWithContentsOfFile:WKBuiltInJITPairingFilePath() options:0 error:&error];
    if (!_pairing.length) { [self finish:@"The pairing file could not be read."]; return; }
    atomic_store(&inProgress, true);
    WKLog("jit", @"built-in: starting the helper for pid %d", getpid());
    [self stage:@"Starting the JIT helper"];

    Class extensionClass = NSClassFromString(@"NSExtension");
    if (![extensionClass respondsToSelector:@selector(extensionWithIdentifier:error:)]) {
        [self finish:@"This iOS version does not let the app start its JIT helper."]; return;
    }
    _extension = [extensionClass extensionWithIdentifier:HelperIdentifier() error:&error];
    if (!_extension || ![_extension respondsToSelector:@selector(beginExtensionRequestWithInputItems:error:)]) {
        [self finish:[NSString stringWithFormat:@"iOS could not load the JIT helper (%@ %ld). Reinstall the app so "
                      @"the helper is signed with it.", error.domain ?: @"no error", (long)error.code]];
        return;
    }
    _listener = [NSXPCListener anonymousListener];
    _listener.delegate = self;
    [_listener resume];
    NSExtensionItem *item = [NSExtensionItem new];
    item.userInfo = @{WK_JIT_ENDPOINT_KEY: _listener.endpoint};
    _request = [_extension beginExtensionRequestWithInputItems:@[item] error:&error];
    if (!_request) {
        [self finish:[NSString stringWithFormat:@"iOS refused to start the JIT helper (%@ %ld).",
                      error.domain ?: @"no error", (long)error.code]];
        return;
    }
    if ([_extension respondsToSelector:@selector(pidForRequestIdentifier:)])
        _helperPID = [_extension pidForRequestIdentifier:_request];
    WKLog("jit", @"built-in: helper started (pid %d)", _helperPID);

    __weak WKBuiltInJIT *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(WKJITTimeout * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        WKBuiltInJIT *strongSelf = weakSelf;
        if (strongSelf && !strongSelf->_finished)
            [strongSelf finish:[NSString stringWithFormat:@"JIT was not ready after %.0f seconds (last step: %@).",
                                WKJITTimeout, strongSelf->_stage ?: @"none"]];
    });
}

// Only the helper this object started may connect, and only once.
- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)connection {
    (void)listener;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_finished || self->_connection ||
            (self->_helperPID > 0 && connection.processIdentifier != self->_helperPID)) {
            WKLog("jit", @"built-in: refused a connection from pid %d", connection.processIdentifier);
            [connection invalidate];
            return;
        }
        self->_connection = connection;
        connection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(WKJITHostEvents)];
        connection.exportedObject = self;
        connection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(WKJITWorker)];
        __weak WKBuiltInJIT *weakSelf = self;
        connection.invalidationHandler = ^{
            dispatch_async(dispatch_get_main_queue(), ^{
                WKBuiltInJIT *strongSelf = weakSelf;
                if (strongSelf && !strongSelf->_replyDone)
                    [strongSelf helperReplied:@"The JIT helper stopped before it finished."];
            });
        };
        [connection resume];
        id<WKJITWorker> worker = [connection remoteObjectProxyWithErrorHandler:^(NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf helperReplied:[NSString stringWithFormat:@"The JIT helper could not be reached (%@ %ld).",
                                         error.domain, (long)error.code]];
            });
        }];
        [self watchForAttachment];
        [self stage:@"Connecting to the device"];
        [worker enableJITForProcess:getpid() pairingFile:self->_pairing reply:^(NSString *failure) {
            dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf helperReplied:failure]; });
        }];
        self->_pairing = nil;
    });
    return YES;
}

// The script attaches, then waits for our breakpoints: reserve as soon as it is attached.
- (void)watchForAttachment {
    _watchQueue = dispatch_queue_create("wolkaraforever.jit.reserve", DISPATCH_QUEUE_SERIAL);
    _poll = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _watchQueue);
    dispatch_source_set_timer(_poll, DISPATCH_TIME_NOW, 20 * NSEC_PER_MSEC, 5 * NSEC_PER_MSEC);
    __weak WKBuiltInJIT *weakSelf = self;
    BOOL (^reserve)(void) = _reserve;
    __block BOOL started = NO;
    dispatch_source_t poll = _poll;
    dispatch_source_set_event_handler(_poll, ^{
        if (started || !hd_debugger_attached()) return;
        started = YES;
        dispatch_source_cancel(poll);
        dispatch_async(dispatch_get_main_queue(), ^{
            WKBuiltInJIT *strongSelf = weakSelf;
            if (!strongSelf) return;
            strongSelf->_attached = YES;
            [strongSelf stage:@"Preparing executable memory"];
        });
        BOOL reserved = reserve();
        dispatch_async(dispatch_get_main_queue(), ^{
            WKBuiltInJIT *strongSelf = weakSelf;
            if (!strongSelf) return;
            strongSelf->_reserveDone = YES;
            strongSelf->_reserved = reserved;
            WKLog("jit", @"built-in: memory %s", reserved ? "prepared and the debugger detached" : "was not prepared");
            [strongSelf settle];
        });
    });
    dispatch_resume(_poll);
}

- (void)helperReplied:(NSString *)failure {
    if (_replyDone || _finished) return;
    _replyDone = YES;
    _replyFailure = failure;
    WKLog("jit", @"built-in: helper finished: %@", failure ?: @"success");
    [self settle];
}

// Done when the helper has answered and, if it ever attached, our reservation has returned.
- (void)settle {
    if (_finished || !_replyDone) return;
    if (_attached && !_reserveDone) return;
    if (_reserveDone && _reserved && !_replyFailure) { [self finish:nil]; return; }
    NSString *failure = _replyFailure ?: (_attached ? @"The JIT script finished but no executable memory was prepared."
                                                    : @"The JIT script finished without attaching to the app.");
    [self finish:[failure stringByAppendingString:
                  @"\n\nCheck that LocalDevVPN is connected (on Wi-Fi, or: cellular data on, connect LocalDevVPN, "
                  @"then Airplane Mode), Developer Mode is on, and the pairing file is for this phone."]];
}

- (void)finish:(NSString *)failure {
    if (_finished) return;
    _finished = YES;
    if (_poll && !_attached) dispatch_source_cancel(_poll);
    [_connection invalidate]; _connection = nil;
    [_listener invalidate]; _listener = nil;
    if (_request && [_extension respondsToSelector:@selector(cancelExtensionRequestWithIdentifier:)])
        [_extension cancelExtensionRequestWithIdentifier:_request];
    _request = nil; _extension = nil; _pairing = nil;
    // An attached reservation that never returned is still running: stay "in progress".
    if (!_attached || _reserveDone) atomic_store(&inProgress, false);
    WKLog("jit", @"built-in: %@", failure ? [@"failed: " stringByAppendingString:failure] : @"JIT ready");
    void (^completion)(NSString *) = _completion;
    _completion = nil; _progress = nil;
    if (completion) completion(failure);
}

- (void)stage:(NSString *)stage {
    _stage = stage;
    if (_progress) _progress(stage);
}

#pragma mark WKJITHostEvents (from the helper, on the connection's queue)

- (void)jitStage:(NSString *)stage {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_finished) return;
        WKLog("jit", @"built-in: %@", stage);
        [self stage:stage];
    });
}

- (void)jitLog:(NSString *)line {
    WKLog("jit", @"script: %@", line);
}
@end
