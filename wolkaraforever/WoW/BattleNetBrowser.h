#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
@interface TKBattleNetBrowser : UIViewController
+ (void)clearSavedSignInWithCompletion:(void (^)(void))completion;
// Fork: the opt-in to keep Battle.net's web session on this device between app launches.
+ (BOOL)canStaySignedIn;
+ (BOOL)staysSignedIn;
+ (void)setStaysSignedIn:(BOOL)stay completion:(nullable void (^)(void))completion;
- (instancetype)initWithRegion:(NSString *)region locale:(NSString *)locale;
@property(nonatomic, copy, nullable) void (^completion)(BOOL received);
@end
NS_ASSUME_NONNULL_END
