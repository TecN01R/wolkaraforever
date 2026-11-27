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
// Personal branch. The app declares CADisableMinimumFrameDurationOnPhone, so iOS may show it
// at up to 120 Hz, and two things here follow from that:
//   - The link is the request for 120 Hz, with Battery Saver's frame limit Off (the game's own
//     Max Foreground FPS is then the limit) and with its 40 (every third refresh at 120 Hz).
//     It asks for exactly 120: on an iPhone Duo a request for 40-120 Hz, preferring 40, was
//     given 60 Hz after a few seconds, where 40 FPS cannot fit and the pacing fell to 30.
//     Automatic, 30 and 60 ask for nothing. While the AFK dim holds the game at 10 FPS the
//     link is paused, so it stops asking.
//   - Every session logs, once a second, how long presented frames stayed on screen
//     (Presentation.m), which Battery Saver pacing path ran, and the panel's refresh
//     interval while the link runs.
// Both run on a thread of their own. On the main thread the link's callbacks came about every
// 74 ms, because the game keeps that thread busy; whether iOS weighs a late link less is not
// documented, and a thread of its own takes the question away.

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
static double s_panelSum;           // link.duration since the last refresh-test line
static unsigned s_panelCount;
static NSTimer *s_refreshTimer;
static NSThread *s_rateThread;
static long s_screenMaximum;        // read on the main thread at install

// One line a second while frames are being presented; nothing while none are (background,
// a paused game), so an idle session does not fill the log.
static void RefreshReport(void) {
    unsigned gaps[7] = {0};
    AKMetalTakePresentedGapBins(gaps);
    unsigned frames = 0;
    for (int index = 0; index < 7; index++) frames += gaps[index];
    double panel = s_panelCount ? s_panelSum / s_panelCount : 0.0;
    s_panelSum = 0.0;
    s_panelCount = 0;
    if (!frames) return;
    uint64_t immediate = 0, extended = 0, raised = 0, kept = 0, bypassed = 0;
    AKMetalBatterySaverPacingCounts(&immediate, &extended, &raised, &kept, &bypassed);
    // The launch choice rather than the resolved cap: resolving reads UIDevice's battery
    // state, which belongs to the main thread. Low Power Mode is on the line itself.
    AKLog(@"refresh test: frames=%u ms 8=%u 12=%u 17=%u 21=%u 25=%u 33=%u longer=%u limit=%@ panel=%.2fms pacing immediate=%llu extended=%llu raised=%llu kept=%llu bypassed=%llu thermal=%d lowpower=%d",
          frames, gaps[0], gaps[1], gaps[2], gaps[3], gaps[4], gaps[5], gaps[6],
          AKBatterySaverLaunchEnabled() ? AKBatterySaverFrameLimitStoredName(AKBatterySaverLaunchFrameLimit()) : @"off",
          panel * 1000.0,
          (unsigned long long)immediate, (unsigned long long)extended, (unsigned long long)raised,
          (unsigned long long)kept, (unsigned long long)bypassed,
          (int)NSProcessInfo.processInfo.thermalState, (int)NSProcessInfo.processInfo.isLowPowerModeEnabled);
}

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
    s_intervalTotal = s_intervalMin = s_intervalMax = s_deadlineTotal = 0.0;
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
        s_panelSum += link.duration;
        s_panelCount++;
    }
    s_lastTimestamp = now;
    s_ticks++;
    if (now >= s_nextReport) {
        Report();
        s_nextReport = now + 1.0;
    }
}

@interface AKDisplayRateTarget : NSObject
@property (nonatomic) BOOL wantsLink;
@property (nonatomic) float minimum, maximum, preferred;
- (void)tick:(CADisplayLink *)link;
@end

@implementation AKDisplayRateTarget
- (void)tick:(CADisplayLink *)link { Tick(link); }
- (void)report:(NSTimer *)timer { (void)timer; RefreshReport(); }
- (void)setLinkPaused:(NSNumber *)paused {
    s_link.paused = paused.boolValue;
    s_lastTimestamp = 0;
    AKLog(@"display rate: %@ while the AFK dim is %@", paused.boolValue ? @"paused" : @"resumed",
          paused.boolValue ? @"on" : @"off");
}
// The link and the log timer live on this thread's run loop for the rest of the session.
- (void)run:(id)unused {
    (void)unused;
    NSRunLoop *loop = NSRunLoop.currentRunLoop;
    if (self.wantsLink) {
        s_link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
        if (!s_link) {
            AKLog(@"display rate: could not create a display link; the panel rate is unclaimed");
        } else {
            if (@available(iOS 15.0, *)) {
                s_link.preferredFrameRateRange = CAFrameRateRangeMake(self.minimum, self.maximum, self.preferred);
            } else {
                s_link.preferredFramesPerSecond = (NSInteger)self.preferred;
            }
            [s_link addToRunLoop:loop forMode:NSRunLoopCommonModes];
            AKLog(@"display rate: asked for %.0f-%.0f Hz, preferring %.0f (screen maximum %ld), on its own thread",
                  self.minimum, self.maximum, self.preferred, s_screenMaximum);
        }
    }
    if (s_refreshTimer) [loop addTimer:s_refreshTimer forMode:NSRunLoopCommonModes];
    // A run loop with nothing to wait on returns at once; the port keeps this one waiting.
    [loop addPort:NSMachPort.port forMode:NSDefaultRunLoopMode];
    for (;;) {
        @autoreleasepool { [loop runMode:NSDefaultRunLoopMode beforeDate:NSDate.distantFuture]; }
    }
}
@end

static AKDisplayRateTarget *s_target;

static void AKDisplayRateInstall(void) {
    if (s_target || !NSThread.isMainThread) return;
    BOOL highRefresh = AKBatterySaverHighRefreshAllowed();
    BOOL measure = [NSProcessInfo.processInfo.arguments containsObject:@"--measure-display-rate"];
    if (!highRefresh && !measure) return;
    AKBatterySaverFrameLimit limit = AKBatterySaverLaunchEnabled() ? AKBatterySaverLaunchFrameLimit()
                                                                   : AKBatterySaverFrameLimitOff;
    // 120 Hz is asked for wherever Battery Saver sets no cap below it that 60 Hz serves as well.
    BOOL ask120 = highRefresh && (limit == AKBatterySaverFrameLimitOff || limit == AKBatterySaverFrameLimit40);
    s_screenMaximum = (long)UIScreen.mainScreen.maximumFramesPerSecond;
    s_target = [AKDisplayRateTarget new];
    s_target.wantsLink = ask120 || measure;
    s_target.minimum = ask120 ? 120 : AKDisplayRateMinimum;
    s_target.maximum = ask120 ? 120 : AKDisplayRateMaximum;
    s_target.preferred = ask120 ? 120 : AKDisplayRatePreferred;
    if (highRefresh) {
        s_refreshTimer = [NSTimer timerWithTimeInterval:1.0 target:s_target selector:@selector(report:)
                                               userInfo:nil repeats:YES];
        AKLog(@"refresh test: 120 Hz opt-in present; frame limit %@ (Battery Saver Mode %@); asking for 120 Hz %d; screen maximum %ld",
              AKBatterySaverFrameLimitStoredName(AKBatterySaverLaunchFrameLimit()),
              AKBatterySaverLaunchEnabled() ? @"on" : @"off", ask120, s_screenMaximum);
    }
    s_rateThread = [[NSThread alloc] initWithTarget:s_target selector:@selector(run:) object:nil];
    s_rateThread.name = @"WolkaraForever display rate";
    s_rateThread.qualityOfService = NSQualityOfServiceUserInteractive;
    [s_rateThread start];
    if (s_target.wantsLink) {
        // The AFK dim holds the game at 10 FPS; a link still asking for 120 Hz would keep the
        // panel fast for a screen nobody is looking at.
        [NSNotificationCenter.defaultCenter addObserverForName:AKBatterySaverDimDidChangeNotification
                                                        object:nil queue:NSOperationQueue.mainQueue
                                                    usingBlock:^(NSNotification *note) {
            BOOL dimmed = [note.userInfo[AKBatterySaverDimmedKey] boolValue];
            [s_target performSelector:@selector(setLinkPaused:) onThread:s_rateThread
                           withObject:@(dimmed) waitUntilDone:NO];
        }];
    }
}

// The adapter is loaded before the guest draws. Install reads UIScreen and the launch
// snapshot on the main thread, then starts the thread that owns the link and the log; it
// does nothing without the 120 Hz opt-in or the explicit capture argument.
__attribute__((constructor)) static void AKDisplayRateLoad(void) {
    if (NSThread.isMainThread) AKDisplayRateInstall();
    else dispatch_async(dispatch_get_main_queue(), ^ { AKDisplayRateInstall(); });
}
