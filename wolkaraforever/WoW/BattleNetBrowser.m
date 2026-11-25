#import "BattleNetBrowser.h"
#import "BattleNetSession.h"
#import "../App/WKLocalization.h"
#import "../App/WolkaraForeverLog.h"
#import <WebKit/WebKit.h>

@interface TKBattleNetBrowser () <WKNavigationDelegate>
@end

@implementation TKBattleNetBrowser {
    NSString *_region;
    NSString *_locale;
    WKWebView *_web;
    BOOL _finished;
    BOOL _trustedMainNavigation;
    WKNavigation *_navigation;
    NSTimer *_deadline;
}

// Fork: "Stay signed in on this device", off by default. See +staySignedInDataStore.
static NSString *const TKBattleNetStaySignedInKey=@"WoWBrowserLoginStaySignedIn";

+ (WKWebsiteDataStore *)memoryDataStore {
    // Isolated from add-on browsing and kept in memory only (hardened local build):
    // the Battle.net web session can mint new launch tickets, so it is never written
    // to disk and ends with this process. WebKit owns the cookies; the launcher never
    // reads or exports their values. One store per process so a cancelled attempt
    // can be retried without signing in again.
    static WKWebsiteDataStore *store;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ store=WKWebsiteDataStore.nonPersistentDataStore; });
    return store;
}
// Fork: the player's opt-in to keep Battle.net's web session across app launches, so the
// sign-in page needs no typing next time. It is a second WebKit store of its own - still
// isolated from add-on browsing, still never read or exported by the launcher - that WebKit
// keeps on disk inside this app's container. The price is the one the store above avoids: while
// it is kept, whoever can open this app on the unlocked device can start the game on that
// account. Off, disabling the login and "Clear sign-in data" all empty it.
+ (nullable WKWebsiteDataStore *)staySignedInDataStore {
    if (@available(iOS 17.0, *)) {
        static WKWebsiteDataStore *store;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            NSUUID *identifier=[[NSUUID alloc] initWithUUIDString:@"6B1D2C0A-5E0F-4C1B-9A57-3D2B8E64F0A1"];
            store=[WKWebsiteDataStore dataStoreForIdentifier:identifier];
        });
        return store;
    }
    return nil;
}
+ (BOOL)staysSignedIn {
    return [NSUserDefaults.standardUserDefaults boolForKey:TKBattleNetStaySignedInKey] &&
           [self staySignedInDataStore]!=nil;
}
+ (BOOL)canStaySignedIn { return [self staySignedInDataStore]!=nil; }
+ (void)setStaysSignedIn:(BOOL)stay completion:(nullable void (^)(void))completion {
    if (!completion) completion=^{};
    [NSUserDefaults.standardUserDefaults setBool:stay && [self canStaySignedIn] forKey:TKBattleNetStaySignedInKey];
    WKLog("battle-login", @"stay signed in: %@", [self staysSignedIn] ? @"on" : @"off");
    // Either way the next sign-in starts clean: turning it off must leave nothing on disk, and
    // turning it on must not carry over a session the player did not ask to keep.
    [self clearSavedSignInWithCompletion:completion];
}
+ (WKWebsiteDataStore *)signInDataStore {
    WKWebsiteDataStore *kept=[self staysSignedIn] ? [self staySignedInDataStore] : nil;
    return kept ?: [self memoryDataStore];
}
+ (void)clearSavedSignInWithCompletion:(void (^)(void))completion {
    [TKBattleNetSession clear];
    // Both stores, whichever is in use: nothing of a sign-in survives a clear.
    WKWebsiteDataStore *kept=[self staySignedInDataStore];
    [[self memoryDataStore] removeDataOfTypes:WKWebsiteDataStore.allWebsiteDataTypes
                              modifiedSince:NSDate.distantPast completionHandler:^{
        if (!kept) { if (completion) completion(); return; }
        [kept removeDataOfTypes:WKWebsiteDataStore.allWebsiteDataTypes
                  modifiedSince:NSDate.distantPast completionHandler:^{ if (completion) completion(); }];
    }];
}

- (instancetype)initWithRegion:(NSString *)region locale:(NSString *)locale {
    if ((self=[super init])) {
        _region=[region.lowercaseString copy];
        _locale=[locale copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=WKLocalized(@"login.title");
    self.view.backgroundColor=UIColor.systemBackgroundColor;
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
    WKWebViewConfiguration *configuration=[WKWebViewConfiguration new];
    // No injected scripts, password storage or JavaScript bridge.
    configuration.websiteDataStore=[TKBattleNetBrowser signInDataStore];
    _web=[[WKWebView alloc] initWithFrame:CGRectZero configuration:configuration];
    _web.navigationDelegate=self;
    _web.translatesAutoresizingMaskIntoConstraints=NO;
    [self.view addSubview:_web];
    [NSLayoutConstraint activateConstraints:@[
        [_web.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_web.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [_web.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_web.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]]];
    if (![@[@"us", @"eu", @"kr", @"tw"] containsObject:_region]) {
        WKLog("battle-login", @"browser refused: invalid selected region");
        [self cancel];
        return;
    }
    NSURL *url=[NSURL URLWithString:[NSString stringWithFormat:
        @"https://%@.battle.net/login/en/?externalChallenge=login&app=WoW", _region]];
    self.navigationItem.prompt=url.host;
    WKLog("battle-login", @"browser opened: official sign-in page");
    [_web loadRequest:[NSURLRequest requestWithURL:url]];
    __weak typeof(self) weakSelf=self;
    _deadline=[NSTimer scheduledTimerWithTimeInterval:600 repeats:NO block:^(__unused NSTimer *timer) {
        [weakSelf cancel];
    }];
}

- (void)finish:(BOOL)received {
    if (_finished) return;
    _finished=YES;
    [_deadline invalidate];
    _deadline=nil;
    _navigation=nil;
    _web.navigationDelegate=nil;
    [_web stopLoading];
    [_web removeFromSuperview];
    _web=nil;
    if (!received) [TKBattleNetSession clear];
    WKLog("battle-login", @"browser closed: %@", received?@"accepted result":@"no result");
    void (^completion)(BOOL)=self.completion;
    self.completion=nil;
    [self dismissViewControllerAnimated:YES completion:^{
        if (completion) completion(received);
    }];
}

- (void)cancel { [self finish:NO]; }

- (void)webView:(__unused WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)action
    decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    if (_finished) {
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }
    NSURL *url=action.request.URL;
    NSString *ticket=TKBattleNetCallbackTicket(url);
    if (ticket) {
        // A callback must originate in the main frame of an approved sign-in page.
        WKSecurityOrigin *origin=action.sourceFrame.securityOrigin;
        NSURLComponents *source=[NSURLComponents new];
        source.scheme=origin.protocol;
        source.host=origin.host;
        if (origin.port) source.port=@(origin.port);
        BOOL trusted=action.sourceFrame.mainFrame && action.targetFrame.mainFrame &&
                     TKBattleNetTrustedURL(source.URL);
        // A rejected navigation must never become an accepted failure callback.
        _trustedMainNavigation=NO;
        decisionHandler(WKNavigationActionPolicyCancel);
        if (trusted) [self finish:[TKBattleNetSession acceptTicket:ticket region:_region locale:_locale]];
        else WKLog("battle-login", @"callback refused: untrusted source");
        return;
    }
    // Federation leaves Blizzard's domains for the provider's own HTTPS page. This is allowed
    // only inside the acknowledged browser. The localhost result stays strict: only an official
    // Blizzard main frame may deliver the game ticket.
    if (action.targetFrame.mainFrame || !action.targetFrame) {
        BOOL blizzard=TKBattleNetTrustedURL(url);
        if (!blizzard && !TKBattleNetFederatedURL(url)) {
            WKLog("battle-login", @"navigation refused: untrusted top-level page");
            decisionHandler(WKNavigationActionPolicyCancel);
            return;
        }
        _trustedMainNavigation=blizzard;
        if (!action.targetFrame) {
            decisionHandler(WKNavigationActionPolicyCancel);
            [_web loadRequest:action.request];
            return;
        }
        self.navigationItem.prompt=url.host;
    }
    decisionHandler(WKNavigationActionPolicyAllow);
}

- (void)webView:(__unused WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
    _navigation=navigation;
}

- (BOOL)acceptMainFrameRedirect:(NSURL *)url navigation:(WKNavigation *)navigation {
    // WebKit can reject port zero before a navigation action is delivered. Only
    // accept a redirect/error for the current, approved main-frame navigation.
    if (_finished || !_trustedMainNavigation || !navigation || navigation!=_navigation) return NO;
    NSString *ticket=TKBattleNetCallbackTicket(url);
    if (!ticket) return NO;
    [self finish:[TKBattleNetSession acceptTicket:ticket region:_region locale:_locale]];
    return YES;
}

- (void)webView:(WKWebView *)webView didReceiveServerRedirectForProvisionalNavigation:(WKNavigation *)navigation {
    if ([self acceptMainFrameRedirect:webView.URL navigation:navigation]) [webView stopLoading];
}

- (void)webView:(__unused WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation
    withError:(NSError *)error {
    if (_finished || ([error.domain isEqual:NSURLErrorDomain] && error.code==NSURLErrorCancelled)) return;
    id failingURL=error.userInfo[NSURLErrorFailingURLErrorKey];
    if ([failingURL isKindOfClass:NSURL.class] &&
        [self acceptMainFrameRedirect:failingURL navigation:navigation]) return;
    // NSError descriptions can contain credential-bearing URLs; never show/log them.
    self.navigationItem.prompt=WKLocalized(@"login.failed");
}

- (void)dealloc { [_deadline invalidate]; }
@end
