//
//  AppDelegate.m
//  PeopleManager
//
//  Created by Scott Rasche on 9/24/15.
//  Copyright © 2015 vokal. All rights reserved.
//

#import "AppDelegate.h"
#import "HDBeaconManager.h"
#import "HDConstants.h"
#import "HDCloudKitManager.h"
#import "HDUtilities.h"
#include <assert.h>
#include <stdbool.h>
#include <sys/types.h>
#include <unistd.h>
#include <sys/sysctl.h>

@interface AppDelegate()

@property (nonatomic, strong) HDCloudKitManager *cloudManager;
@property (nonatomic, strong) UIView *appWideAlertView;

@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    [self redirectConsoleLogToDocumentFolder];
    UIUserNotificationSettings *notificationSettings = [UIUserNotificationSettings settingsForTypes:(UIUserNotificationTypeAlert | UIUserNotificationTypeBadge | UIUserNotificationTypeSound) categories:nil];
    [application registerUserNotificationSettings:notificationSettings];
    [application registerForRemoteNotifications];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(displayAppWideAlert:) name:NOTIFICATION_APP_WIDE_ALERT object:nil];
    self.cloudManager = [HDCloudKitManager sharedInstance];
    self.window.tintColor = [UIColor colorWithRed:249.0/255 green:243.0/255 blue:143.0/255 alpha:1.0];
    
    return YES;
}

- (void)redirectConsoleLogToDocumentFolder
{
    if ([self isDebuggerAttached]) {
        return;
    }
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                         NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSDateFormatter *dateFormat = [[NSDateFormatter alloc] init];
    [dateFormat setDateFormat:@"yyyy-MM-dd_HH-mm-ss"]; // 2009-02-01 19:50:41 PST
    NSDate *now = [NSDate date];
    NSString *logString = [NSString stringWithFormat:@"console_%@.log", [dateFormat stringFromDate:now]];
    
    NSString *logPath = [documentsDirectory stringByAppendingPathComponent:logString];
    freopen([logPath cStringUsingEncoding:NSASCIIStringEncoding], "a+",stderr);
}

- (BOOL)isDebuggerAttached
{
    // Returns true if the current process is being debugged (either
    // running under the debugger or has a debugger attached post facto).
    int junk;
    int mib[4];
    struct kinfo_proc info;
    size_t size;
    
    // Initialize the flags so that, if sysctl fails for some bizarre
    // reason, we get a predictable result.
    
    info.kp_proc.p_flag = 0;
    
    // Initialize mib, which tells sysctl the info we want, in this case
    // we're looking for information about a specific process ID.
    
    mib[0] = CTL_KERN;
    mib[1] = KERN_PROC;
    mib[2] = KERN_PROC_PID;
    mib[3] = getpid();
    
    // Call sysctl.
    
    size = sizeof(info);
    junk = sysctl(mib, sizeof(mib) / sizeof(*mib), &info, &size, NULL, 0);
    assert(junk == 0);
    
    // We're being debugged if the P_TRACED flag is set.
    
    return ( (info.kp_proc.p_flag & P_TRACED) != 0 );
}

#pragma mark - notifications

- (void)application:(UIApplication *)application didReceiveLocalNotification:(UILocalNotification *)notification
{
    NSLog(@"didReceiveLocalNotification = %@", notification);
}

- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo fetchCompletionHandler:(void (^)(UIBackgroundFetchResult result))completionHandler
{
    NSLog(@"Received remote notification : %@", userInfo);
    NSDictionary *ck = [userInfo objectForKey:@"ck"];
    NSDictionary *qry = ck[@"qry"];
    NSString *rid = qry[@"rid"];
    NSString *sid = qry[@"sid"];
    
    [self.cloudManager fetchRecordWithID:rid completionHandler:^(CKRecord *record, NSError *error) {
        
        if (record) {
            UIApplicationState state = application.applicationState;
            NSString *appState = nil;
            switch (state) {
                case UIApplicationStateActive:
                    appState = @"Active";
                    break;
                case UIApplicationStateBackground:
                    appState = @"Background";
                    break;
                case UIApplicationStateInactive:
                    appState = @"Inactive";
                    break;
                default:
                    break;
            }
            NSLog(@"Found cloud record updated while in AppState = %@", appState);
            // TODO: act on this - redraw screen
            if ([sid isEqualToString:SUBSCRIPTION_ADD_ACTIVITY]) {
                [HDUtilities showSystemWideAlertWithError:NO message:SUBSCRIPTION_ADD_ACTIVITY];
                [[NSNotificationCenter defaultCenter] postNotificationName:NOTIFICATION_ACTIVITY object:nil];
                
            } else if ([sid isEqualToString:SUBSCRIPTION_ADD_MESSAGE]) {
                [HDUtilities showSystemWideAlertWithError:NO message:SUBSCRIPTION_ADD_MESSAGE];
                
            } else if ([sid isEqualToString:SUBSCRIPTION_STATUS_UPDATE]) {
                [HDUtilities showSystemWideAlertWithError:NO message:SUBSCRIPTION_STATUS_UPDATE];
                [[NSNotificationCenter defaultCenter] postNotificationName:NOTIFICATION_SIGNED_IN object:nil];
            } else if ([sid isEqualToString:SUBSCRIPTION_ORDER]) {
                [HDUtilities showSystemWideAlertWithError:NO message:SUBSCRIPTION_ORDER];
                [[NSNotificationCenter defaultCenter] postNotificationName:NOTIFICATION_ORDER object:nil];
            } else {
                completionHandler(UIBackgroundFetchResultNoData);
            }
            completionHandler(UIBackgroundFetchResultNewData);
        } else {
            completionHandler(UIBackgroundFetchResultNoData);
        }
    }];
}

 - (void)testLocalNotification
{
    UILocalNotification *note1 = [[UILocalNotification alloc] init];
    note1.alertBody = [NSString stringWithFormat:@"This is a test"];
    note1.alertAction = @"Entered Test";
    note1.soundName = SOUND_ENTERED_REGION;
    note1.userInfo = [NSDictionary dictionaryWithObject:@"TEST" forKey:NOTIFICATION_IDENTIFIER_ENTER];
    [[UIApplication sharedApplication] presentLocalNotificationNow:note1];
    NSLog(@"Notification : %@", note1);
    note1.applicationIconBadgeNumber = 0;
}

#pragma mark - Utils

- (void)displayAppWideAlert:(NSNotification *)notification
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDictionary *userInfo = notification.userInfo;
        NSNumber *isError = userInfo[KEY_ERROR_APP_WIDE_ALERT];
        BOOL err = NO;
        if (isError!=nil) {
            err = isError.boolValue;
        }
        NSString *message = userInfo[KEY_MESSAGE_APP_WIDE_ALERT];
        
        if (!self.appWideAlertView) {
            self.appWideAlertView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, [HDUtilities currentScreenWidth], 64)];
            self.appWideAlertView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
            self.appWideAlertView.backgroundColor = [UIColor clearColor];
            UIView *transparentBackground = [[UIView alloc] initWithFrame:self.appWideAlertView.frame];
            transparentBackground.tag = 11;
            transparentBackground.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
            transparentBackground.alpha = 0.8;
            UILabel *label = [[UILabel alloc] initWithFrame:self.appWideAlertView.frame];
            label.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
            label.textColor = [UIColor whiteColor];
            label.numberOfLines = 0;
            label.textAlignment = NSTextAlignmentCenter;
            label.minimumScaleFactor = 0.5;
            label.adjustsFontSizeToFitWidth = YES;
            label.tag = 12;
            [self.appWideAlertView addSubview:transparentBackground];
            [self.appWideAlertView addSubview:label];
            self.appWideAlertView.userInteractionEnabled = NO;
        } else {
            self.appWideAlertView.frame = CGRectMake(0, 0, [HDUtilities currentScreenWidth], 64); // in case we've rotated and screen size is different
        }
        UIView *transBack = (UIView *)[self.appWideAlertView viewWithTag:11];
        if (err) {
            transBack.backgroundColor = [UIColor redColor];
        } else {
            transBack.backgroundColor = self.window.tintColor;//[UIColor colorWithRed:0.0 green:0.0 blue:240.0/255.0 alpha:1.0];
        }
        UILabel *messageLabel = (UILabel *)[self.appWideAlertView viewWithTag:12];
        if (message) {
            if (self.appWideAlertView.window) {
                messageLabel.text = [messageLabel.text stringByAppendingFormat:@"\n%@", message];
            } else {
                messageLabel.text = message;
            }
        } else {
            messageLabel.text = @"message is nil";
        }
        self.appWideAlertView.alpha = 0.0;
        [self.window addSubview:self.appWideAlertView];
        [UIView animateWithDuration:1.0
                         animations:^{
                             self.appWideAlertView.alpha = 1.0;
                         } completion:^(BOOL finished) {
                             [self performSelector:@selector(dismissAppWideAlert) withObject:nil afterDelay:10.0];
                         }];
    });
}

- (void)dismissAppWideAlert
{
    [UIView animateWithDuration:1.0
                     animations:^{
                         self.appWideAlertView.alpha = 0.0;
                     } completion:^(BOOL finished) {
                         [self.appWideAlertView removeFromSuperview];
                         self.appWideAlertView = nil;
                     }];
}

@end
