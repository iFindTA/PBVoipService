//
//  AppDelegate.m
//  PBVoipService
//
//  Created by nanhujiaju on 2017/9/8.
//  Copyright © 2017年 nanhujiaju. All rights reserved.
//

#import "AppDelegate.h"
#import <UIKit/UIKit.h>
#import "PBVoipService.h"
#import <PBKits/PBKits.h>
#import <PushKit/PushKit.h>
#import <Intents/Intents.h>
#import <IntentsUI/IntentsUI.h>
#import <UserNotifications/UNUserNotificationCenter.h>

@interface AppDelegate ()<PKPushRegistryDelegate>

@property (nonatomic, assign) UIBackgroundTaskIdentifier taskIdentifier;

@end

@implementation AppDelegate


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // Override point for customization after application launch.
    
    //本地通知：未接来电／未读
    NSDictionary *localNotification = [launchOptions objectForKey:UIApplicationLaunchOptionsLocalNotificationKey];
    if (localNotification) {
        //TODO:
        
    }
    
    //
    [self startSipServiceProcess];
    
    //for voip
    [self registerPushKitService];
    
    return YES;
}


- (void)applicationWillResignActive:(UIApplication *)application {
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
}


- (void)applicationDidEnterBackground:(UIApplication *)application {
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
}


- (void)applicationWillEnterForeground:(UIApplication *)application {
    // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
}


- (void)applicationDidBecomeActive:(UIApplication *)application {
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
}


- (void)applicationWillTerminate:(UIApplication *)application {
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}

#pragma mark --

- (void)startSipServiceProcess {
    //保证启动sip server 进程
    NSString *server = @"112.74.77.9";//开发
    //server = @"115.28.60.200";//demo
    //server = @"221.180.249.156";//辽宁
    u_int16_t port = 8443;
    //port = 2009;
    //init sip server
    NSString *acc = @"13023622337";
    NSString *pwd = @"123456";pwd = [pwd pb_SHA256];
    PBSipConfigure *config = [PBSipConfigure defaultConfiguration];
    config = [PBSipConfigure configureWithServerHost:server withPort:port withRingFile:@"call.caf"];
    NSLog(@"start sip service---");
    //__weak typeof(self) weakSelf = self;
    [[PBVoipService shared] startWithConfiguration:config withCompletion:^(NSError * _Nullable error) {
        if (error == nil) {
            NSLog(@"start sip server successful!");
            //[weakSelf authorAction:nil];
            [[PBVoipService shared] autherizeUsr:acc withPwd:pwd withCompletion:^(NSError * _Nullable error) {
                NSLog(@"register user with error:%@", error);
            }];
        } else {
            //TODO:restart while a some minutes
            NSLog(@"failed to start sip server with error:%@", error.localizedDescription);
        }
    }];
    //电话记录回调
    [[PBVoipService shared] registerVoipCallbackEventHandler:^(NSDictionary * _Nullable err) {
        
    }];
    //显示名字回调
    [[PBVoipService shared] registerVoipCallConvertDisplayEventHandler:^NSString * _Nullable(NSString * _Nonnull account) {
        return @"voip call";
    }];
    //来电通知 本地window需要失去焦点
    [[PBVoipService shared] registerVoipCallProfileShowEventHandler:^(BOOL show) {
        //[self.window resignFirstResponder];
    }];
}

#pragma mark -- push kit delegate

- (void)registerPushKitService {
    //for voip
    dispatch_queue_t queue = dispatch_queue_create("com.PB.microCall", DISPATCH_QUEUE_SERIAL);
    PKPushRegistry *pushRegistry = [[PKPushRegistry alloc] initWithQueue:queue];
    pushRegistry.delegate = self;
    pushRegistry.desiredPushTypes = [NSSet setWithObject:PKPushTypeVoIP];
    //*
    UIApplication *application = [UIApplication sharedApplication];
    UIUserNotificationSettings *settings = [UIUserNotificationSettings settingsForTypes:(UIUserNotificationTypeAlert |UIUserNotificationTypeSound | UIUserNotificationTypeBadge) categories:nil];
    //注册apnsnotification(local/remote) for ios10 settings(runtime loop)
    if ([UNUserNotificationCenter class] != nil) {
        //remote notification
        UNAuthorizationOptions options = UNAuthorizationOptionBadge|UNAuthorizationOptionAlert|UNAuthorizationOptionSound;
        [[UNUserNotificationCenter currentNotificationCenter] requestAuthorizationWithOptions:options completionHandler:^(BOOL granted, NSError * _Nullable error) {
            if (granted) {
                NSLog(@"usr did accept notifications");
                
                [application registerUserNotificationSettings:settings];
                [application registerForRemoteNotifications];
            }
        }];
    } else {
        [application registerUserNotificationSettings:settings];
        [application registerForRemoteNotifications];
    }
    //*/
}

- (void)pushRegistry:(PKPushRegistry *)registry didUpdatePushCredentials:(PKPushCredentials *)credentials forType:(PKPushType)type {
    
    if ([type isEqualToString:PKPushTypeVoIP]) {
        if (credentials.token.length == 0) {
            NSLog(@"failed to fetch voip push token!");
            return;
        }
        NSString *voipToken = [credentials.token description];
        NSLog(@"did fetch voip token :%@", voipToken);
    } else if ([type isEqualToString:PKPushTypeComplication]) {
        
    }
}

- (void)pushRegistry:(PKPushRegistry *)registry didInvalidatePushTokenForType:(PKPushType)type {
    if ([type isEqualToString:PKPushTypeVoIP]) {
        NSLog(@"did invalid voip push token!");
        //TODO: told the server that should not push notification to this device anymore!
    }
}

/**
 can excute by 10 secs or less
 */
- (void)pushRegistry:(PKPushRegistry *)registry didReceiveIncomingPushWithPayload:(PKPushPayload *)payload forType:(PKPushType)type {
    if ([payload.type isEqualToString:PKPushTypeVoIP]) {
        
        NSDictionary *map = [payload dictionaryPayload];
        NSLog(@"did received voip push :%@", map);
        if (![self whetherAllowedRemoteNotification]) {
            NSLog(@"用户关闭了推送权限，忽略此voip call");
            return;
        }
        
        if (map != nil) {
            NSDictionary *aps = [map objectForKey:@"aps"];
            if (aps) {
                NSDictionary * alert = [aps objectForKey:@"alert"];
                if (alert) {
                    NSString *body = [alert objectForKey:@"body"];
                    if (body) {
                        NSError *jsonErr = nil;
                        NSData *bodyData = [body dataUsingEncoding:NSUTF8StringEncoding];
                        NSDictionary *bodyMap = [NSJSONSerialization JSONObjectWithData:bodyData options:NSJSONReadingAllowFragments|NSJSONReadingMutableLeaves error:&jsonErr];
                        if (jsonErr == nil) {
                            unsigned int time_abs_delta = 8;
                            unsigned int background_excute_interval = 20;
                            NSString *cmd = [bodyMap objectForKey:@"status"];
                            NSString *handler = [bodyMap objectForKey:@"caller"];
                            
                            if ([cmd isEqualToString:@"new"]) {
                                UIApplicationState state = [[UIApplication sharedApplication] applicationState];
                                if (state == UIApplicationStateActive) {
                                    NSLog(@"应用在前台不响应voip推送");
                                    return;
                                }
                                //judge the timestamp for new call
                                NSNumber *timeNumber = [bodyMap objectForKey:@"timestamp"];
                                NSTimeInterval timestamp = [timeNumber doubleValue];
                                NSTimeInterval cur_stamp = [[NSDate date] timeIntervalSince1970];
                                unsigned int time_delta = fabs(timestamp-cur_stamp);
                                if (timestamp >= cur_stamp || time_delta > time_abs_delta) {
                                    NSLog(@"超过了时间戳，无效电话...");
                                    return;
                                }
                                //excute background task
                                UIApplication *application = [UIApplication sharedApplication];
                                self.taskIdentifier = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
                                    self.taskIdentifier = UIBackgroundTaskInvalid;
                                }];
                                [[PBVoipService shared] startSipServiceFromBackgroundModeWithCompletion:^(NSError * _Nullable error) {
                                    NSLog(@"后台重起用户服务结果:%@", error.localizedDescription);
                                }];
                                dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
                                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(background_excute_interval * NSEC_PER_SEC)), queue, ^{
                                    [application endBackgroundTask:self.taskIdentifier];
                                });
                            } else if ([cmd isEqualToString:@"canceled"] || [cmd isEqualToString:@"missed"]) {
                                //TODO:需要主动去除本地通知 或 系统CallKit UI
                                [[PBVoipService shared] cancelSystemProfileWithUsrAccount:handler withCompletion:^(NSError * _Nullable error) {
                                    NSLog(@"后台voip push 停止会话服务结果:%@", error.localizedDescription);
                                }];
                                [self generateUnAcceptCall4UID:handler];
                            }
                        } else {
                            NSLog(@"json failed :%@", jsonErr.localizedDescription);
                        }
                    }
                }
            }
        }
    }
}

- (BOOL)whetherAllowedRemoteNotification {
    UIUserNotificationSettings *settings = [[UIApplication sharedApplication] currentUserNotificationSettings];
    return settings.types ^ UIUserNotificationTypeNone;
}

/**
 根据账号生成未接来电
 */
- (void)generateUnAcceptCall4UID:(NSString *)uid {
    UIApplicationState state = [UIApplication sharedApplication].applicationState;
    if (state == UIApplicationStateActive) {
        return;
    }
    if (uid.length == 0) {
        return;
    }
    NSString *nick /*= [self convertAccount2Nick4UID:uid]*/;//TODO:替换显示名称
    NSString *body = PBFormat(@"来自%@的未接加密来电...",PBIsEmpty(nick)?uid:nick);
    //NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:uid, PB_SYSTEM_CALL_IDENTIFIER, @"unaccept", PB_SYSTEM_CALL_TYPE, [NSDate date], PB_SYSTEM_CALL_DATE, nil];
    UILocalNotification *notis = [[UILocalNotification alloc] init];
    notis.repeatInterval = 0;
    notis.alertBody = body;
    //notis.userInfo = info;
    //notis.soundName = UILocalNotificationDefaultSoundName;
    [[UIApplication sharedApplication] presentLocalNotificationNow:notis];
}

#pragma mark -- make call from system-contact

//*系统通讯录直接呼出
- (BOOL)application:(UIApplication *)application continueUserActivity:(NSUserActivity *)userActivity restorationHandler:(void(^)(NSArray *restorableObjects))restorationHandler {
    NSLog(@"userActivity:%@", userActivity.description);
    //应该在这里发起实际VoIP呼叫
    INInteraction *interaction = [userActivity interaction];
    INIntent *intent = interaction.intent;
    if ([intent isKindOfClass:[INStartAudioCallIntent class]]) {
        INStartAudioCallIntent *audioIntent = (INStartAudioCallIntent *)intent;
        INPerson *person = audioIntent.contacts.firstObject;
        NSString *phoneNum = person.personHandle.value;
        NSLog(@"phone num:%@", phoneNum);
        [[PBVoipService shared] startVoipCall2UserAccount:phoneNum withCompletion:^(NSError * _Nullable err) {
            
        }];
        return true;
    }
    
    return false;
}
//*/

//接收通过某种Activity调回来的操作：
- (void)application:(UIApplication *)application didUpdateUserActivity:(NSUserActivity *)userActivity{
    
}

@end
