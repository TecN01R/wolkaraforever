// Ask Core Animation for the 60 Hz the game is trying to hit, and record what it
// actually gives this display link.
//
// Why this exists. The renderer needs to request the 30/60 Hz priority Apple gives
// games, and the adapter needs to record the scheduling interval it receives. A
// display-link interval alone is not proof of the guest's present cadence; that is
// measured separately from CAMetalDrawable.presentedTime.
//
// Apple's rule for this case: "the system provides games with special priority to 30Hz
// and 60Hz refresh rates to ensure optimal performance. To access this special
// prioritization, your game needs to set a preferredFrameRateRange with a
// CAFrameRateRange structure using one or both of those values." (Optimizing iPhone
// and iPad apps to support ProMotion displays.) It also says the rate is not ours to
// force - "you can't force a ProMotion display to show your content at any specific
// rate" - so this is a request, and the log below is how we learn whether it was
// granted.
//
// Nothing in either tree claimed a frame rate before this: the only CADisplayLink was
// the performance HUD's, at 4-30 Hz preferred 10, which is a diagnostic overlay and not
// a claim on the panel.
//
// The measurement matters as much as the request. Once per second this logs the
// interval Core Animation schedules for this link and the interval of its callbacks.
// Compare it with the independent Metal present distribution; do not present either
// value as proof of the other.
//
// This is capture-only, not a production pacing mechanism.  The guest does not
// render from this callback, so a passive link cannot improve its frame time and
// must not add main-thread wakeups during ordinary play.  Opt in explicitly with
// --measure-display-rate when correlating this link with Metal presentation data.
//
// Personal branch: Battery Saver's 40 and 120 choices also install the link, because there
// it is the request. The app declares CADisableMinimumFrameDurationOnPhone, and a display
// link's preferred range is how an app asks iOS for a refresh rate. 40 asks for the panel's
// 40 Hz step and accepts 80 or 120, which 40 FPS also divides evenly; 120 asks for 120 Hz.
// While the AFK dim holds the game at 10 FPS the link is paused, so it stops asking. Each
// second the log then also carries the panel's refresh interval (the link's `duration`),
// how long presented frames stayed up (Presentation.m), and which presentation path the
// Battery Saver pacing took.

#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import "AKSupport.h"
#import "BatterySaverPolicy.h"

// Presentation.m, the same adapter image: presented-frame durations in refresh multiples
// (8, 12, 17, 21, 25, 33 ms, longer), and the Battery Saver pacing path counts.
extern void AKMetalTakePresentedGapBins(unsigned out[7]);
extern void AKMetalBatterySaverPacingCounts(uint64_t *immediate, uint64_t *extended,
                                            uint64_t *raised, uint64_t *kept, uint64_t *bypassed);

// The rate a game should ask for: both values Apple gives priority to, preferring 60.
#define AKDisplayRateMinimum 30.0
#define AKDisplayRateMaximum 60.0
#define AKDisplayRatePreferred 60.0

static CADisplayLink *s_link;
static double s_lastTimestamp;
static double s_intervalTotal;
static double s_intervalMin;
static double s_intervalMax;
static unsigned s_ticks;
static double s_nextReport;
static double s_deadlineTotal;      // targetTimestamp - timestamp, the asked-for interval
static double s_panelTotal;         // duration, the panel's refresh interval
static BOOL s_rateTest;             // installed for a Battery Saver 40 or 120 session

static void Report(void) {
    if (!s_ticks) {
        AKLog(@"display rate: no display link callbacks in the last second (the run loop is not being served)");
        return;
    }
    double mean = s_intervalTotal / s_ticks;
    double target = s_ticks ? s_deadlineTotal / s_ticks : 0.0;
    // Apple defines targetTimestamp - timestamp as the display link's actual frame
    // duration.  It is still a property of this link, not a CAMetalDrawable present.
    AKLog(@"display link rate: target %.2fms (%.1f Hz), callback mean %.2fms min %.2f max %.2f, callbacks=%u thermal=%d lowpower=%d",
          target * 1000.0, target > 0 ? 1.0 / target : 0.0,
          mean * 1000.0, s_intervalMin * 1000.0, s_intervalMax * 1000.0, s_ticks,
          (int)NSProcessInfo.processInfo.thermalState,
          (int)NSProcessInfo.processInfo.isLowPowerModeEnabled);
    if (s_rateTest) {
        double panel = s_panelTotal / s_ticks;
        unsigned gaps[7] = {0};
        AKMetalTakePresentedGapBins(gaps);
        uint64_t immediate = 0, extended = 0, raised = 0, kept = 0, bypassed = 0;
        AKMetalBatterySaverPacingCounts(&immediate, &extended, &raised, &kept, &bypassed);
        AKBatterySaverFramePolicy policy = AKBatterySaverResolvedPolicy(NO);
        AKLog(@"refresh test: panel %.2fms (%.0f Hz) cap=%.0f presented ms 8=%u 12=%u 17=%u 21=%u 25=%u 33=%u longer=%u pacing immediate=%llu extended=%llu raised=%llu kept=%llu bypassed=%llu",
              panel * 1000.0, panel > 0 ? 1.0 / panel : 0.0, policy.capped ? policy.framesPerSecond : 0.0,
              gaps[0], gaps[1], gaps[2], gaps[3], gaps[4], gaps[5], gaps[6],
              (unsigned long long)immediate, (unsigned long long)extended, (unsigned long long)raised,
              (unsigned long long)kept, (unsigned long long)bypassed);
    }
    s_intervalTotal = s_intervalMin = s_intervalMax = s_deadlineTotal = s_panelTotal = 0.0;
    s_ticks = 0;
}

static void Tick(CADisplayLink *link) {
    double now = link.timestamp;
    if (s_lastTimestamp > 0 && now > s_lastTimestamp) {
        double interval = now - s_lastTimestamp;
        s_intervalTotal += interval;
        if (s_intervalMin == 0 || interval < s_intervalMin) s_intervalMin = interval;
        if (interval > s_intervalMax) s_intervalMax = interval;
        s_deadlineTotal += link.targetTimestamp - link.timestamp;
        s_panelTotal += link.duration;
    }
    s_lastTimestamp = now;
    s_ticks++;
    if (now >= s_nextReport) {
        Report();
        s_nextReport = now + 1.0;
    }
}

@interface AKDisplayRateTarget : NSObject
- (void)tick:(CADisplayLink *)link;
@end

@implementation AKDisplayRateTarget
- (void)tick:(CADisplayLink *)link { Tick(link); }
@end

static AKDisplayRateTarget *s_target;

static void AKDisplayRateInstall(void) {
    if (s_link || !NSThread.isMainThread) return;
    AKBatterySaverFrameLimit limit = AKBatterySaverLaunchEnabled() ? AKBatterySaverLaunchFrameLimit()
                                                                   : AKBatterySaverFrameLimitOff;
    s_rateTest = limit == AKBatterySaverFrameLimit40 || limit == AKBatterySaverFrameLimit120;
    if (!s_rateTest && ![NSProcessInfo.processInfo.arguments containsObject:@"--measure-display-rate"]) return;
    s_target = [AKDisplayRateTarget new];
    s_link = [CADisplayLink displayLinkWithTarget:s_target selector:@selector(tick:)];
    if (!s_link) {
        AKLog(@"display rate: could not create a display link; the panel rate is unclaimed");
        return;
    }
    float minimum = AKDisplayRateMinimum, maximum = AKDisplayRateMaximum, preferred = AKDisplayRatePreferred;
    if (limit == AKBatterySaverFrameLimit40) { minimum = 40; maximum = 120; preferred = 40; }
    if (limit == AKBatterySaverFrameLimit120) { minimum = 80; maximum = 120; preferred = 120; }
    if (@available(iOS 15.0, *)) {
        s_link.preferredFrameRateRange = CAFrameRateRangeMake(minimum, maximum, preferred);
    } else {
        s_link.preferredFramesPerSecond = (NSInteger)preferred;
    }
    [s_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    AKLog(@"display rate: asked for %.0f-%.0f Hz, preferring %.0f (screen maximum %ld, 120 Hz opt-in %d)",
          minimum, maximum, preferred, (long)UIScreen.mainScreen.maximumFramesPerSecond,
          AKBatterySaverHighRefreshAllowed());
    if (s_rateTest) {
        // The AFK dim holds the game at 10 FPS; a link still asking for 40-120 Hz would keep
        // the panel fast for a screen nobody is looking at.
        [NSNotificationCenter.defaultCenter addObserverForName:AKBatterySaverDimDidChangeNotification
                                                        object:nil queue:NSOperationQueue.mainQueue
                                                    usingBlock:^(NSNotification *note) {
            BOOL dimmed = [note.userInfo[AKBatterySaverDimmedKey] boolValue];
            s_link.paused = dimmed;
            s_lastTimestamp = 0;
            AKLog(@"display rate: %@ while the AFK dim is %@", dimmed ? @"paused" : @"resumed", dimmed ? @"on" : @"off");
        }];
    }
}

// The adapter is loaded before the guest draws. A display link must be created on
// the main thread, so the constructor installs only when the explicit capture argument
// is present or the launch snapshot holds Battery Saver 40 or 120.
__attribute__((constructor)) static void AKDisplayRateLoad(void) {
    if (NSThread.isMainThread) AKDisplayRateInstall();
    else dispatch_async(dispatch_get_main_queue(), ^ { AKDisplayRateInstall(); });
}
