//
//  FLKSipService.m
//  PJSip2.5.5Pro
//
//  Created by nanhujiaju on 2017/1/3.
//  Copyright © 2017年 nanhu. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <PBKits/PBKits.h>
#import "FLKSipService.h"
#import <pjsua-lib/pjsua_internal.h>
#import <pjmedia/wav_port.h>
#import "FLKSipConstants.h"
#import "FLKVoipCallProfile.h"
#import "FLKVoipCallProfileDelegate.h"
#import "FLKCallManager.h"
#import "FLKProviderDelegate.h"
#import <CoreTelephony/CTCall.h>
#import <CoreTelephony/CTCallCenter.h>
#import <UserNotifications/UserNotifications.h>
#import <notify.h>
#import "AFNetworkReachabilityManager.h"

#pragma mark == application lock screen notification

#define FLKSCREEN_LOCK                          CFSTR("com.apple.springboard.lockcomplete")
#define FLKSCREEN_CAHNGE                        CFSTR("com.apple.springboard.lockstate")
#define NotificationPwdUI                       CFSTR("com.apple.springboard.hasBlankedScreen")

/**
 程序在前台是可以拿到的，在后台情况下就无法检测
 */
static void screenLockStateChanged(CFNotificationCenterRef center,void* observer,CFStringRef name,const void* object,CFDictionaryRef userInfo);

#pragma mark == extern vars defines

NSString * const FLK_VOIPCALL_DID_RECEIVED_INCOMING_PUSH                =   @"com.flk.microchat-voip.call.push";

#pragma mark == helper util methods ==

static NSString * getUsrAgent() {
    return [NSString stringWithFormat:@"%@-%@-%@",
            [[UIDevice currentDevice] model],
            [[UIDevice currentDevice] systemVersion],
            [[UIDevice currentDevice] name]
            ];
}

/**
 在非初始化pjsip的线程上调用pjsip库方法，需要对该线程进行附加
 */
static void pjsip_check_thread() {
    pj_thread_desc threadDesc;
    pj_thread_t *aThread = 0;
    if (!pj_thread_is_registered()) {
        if (pj_thread_register(PJ_SIP_THREAD.UTF8String, threadDesc, &aThread) == PJ_SUCCESS) {
            NSLog(@"register thread successfully!");
        } else {
            NSLog(@"register thread failed!");
        }
    }
}

/**
 在非初始化pjsip的线程上调用pjsip库方法，需要对该线程进行附加
 
 @param block 代执行block
 */
//static void pjsip_excute_in_block(void(^block)(void)) {
//    pj_thread_desc threadDesc;
//    pj_thread_t *aThread = 0;
//    if (!pj_thread_is_registered()) {
//        if (pj_thread_register(PJ_SIP_THREAD.UTF8String, threadDesc, &aThread) == PJ_SUCCESS) {
//            block();
//        }
//    } else {
//        block();
//    }
//}

#pragma mark -- pjsua callback declares
static void on_pager(pjsua_call_id call_id, const pj_str_t *from,
                     const pj_str_t *to, const pj_str_t *contact,
                     const pj_str_t *mime_type, const pj_str_t *body);
static void on_reg_state(pjsua_acc_id acc_id);
static void on_call_media_state(pjsua_call_id call_id);
static void on_call_state(pjsua_call_id call_id, pjsip_event *e);
static void on_incoming_call(pjsua_acc_id acc_id, pjsua_call_id call_id, pjsip_rx_data *rdata);
static pjsip_redirect_op on_call_redirected(pjsua_call_id call_id, const pjsip_uri *target, const pjsip_event *e);

#pragma mark =======================================================================================

@interface FLKSipConfigure ()

@property (nonatomic, copy, readwrite) NSString * host;
@property (nonatomic, assign, readwrite) uint64_t port;
@property (nonatomic, copy, readwrite) NSString * ringFile;

/**
 当前登录用户账户/密码
 */
@property (nonatomic, copy, readwrite) NSString * localUsrAcc;
@property (nonatomic, copy, readwrite) NSString * localUsrPwd;

@end

@implementation FLKSipConfigure

+ (FLKSipConfigure *)defaultConfiguration {
    return [FLKSipConfigure configureWithServerHost:PJ_SIP_SERVER_HOST withPort:PJ_SIP_SERVER_PORT withRingFile:[NSString stringWithFormat:@"%@.%@", PJ_SIP_RING_FILE, PJ_SIP_RING_FILE_EXT]];
}

+ (FLKSipConfigure *)configureWithServerHost:(NSString *)host withPort:(uint64_t)port withRingFile:(NSString * _Nullable)ringFile {
    FLKSipConfigure * config = [[FLKSipConfigure alloc] init];
    config.host = host.copy;
    config.port = port;
    if (ringFile.length == 0) {
        config.ringFile = [NSString stringWithFormat:@"%@.%@", PJ_SIP_RING_FILE, PJ_SIP_RING_FILE_EXT];
    } else {
        config.ringFile = ringFile.copy;
    }
    return config;
}

@end

#pragma mark ===========================================================================



@interface FLKSipService () <FLKVoipCallProfileDelegate, FLKSystemProviderDelegate> {
    pjsua_app_config_t                              _app_cfg;
}

/**
 observe system call
 */
@property (nonatomic, strong) CTCallCenter *callCenter;

/**
 async operation queue
 */
@property (nonatomic, strong) dispatch_queue_t sipServiceQueue;

/**
 sip resources bundle
 */
@property (nonatomic, strong) NSBundle *sipBundle;

/**
 the call id
 */
@property (nonatomic, assign, readwrite) pjsua_call_id callID;

@property (nonatomic, assign, readwrite) pjsua_acc_id accID;

@property (nonatomic, assign, readwrite) pjsip_inv_state callState;

#pragma mark -- voip callback handler

@property (nonatomic, copy, nullable) FLKVoipCallbackBlock voipCallBackBlock;
@property (nonatomic, copy, nullable) FLKVoipConvertDisplayBlock voipCallConvertBlock;
@property (nonatomic, copy, nullable) FLKVoipCallProfileBlock voipCallProfileBlock;
@property (nonatomic, copy, nullable) FLKVoipServiceRestartBlock voipServiceRestartBlock;

/**
 the app configure
 */
//@property (nonatomic, assign, readwrite) pjsua_app_config_t app_cfg;

@property (nonatomic, strong) FLKSipConfigure *serverConfiguration;

#pragma mark -- audio player
@property (nonatomic, strong) AVAudioPlayer *audioPlayer;

#pragma mark -- voip call custom profile
@property (nonatomic, strong, nullable) FLKVoipCallProfile *voipProfile;
@property (nonatomic, strong, nullable) FLKProviderDelegate *systemDelegate;

/**
 标示当前电话 是否由系统接起来
 */
@property (nonatomic, assign) BOOL whetherCallConfirmedBySystem;
//系统提醒来电开始时间 用来生成未接来电时的标示
@property (nonatomic, strong, nullable) NSDate *systemCallFiredDate;

@property (nonatomic, assign) BOOL whetherHangupByMySelf;

#pragma mark -- background mode
@property (nonatomic, assign) UIBackgroundTaskIdentifier taskIdentifier;
//当前通话 对方账号
//@property (nonatomic, copy, nullable) NSString *currentHandle;

#pragma mark -- network state --
//当在通话中时网络切换时不能马上断开 在通话结束时再切换网络
@property (nonatomic, assign) BOOL                  whetherShouldReStartServer;

@end

static FLKSipService *instance = nil;
static CGFloat const FLK_BACKGROUND_MODE_EXCUTE_INTERVAL                        =   6.f;

@implementation FLKSipService

+ (FLKSipService *)shared {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[FLKSipService alloc] init];
    });
    
    return instance;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (id)init {
    self = [super init];
    if (self) {
        [[NSNotificationCenter defaultCenter] removeObserver:self];
        //self.previousState = RealStatusUnknown;
        //self.pjsuaRetryMaxCounts = 5;
        //TODO: realtime to check network state
        // realtime to check application state
        //[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sipApplicationWillResignActiveMode) name:UIApplicationWillResignActiveNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sipApplicationDidEnterBackgroundMode) name:UIApplicationDidEnterBackgroundNotification object:nil];
        //此处暂不需要监听 因为从后台激活时 可能本服务已经被杀掉或者释放 直接从appDelegate激活本服务即可
        //TODO:也可以监听此方法 从后台进入前台时 如果在振铃则需要弹出被叫界面
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sipApplicationWillEnterForegroundMode) name:UIApplicationWillEnterForegroundNotification object:nil];
        //[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sipApplicationDidBecomeActiveForegroundMode) name:UIApplicationDidBecomeActiveNotification object:nil];
        //此处通知为下下策
        //[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sipApplicationDidReceivedVoipPushInfo:) name:FLK_VOIPCALL_DID_RECEIVED_INCOMING_PUSH object:nil];
        //screen lock notification
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, screenLockStateChanged, FLKSCREEN_LOCK, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, screenLockStateChanged, FLKSCREEN_CAHNGE, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        
        [[AFNetworkReachabilityManager sharedManager] startMonitoring];
        weakify(self)
        [[AFNetworkReachabilityManager sharedManager] setReachabilityStatusChangeBlock:^(AFNetworkReachabilityStatus status) {
            strongify(self)
            [self networkStateChanged];
        }];
        AFNetworkReachabilityStatus status = [[AFNetworkReachabilityManager sharedManager] networkReachabilityStatus];
        NSLog(@"init engine network state:%zd",status);
        sleep(0.25);
        
        //system call event
        //[self __observeSystemCallEvent];
        //*
        if ([self whetherSystemOperationAbove10]) {
            [self.systemDelegate description];
        } else {
            [self __observeSystemCallEvent];
        }
        //*/
        
        //seup default value
        _accID = PJSUA_INVALID_ID;
        _callID = PJSUA_INVALID_ID;
        _callState = PJSIP_INV_STATE_NULL;
        _app_cfg.record_id = PJSUA_INVALID_ID;
        
        //test for record audio file
        NSString *audioFile = [self localPath4File:@"voip.wav"];
        if (audioFile) {
            NSData *audioData = [NSData dataWithContentsOfURL:[NSURL fileURLWithPath:audioFile]];
            NSLog(@"上次通话录音文件大小:%.2f KB", audioData.length/1024.f);
        }
    }
    return self;
}

#pragma mark -- System Call notificatons --

- (void)__observeSystemCallEvent {
    weakify(self)
    self.callCenter = [[CTCallCenter alloc] init];
    self.callCenter.callEventHandler = ^(CTCall *call){
        if([call.callState isEqualToString:CTCallStateDisconnected]) {
            NSLog(@"Call has been disconnected");
        } else if ([call.callState isEqualToString:CTCallStateConnected]) {
            NSLog(@"Callhasjustbeen connected");
        } else if([call.callState isEqualToString:CTCallStateIncoming]) {
            NSLog(@"System Call is incoming==============%@", call.callID);
            strongify(self)
            [self didObservedSystemIncomingCall4UUIDString:call.callID];
        } else if([call.callState isEqualToString:CTCallStateDialing]) {
            NSLog(@"Call is Dialing");
        } else {
            NSLog(@"Nothing is done");
        }
    };
}

#pragma mark -- application notifications --

- (void)sipApplicationWillResignActiveMode {
    NSLog(@"%s",__FUNCTION__);
}

- (void)sipApplicationDidEnterBackgroundMode {
    NSLog(@"will disconnect sip service when did enter background!");
    if (_callState != PJSIP_INV_STATE_CONFIRMED) {
        [self stopSipServiceAndResignUserInBackground];
    }
}

#pragma mark ===== Excute Event In Unique-queue =====

/**
 ensure excute block event in unique-queue of sip
 */
- (void)excuteBlockEvent:(NSError * _Nullable(^)())block withCompletion:(void (^ _Nullable)(NSError * _Nullable error))completion {
    dispatch_async(self.sipServiceQueue, ^{
        NSError *err = block();
        if (completion) {
            completion(err);
        }
    });
}

/**
 进入后台时清除服务 注销用户
 */
- (void)stopSipServiceAndResignUserInBackground {
    UIApplication *application = [UIApplication sharedApplication];
    self.taskIdentifier = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
        self.taskIdentifier = UIBackgroundTaskInvalid;
    }];
    
    //do something
    NSError * _Nullable(^excuteBlock)() = ^(){
        NSError *err;
        [self stop];
        return err;
    };
    [self excuteBlockEvent:excuteBlock withCompletion:nil];
    
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    queue = self.sipServiceQueue;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(FLK_BACKGROUND_MODE_EXCUTE_INTERVAL * NSEC_PER_SEC)), queue, ^{
        [application endBackgroundTask:self.taskIdentifier];
    });
}

- (void)sipApplicationWillEnterForegroundMode {
    NSLog(@"%s",__FUNCTION__);
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(stopSipServiceAndResignUserInBackground) object:nil];
    [[UIApplication sharedApplication] endBackgroundTask:self.taskIdentifier];
    //reset audio category
    [self resetAudioSessionPreCall];
    
    //cause of when sip service actived below iOS10, such as iOS8+/iOS9+.
    if (![self whetherSystemOperationAbove10] && [self serviceAvaliable]) {
        //reset pre-setting enable for snd_device
        [self setPJSuaAudioDeviceEnable:true];
    }
    
    if (_callID != PJSUA_INVALID_ID) {
        
        NSString *remoteEndia = [self remoteEndiaAccount];
        if (self.whetherCallConfirmedBySystem && [self whetherSystemOperationAbove10]) {
            //系统来电 并且已接通
            NSLog(@"系统已接");
            if (self.voipProfile == nil) {
                NSLog(@"创建profile");
                PBMAINDelay(PBANIMATE_DURATION, ^{
                    [self showCustomProfile4LaunchType:FLKCallLaunchTypeTalking withUsrAccount:remoteEndia];
                });
            }
        } else {
            NSLog(@"取消本地通知");
            //取消本地通知
            //[self cancelSystemVoipCallLocalNotification];
            //10以下系统 此时状态在振铃
            FLKCallLaunchType type = FLKCallLaunchTypeCalled;
            if (_callState == PJSIP_INV_STATE_CONFIRMED) {
                type = FLKCallLaunchTypeTalking;
                //[self stopRingWithSpeaker];
            } else if (_callState == PJSIP_INV_STATE_EARLY) {
                [self startRingWithSpeaker];
            }
            if (self.voipProfile == nil) {
                NSLog(@"create profile");
                PBMAINDelay(PBANIMATE_DURATION, ^{
                    [self showCustomProfile4LaunchType:type withUsrAccount:remoteEndia];
                });
            }
        }
    }
}
//此处暂不需要监听 因为从后台激活时 可能本服务已经被杀掉或者释放 直接从appDelegate激活本服务即可
- (void)sipApplicationDidBecomeActiveForegroundMode {
    NSLog(@"%s",__FUNCTION__);
}

- (void)sipApplicationDidReceivedVoipPushInfo:(NSNotification *)notification {
    NSLog(@"sip server did received a voip push:%@", notification);
}

#pragma mark -- getters --

- (dispatch_queue_t)sipServiceQueue {
    if (!_sipServiceQueue) {
        _sipServiceQueue = dispatch_queue_create("com.flk.sip-service.io", NULL);
    }
    return _sipServiceQueue;
}

- (NSBundle *)sipBundle {
    if (!_sipBundle) {
        //setting bundle
        _sipBundle = [NSBundle bundleWithURL:[[NSBundle mainBundle] URLForResource:@"sipService" withExtension:@"bundle"]];
    }
    return _sipBundle;
}

/**
 file path in Documents
 */
- (NSString *)localPath4File:(NSString *)file {
    NSArray *homeDirs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, true);
    NSString *documents = [homeDirs firstObject];
    return [documents stringByAppendingPathComponent:file];
}

/**
 sip audio file path
 */
- (NSString *)localAudioPath4File:(NSString *)file {
    NSString * fileExtPath = [NSString stringWithFormat:@"audio/%@",file];
    return [[self.sipBundle resourcePath] stringByAppendingPathComponent:fileExtPath];
}

#pragma mark -- Unit Test --

- (NSString * _Nullable)unitTest2FetchRemoteEndianAccount4Sip:(NSString *)sip {
    return @"10086";
}

- (NSString * _Nullable)unitTest2FetchSipBunbleResource {
    return [self localAudioPath4File:@"ring26.caf"];
}

#pragma mark -- Network state change --

- (void)networkStateChanged {
    NSLog(@"sip server networkStateChanged!");
    UIApplicationState state = [self applicationState];
    NSLog(@"UIApplicationState:%zd", state);
    if (state == UIApplicationStateBackground) {
        //在后台则不做任何操作
        return;
    }
    AFNetworkReachabilityStatus status = [[AFNetworkReachabilityManager sharedManager] networkReachabilityStatus];
    if (status == AFNetworkReachabilityStatusNotReachable) {
        if (_callID != PJSUA_INVALID_ID || _voipProfile != nil) {
            //在前台无网 若目前正在通话中则主动挂断
            [self didTouchHangUpWithProfile:nil];
        }
        //在前台 且此时无网也无通话 则返回
        return;
    }
    pjsip_check_thread();
    pjsua_state sip_state = pjsua_get_state();
    if (sip_state != PJSUA_STATE_NULL && sip_state != PJSUA_STATE_CLOSING) {
        //1如果不在运行中、启动中则返回（有可能没启动、正在关闭）
        return;
    }
    
    //正在通话中 重新注册用户状态 刷新NAT网络地址
    if (_callID != PJSUA_INVALID_ID || _voipProfile != nil) {
        [self reRegisterUserStateWithCompletion:nil];
        return;
    }
    
    //用户是否允许自动重联
    BOOL should_restart = true;
    if (self.voipServiceRestartBlock) {
        should_restart = self.voipServiceRestartBlock();
    }
    if (should_restart) {
        //当前网络类型发生了变化 如果此时没有正在通话则注销再次登录 否则不做改动
        [self restartSipServerWithCompletion:^(NSError * _Nullable error) {
            
        }];
    }
}

- (BOOL)networkStateAvaliable {
    return [AFNetworkReachabilityManager sharedManager].isReachable;
}

#pragma mark -- re-register user on sip server

- (void)reRegisterUserStateWithCompletion:(void (^_Nullable)(NSError * _Nullable error))completion {
    weakify(self)
    NSError * _Nullable(^excuteBlock)() = ^(){
        /* first is to check current sip service state */
        NSError *err;
        strongify(self)
        if (self.accID != PJSUA_INVALID_ID) {
            pj_status_t status = pjsua_acc_set_registration(self.accID, PJ_TRUE);
            if (status != PJ_SUCCESS) {
                err = [NSError errorWithDomain:@"failed to re-register user sip state!" code:-1 userInfo:nil];
            }
        }
        
        return err;
    };
    [self excuteBlockEvent:excuteBlock withCompletion:completion];
}

#pragma mark -- re-start engine while network changed

- (void)restartSipServerWithCompletion:(void (^ _Nullable)(NSError * _Nullable error))completion {
    NSLog(@"restarting sip service---------------");
    
    /**
     如果无法保证服务正常 则有以下处理:
     1，上报服务器错误
     2，生成未接来电
     */
    /*
    NSError * _Nullable(^excuteBlock)() = ^(){
        __block NSError *err;
        if (self.serverConfiguration.localUsrAcc.length == 0 || self.serverConfiguration.host.length == 0) {
            _serverConfiguration = nil;
            NSDictionary *cfgMap = [self fetchLocalConfiguration];
            if (cfgMap == nil) {
                err = [NSError errorWithDomain:@"failed to auto sign in with empty params!" code:-1 userInfo:nil];
                return err;//直接失败
            }
            self.serverConfiguration = [self convertMap2SipConfigure:cfgMap];
        }
     
        //这时能确定sip service 不正常（有可能是链接 也有可能是用户未认证）
        
        __weak typeof(FLKSipService *)weakSelf = self;
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
     //此处不可以加信号量 会锁住线程
        [self startWithConfiguration:self.serverConfiguration withCompletion:^(NSError * _Nullable error) {
            if (error != nil) {
                err = error;
                dispatch_semaphore_signal(sem);
            } else {
                [weakSelf autherizeUsr:self.serverConfiguration.localUsrAcc withPwd:self.serverConfiguration.localUsrPwd withCompletion:^(NSError * _Nullable error) {
                    err = error;
                    dispatch_semaphore_signal(sem);
                }];
            }
        }];
        dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
        
        return err;
    };
    
    [self excuteBlockEvent:excuteBlock withCompletion:completion];
    //*/
    /*
     
     dispatch_semaphore_t sem = dispatch_semaphore_create(0);
     dispatch_async(self.sipServiceQueue, ^{
     [self stop];
     dispatch_semaphore_signal(sem);
     });
     dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
     
    __block NSError * blockError;
    if (self.serverConfiguration.localUsrAcc.length == 0 || self.serverConfiguration.host.length == 0) {
        _serverConfiguration = nil;
        NSDictionary *cfgMap = [self fetchLocalConfiguration];
        if (cfgMap == nil) {
            blockError = [NSError errorWithDomain:@"failed to auto sign in with empty params!" code:-1 userInfo:nil];
            if (completion) {
                completion(blockError);
            }
            return ;//直接失败
        }
        self.serverConfiguration = [self convertMap2SipConfigure:cfgMap];
    }
    __weak typeof(FLKSipService *)weakSelf = self;
    [self startWithConfiguration:self.serverConfiguration withCompletion:^(NSError * _Nullable error) {
        //当重新唤醒程序时，如果当前有'合法'用户则自动登录上去并添加localusr，否则不做登录（用户退出登录时记得clean usr/resign usr）
        if (error != nil) {
            if (completion) {
                completion(error);
            }
        } else {
            [weakSelf autherizeUsr:self.serverConfiguration.localUsrAcc withPwd:self.serverConfiguration.localUsrPwd withCompletion:completion];
        }
    }];
    //*/
    
    //启动sip server
    NSError * _Nullable(^excuteBlock)() = ^(){
        /* first is to check current sip service state */
        NSError *err;
        if ([self serviceAvaliable]) {
            [self stop];
        }
        //[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(stop) object:nil];
        /* check server configuration */
        if (self.serverConfiguration.localUsrAcc.length == 0 || self.serverConfiguration.host.length == 0) {
            _serverConfiguration = nil;
            NSDictionary *cfgMap = [self fetchLocalConfiguration];
            if (cfgMap == nil) {
                err = [NSError errorWithDomain:@"could not start server with null configurations!" code:PJSUA_INVALID_ID userInfo:nil];
                return err;//直接失败
            }
            self.serverConfiguration = [self convertMap2SipConfigure:cfgMap];
        }
        
        err = [self publicSetupSipServer];
        if (err == nil) {
            NSString *sipServer = [self assembleSipServer];
            NSString *usrAcc = self.serverConfiguration.localUsrAcc;
            NSString *usrPwd = self.serverConfiguration.localUsrPwd;
            if (sipServer.length == 0 || usrAcc.length==0 || usrPwd.length == 0) {
                err = [NSError errorWithDomain:@"当前服务配置出错，请重新登录！" code:-1 userInfo:nil];
                return err;
            }
            
            NSLog(@"重启服务中========将要去注册");
            __block pj_status_t status;
            __block pjsua_acc_id acc_id;
            const char *acc_uri = [NSString stringWithFormat:@"sips:%@@%@",usrAcc,sipServer].UTF8String ;
            pjsip_check_thread();
            status = pjsua_verify_sip_url(acc_uri);
            if (status != PJ_SUCCESS) {
                NSLog(@"try to add an eligal local account!");
                err = [NSError errorWithDomain:@"当前登录账号非法，请检查账号！" code:-1 userInfo:nil];
                return err;
            }
            
            pjsua_acc_config cfg;
            pjsua_acc_config_default(&cfg);
            NSString *reg_uri = [NSString stringWithFormat:@"sips:%@",sipServer];
            cfg.id = pj_str((char *)acc_uri);
            cfg.reg_uri = pj_str((char *)reg_uri.UTF8String);
            cfg.reg_retry_interval = 0;
            cfg.cred_count = 1;
            cfg.cred_info[0].scheme = pj_str("Digest");
            cfg.cred_info[0].realm = pj_str("*");
            cfg.cred_info[0].username = pj_str((char *)usrAcc.UTF8String);
            cfg.cred_info[0].data_type = PJSIP_CRED_DATA_PLAIN_PASSWD;
            cfg.cred_info[0].data = pj_str((char *)usrPwd.UTF8String);
            cfg.allow_contact_rewrite = PJ_TRUE;
            cfg.contact_rewrite_method = PJSUA_CONTACT_REWRITE_NO_UNREG;
            cfg.use_srtp = PJMEDIA_SRTP_OPTIONAL;
            cfg.reg_timeout = 180;//600
            cfg.unreg_timeout = 1600;//1.6sec
            cfg.ka_interval = 15;//secs
            cfg.auth_pref.initial_auth = PJ_FALSE;
            
            /* add account */
            pjsip_check_thread();
            //register account
            acc_id = PJSUA_INVALID_ID;
            
            status = pjsua_acc_add(&cfg, PJ_TRUE, &acc_id);
            if (status != PJ_SUCCESS) {
                NSString *errmsg = [NSString stringWithFormat:@"failed to login sip server, error code:%d!",status];
                NSLog(@"register error:%@",errmsg);
                err = [NSError errorWithDomain:errmsg code:-1 userInfo:nil];
                return err;
            } else {
                //TODO:此时并不代表添加账号成功 需要在register回调里边检测
                self.accID = acc_id;
                //[self registerUser2SipServer];
                return err;
            }
        }
        
        return err;
    };
    
    //block excute in safe-thread
    [self excuteBlockEvent:excuteBlock withCompletion:completion];
}

#pragma mark -- 用户信息存储／读取
static NSString * const voipConfigFileName     =       @"voipConfigMap.json";
static NSString * const voipConfigAESKey       =       @"com.flk.ios-voip.key";
- (NSString *)getVoipConfigMapPath {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, true);
    NSString *documentPath = [paths firstObject];
    return [documentPath stringByAppendingPathComponent:voipConfigFileName];
}
- (NSDictionary * _Nullable)fetchLocalConfiguration {
    NSString *path = [self getVoipConfigMapPath];
    //whether the map file exist
    NSFileManager *fileHandler = [NSFileManager defaultManager];
    if (![fileHandler fileExistsAtPath:path]) {
        return nil;
    }
    //generate the map data(encrypted)
    NSData *mapEnData = [NSData dataWithContentsOfFile:path];
    if (mapEnData.length == 0) {
        NSLog(@"failed to fetch the balance map encrypted data!");
        return nil;
    }
    NSError *err = nil;
    NSData *mapDeData = [mapEnData pb_decryptedAES256DataUsingKey:voipConfigAESKey withError:&err];
    if (err != nil) {
        NSLog(@"failed to decrypt balance map data!");
        return nil;
    }
    //convert data to map
    err = nil;
    NSDictionary *map = [NSJSONSerialization JSONObjectWithData:mapDeData options:NSJSONReadingMutableContainers|NSJSONReadingAllowFragments error:&err];
    if (err != nil || map == nil) {
        NSLog(@"failed to convert balance data to map format!");
        return nil;
    }
    return map;
}

- (BOOL)saveVoipConfigMap:(NSDictionary *)map {
    if (map == nil) {
        return false;
    }
    NSError *err = nil;
    NSData *mapData = [NSJSONSerialization dataWithJSONObject:map options:NSJSONWritingPrettyPrinted error:&err];
    if (err != nil || mapData.length == 0) {
        NSLog(@"failed convert balance map to hex data!");
        return false;
    }
    //encrypt data
    err = nil;
    NSData *mapEnData = [mapData pb_encryptedAES256DataUsingKey:voipConfigAESKey withError:&err];
    if (err != nil || mapEnData.length == 0) {
        NSLog(@"failed encrypt balance map data!");
        return false;
    }
    //saved in local path
    NSString *path = [self getVoipConfigMapPath];
    NSFileManager *fileHandler = [NSFileManager defaultManager];
    if ([fileHandler fileExistsAtPath:path]) {
        err = nil;
        [fileHandler removeItemAtPath:path error:&err];
        if (err) {
            NSLog(@"failed to remove old file at path:%@---error:%@", path, err.localizedDescription);
        }
    }
    return [mapEnData writeToFile:path atomically:true];
}
static NSString * const FLK_SIP_USR_KEY_HOST                =   @"voip.cfg.key.host";
static NSString * const FLK_SIP_USR_KEY_PORT                =   @"voip.cfg.key.port";
static NSString * const FLK_SIP_USR_KEY_ACC                 =   @"voip.cfg.key.acc";
static NSString * const FLK_SIP_USR_KEY_PWD                 =   @"voip.cfg.key.pwd";
static NSString * const FLK_SIP_USR_KEY_RING                =   @"voip.cfg.key.ring";
- (FLKSipConfigure * _Nullable)convertMap2SipConfigure:(NSDictionary *)map {
    if (map == nil) {
        return nil;
    }
    NSString *host = [map objectForKey:FLK_SIP_USR_KEY_HOST];
    NSNumber *port = [map objectForKey:FLK_SIP_USR_KEY_PORT];
    NSString *acc = [map objectForKey:FLK_SIP_USR_KEY_ACC];
    NSString *pwd = [map objectForKey:FLK_SIP_USR_KEY_PWD];
    NSString *ring = [map objectForKey:FLK_SIP_USR_KEY_RING];
    FLKSipConfigure *cfg = [FLKSipConfigure configureWithServerHost:host withPort:port.unsignedShortValue withRingFile:ring.length==0?PBFormat(@"%@.%@",PJ_SIP_RING_FILE,PJ_SIP_RING_FILE_EXT):ring];
    cfg.localUsrAcc = acc.copy;
    cfg.localUsrPwd = pwd.copy;
    return cfg;
}

- (NSDictionary * _Nullable)convertSipConfigre2Map:(FLKSipConfigure *)cfg {
    if (cfg == nil) {
        return nil;
    }
    NSMutableDictionary *mutMap = [NSMutableDictionary dictionaryWithCapacity:0];
    [mutMap setObject:cfg.host forKey:FLK_SIP_USR_KEY_HOST];
    NSNumber *port = [NSNumber numberWithUnsignedInteger:(NSUInteger)cfg.port];
    [mutMap setObject:port forKey:FLK_SIP_USR_KEY_PORT];
    [mutMap setObject:cfg.localUsrAcc forKey:FLK_SIP_USR_KEY_ACC];
    [mutMap setObject:cfg.localUsrPwd forKey:FLK_SIP_USR_KEY_PWD];
    NSString *ring = cfg.ringFile;
    ring = ring.length==0?PBFormat(@"%@.%@",PJ_SIP_RING_FILE,PJ_SIP_RING_FILE_EXT):ring;
    [mutMap setObject:ring forKey:FLK_SIP_USR_KEY_RING];
    return [mutMap copy];
}
/**
 从账号转换为昵称
 */
- (NSString * _Nullable)convertAccount2Nick4Account:(NSString *)acc {
    NSString *displayName = nil;
    if (self.voipCallConvertBlock) {
        displayName = self.voipCallConvertBlock(acc);
    }
    return displayName;
}

/**
 保存服务／用户信息 在用户登录成功后
 */
- (BOOL)saveAuthorizedUsrInfosWhileDidSignedIn {
    if (!self.serverConfiguration || self.serverConfiguration.localUsrAcc.length == 0) {
        return false;
    }
    NSDictionary *map = [self convertSipConfigre2Map:self.serverConfiguration];
    BOOL ret = [self saveVoipConfigMap:map];
    return ret;
}

- (NSString *)assembleSipServer {
    NSString *host = self.serverConfiguration.host; uint64_t port = self.serverConfiguration.port;
    NSString *sipServer = [NSString stringWithFormat:@"%@:%lld", host, port];
    if (sipServer.length == 0) {
        sipServer = PJ_SIP_BACKUP_SERVER.copy;
    }
    return sipServer;
}

#pragma mark == 启动sip 服务

- (void)startWithConfiguration:(FLKSipConfigure *)config withCompletion:(void (^ _Nullable)(NSError * _Nullable))completion {
    
    NSError * _Nullable(^excuteBlock)() = ^(){
        /* first is to check current sip service state */
        NSError *err;
        if ([self serviceAvaliable]) {
            err = [NSError errorWithDomain:@"should not re-start sip server while alive!" code:-1 userInfo:nil];
            NSLog(@"should not re-start sip server while alive!");
            return err;
        }
        //[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(stop) object:nil];
        /* check server configuration */
        if (config == nil) {
            if (completion) {
                err = [NSError errorWithDomain:@"could not start server with null configurations!" code:PJSUA_INVALID_ID userInfo:nil];
            }
            return err;
        }
        self.serverConfiguration = config;
        return [self publicSetupSipServer];
    };
    [self excuteBlockEvent:excuteBlock withCompletion:completion];
}

- (void)outterAutoStartSipServiceWithCompletion:(void (^)(NSError * _Nullable))completion {
    
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(stop) object:nil];
   
    __block NSError *blockError;
    
    if ([self serviceAvaliable]) {
        NSLog(@"sip service still alive ------------------!");
        //[self registerUser2SipServer];
        if (completion) {
            completion(blockError);
        }
        return;
    }
    
    if (self.serverConfiguration.localUsrAcc.length == 0 || self.serverConfiguration.host.length == 0) {
        _serverConfiguration = nil;
        NSDictionary *cfgMap = [self fetchLocalConfiguration];
        if (cfgMap == nil) {
            blockError = [NSError errorWithDomain:@"failed to auto sign in with empty params!" code:-1 userInfo:nil];
            if (completion) {
                completion(blockError);
            }
            return ;//直接失败
        }
        self.serverConfiguration = [self convertMap2SipConfigure:cfgMap];
    }
    /**
     如果无法保证服务正常 则有以下处理:
     1，上报服务器错误
     2，生成未接来电
     */
    //这时能确定sip service 不正常（有可能是链接 也有可能是用户未认证）
    
    __weak typeof(FLKSipService *)weakSelf = self;
    [self startWithConfiguration:self.serverConfiguration withCompletion:^(NSError * _Nullable error) {//当重新唤醒程序时，如果当前有'合法'用户则自动登录上去并添加localusr，否则不做登录（用户退出登录时记得clean usr/resign usr）
        if (error != nil) {
            if (completion) {
                completion(error);
            }
        } else {
            [weakSelf autherizeUsr:self.serverConfiguration.localUsrAcc withPwd:self.serverConfiguration.localUsrPwd withCompletion:completion];
        }
    }];
}

- (void)startSipServiceFromBackgroundModeWithCompletion:(void (^)(NSError * _Nullable error))completion {
    __block NSError *blockError;
    
    //*
    if ([self serviceAvaliable]) {
        NSLog(@"sip service still alive ------------------!");
        if (completion) {
            completion(blockError);
        }
        return;
    }
    if ([self whetherSuaWasStarting]) {
        NSLog(@"sip service was starting ------------------!");
        if (completion) {
            completion(blockError);
        }
        return;
    }
    //*/
    
    //reset audio session
    [self resetAudioSessionPreCall];
    
    if (self.serverConfiguration.localUsrAcc.length == 0 || self.serverConfiguration.host.length == 0) {
        _serverConfiguration = nil;
        NSDictionary *cfgMap = [self fetchLocalConfiguration];
        if (cfgMap == nil) {
            blockError = [NSError errorWithDomain:@"failed to auto sign in with empty params!" code:-1 userInfo:nil];
            if (completion) {
                completion(blockError);
            }
            return ;//直接失败
        }
        self.serverConfiguration = [self convertMap2SipConfigure:cfgMap];
    }
    
    /**
     如果无法保证服务正常 则有以下处理:
     1，上报服务器错误
     2，生成未接来电
     */
    //这时能确定sip service 不正常（有可能是链接 也有可能是用户未认证）
    
    __weak typeof(FLKSipService *)weakSelf = self;
    [self startWithConfiguration:self.serverConfiguration withCompletion:^(NSError * _Nullable error) {
        //当重新唤醒程序时，如果当前有'合法'用户则自动登录上去并添加localusr，否则不做登录（用户退出登录时记得clean usr/resign usr）
        if ([self whetherSystemOperationAbove10]) {
            [self setPJSuaAudioDeviceEnable:false];
        }
        if (error != nil) {
            if (completion) {
                completion(error);
            }
        } else {
            [weakSelf autherizeUsr:self.serverConfiguration.localUsrAcc withPwd:self.serverConfiguration.localUsrPwd withCompletion:^(NSError * _Nullable error) {
                if (completion) {
                    completion(error);
                }
            }];
        }
    }];
}

/**
 如果在后台启动成功后 可配置时间内如无电话进来 则停止sip服务
 */
- (void)autoStopSipServiceIfNoIncomingCallAfterDelay {
    if (_callID == PJSUA_INVALID_ID || _callState == PJSIP_INV_STATE_NULL) {
        NSError *_Nullable(^block)() = ^(){
            NSError *err;
            if (![self stop]) {
                err = [NSError errorWithDomain:@"failed to stop sip service!" code:-1 userInfo:nil];
            };
            return err;
        };
        [self excuteBlockEvent:block withCompletion:nil];
    }
}

- (void)outterStopSipServiceAndResignAuthorizedWithCompletion:(void (^)(NSError * _Nullable))completion {
    NSError * _Nullable(^block)() = ^(){
        NSError *err;
        if (![self stop]) {
            err = [NSError errorWithDomain:@"failed to stop sip service!" code:-1 userInfo:nil];
        };
        return err;
    };
    [self excuteBlockEvent:block withCompletion:completion];
}

- (void)printlnAudioDevices {
    int dev_count;
    pjmedia_aud_dev_index dev_idx;
    pjsip_check_thread();
    dev_count = pjmedia_aud_dev_count();
    printf("Got %d audio devices\n", dev_count);
    for (dev_idx=0; dev_idx<dev_count; ++dev_idx) {
        pjmedia_aud_dev_info info;
        pjmedia_aud_dev_get_info(dev_idx, &info);
        printf("%d. %s (in=%d, out=%d)\n",
               dev_idx, info.name,
               info.input_count, info.output_count);
    }
}

- (BOOL)setPJSuaAudioDeviceEnable:(BOOL)enable {
    NSLog(@"______%s", __FUNCTION__);
    pjsip_check_thread();
    NSLog(@"pre-set audio device enable :%d", enable);
    pjsua_state state = pjsua_get_state();
    if (state == PJSUA_STATE_CLOSING || state == PJSUA_STATE_NULL) {
        NSLog(@"pjsua did destroied, no-need set audio device again!");
        return true;
    }
    if (enable) {
        //int capture_dev; int playback_dev;
        //pjsua_get_snd_dev(&capture_dev, &playback_dev);
        //NSLog(@"----------------------------------get dev:%zd------%zd", capture_dev, playback_dev);
        pj_status_t status;
        status = pjsua_set_snd_dev(PJMEDIA_AUD_DEFAULT_CAPTURE_DEV, PJMEDIA_AUD_DEFAULT_PLAYBACK_DEV);
        //status = pjsua_set_snd_dev(0, 0);
        NSLog(@"启用语音设备结果:%@", status==PJ_SUCCESS?@"成功！":@"失败！");
        return status == PJ_SUCCESS;
    } else {
        pjsua_set_no_snd_dev();
        //pjsua_set_null_snd_dev();
    }
    
    return true;
}

- (NSError *)publicSetupSipServer {
    NSString *sipServer = [self assembleSipServer];
    
    __block pj_status_t status;
    /* register pjsua thread */
    pjsip_check_thread();
    /* clean sua */
    if (pjsua_get_state() != PJSUA_STATE_NULL) {
        /*
        status = pjsua_destroy();
        if (status != PJ_SUCCESS) {
            NSLog(@"failed to clean pjsua!");
        }
         */
    }
    
    
    /* create sua */
    status = pjsua_create();
    if (status != PJ_SUCCESS) {
        NSError *err = [NSError errorWithDomain:@"failed to create pjsua!" code:PJSUA_INVALID_ID userInfo:nil];
        return err;
    }
    
    /* Create pool for application */
    _app_cfg.pool = pjsua_pool_create(PJ_SIP_POOL, 1000, 1000);
    
    /* setting default */
    pjsua_config_default(&(_app_cfg.cfg));
    
    /* setting user agent */
    NSString *user_agent = getUsrAgent();
    pj_strdup2_with_null(_app_cfg.pool, &_app_cfg.cfg.user_agent, user_agent.UTF8String);
    
    /* setting log info */
    pjsua_logging_config_default(&(_app_cfg.log_cfg));
#ifdef DEBUG
    _app_cfg.log_cfg.msg_logging = PJ_TRUE;
    _app_cfg.log_cfg.console_level = 4;
    _app_cfg.log_cfg.level = 6;
    pj_log_set_level(6);
#else
    _app_cfg.log_cfg.msg_logging = PJ_FALSE;
    _app_cfg.log_cfg.console_level = 0;
    _app_cfg.log_cfg.level = 0;
    pj_log_set_level(0);
#endif
    
    /* setting media about */
    pjsua_media_config_default(&(_app_cfg.media_cfg));
    _app_cfg.media_cfg.clock_rate = 8000;
    _app_cfg.media_cfg.snd_clock_rate = 8000;
    _app_cfg.media_cfg.ec_options = 2;
    _app_cfg.media_cfg.ec_tail_len = 512;
    _app_cfg.media_cfg.quality = 10;
    
    /* setting call */
    pjsua_call_setting_default(&(_app_cfg.call_cfg));
    _app_cfg.call_cfg.aud_cnt = 1;
    _app_cfg.call_cfg.vid_cnt = 0;
    
    /* silence detector! */
    _app_cfg.media_cfg.no_vad = PJ_TRUE;
    _app_cfg.media_cfg.snd_auto_close_time = 0;
    /* setting ice */
    _app_cfg.media_cfg.enable_ice = PJ_FALSE;
    
    /* setting transport channels */
    pjsua_transport_config_default(&(_app_cfg.tcp_cfg));
    //_app_cfg.tcp_cfg.port = 8443;
    pjsua_transport_config_default(&(_app_cfg.rtp_cfg));
    //_app_cfg.rtp_cfg.port = 4000;
    
    /* setting callbacks */
    _app_cfg.cfg.cb.on_pager = &on_pager;                            // SMS message
    _app_cfg.cfg.cb.on_incoming_call = &on_incoming_call;            // 来电回调
    _app_cfg.cfg.cb.on_call_media_state = &on_call_media_state;      // 媒体状态回调（通话建立后，要播放RTP流）
    _app_cfg.cfg.cb.on_call_state = &on_call_state;                  // 电话状态回调
    _app_cfg.cfg.cb.on_reg_state = &on_reg_state;                    // 注册状态回调
    _app_cfg.cfg.cb.on_call_redirected = &on_call_redirected;        // 来电路由重置
    _app_cfg.cfg.use_srtp = PJMEDIA_SRTP_OPTIONAL;
    _app_cfg.cfg.max_calls = 1;
    //_app_cfg.cfg.srtp_secure_signaling = PJSUA_DEFAULT_SRTP_SECURE_SIGNALING;
    
    /* settng sip server */
    NSString *outbound_proxy = [NSString stringWithFormat:@"sips:%@",sipServer];
    pj_strdup2_with_null(_app_cfg.pool, &_app_cfg.cfg.outbound_proxy[0], outbound_proxy.UTF8String);
    _app_cfg.cfg.outbound_proxy_cnt = 1;
    pjsip_cfg()->endpt.disable_secure_dlg_check = PJ_TRUE;
    
    /* init sua */
    //status = pjsua_init(&cfg, &log_cfg, &media_cfg);
    status = pjsua_init(&_app_cfg.cfg, &_app_cfg.log_cfg, &_app_cfg.media_cfg);
    if (status != PJ_SUCCESS) {
        NSLog(@"error init pjsua!");
        goto on_start_error;
    }
    
    /* setting rings and ringback */
    [self setupRingTongs];
    
    /* setting tcps */
    pjsua_transport_id trans_id = -1;
    status = pjsua_transport_create(PJSIP_TRANSPORT_TLS, &(_app_cfg.tcp_cfg), &trans_id);
    if (status != PJ_SUCCESS) {
        NSLog(@"failed to create pjsua transport id!");
        goto on_start_error;
    }
    
    /* start pjsua */
    status = pjsua_start();
    if (status != PJ_SUCCESS) {
        NSLog(@"error start pjsua");
        goto on_start_error;
    }
    
    /* setting gsm */
    pj_str_t gsm_str = pj_str("gsm");//{"gsm":3}
    pjsua_codec_set_priority(&gsm_str, PJMEDIA_CODEC_PRIO_LOWEST);
#if DEBUG
    [self printlnAudioDevices];
#endif
    
    return nil;
    
    /* define error method todo */
on_start_error:{
    //NSLog(@"error start engine!");
    [self stop];
    NSError *err = [NSError errorWithDomain:@"failed to start sip server!" code:PJSUA_INVALID_ID userInfo:nil];
    return err;
}
}

/**
 setup ringtones, should call after pjsua init
 */
- (void)setupRingTongs {
    
    /* Ringback tone (call is ringing) */
    pj_str_t name;
    pj_status_t status;
    unsigned samples_per_frame;
    pjmedia_tone_desc tone[RING_CNT+RINGBACK_CNT];
    name = pj_str("ringback");
    samples_per_frame = _app_cfg.media_cfg.audio_frame_ptime * _app_cfg.media_cfg.clock_rate * _app_cfg.media_cfg.channel_count / 1000;
    status = pjmedia_tonegen_create2(_app_cfg.pool, &name,
                                     _app_cfg.media_cfg.clock_rate,
                                     _app_cfg.media_cfg.channel_count,
                                     samples_per_frame,
                                     16, PJMEDIA_TONEGEN_LOOP,
                                     &_app_cfg.ringback_port);
    if (status != PJ_SUCCESS) {
        goto on_error;
    }
    
    pj_bzero(&tone, sizeof(tone));
    for (int i = 0; i < RINGBACK_CNT; ++i) {
        tone[i].freq1 = RINGBACK_FREQ1;
        tone[i].freq2 = RINGBACK_FREQ2;
        tone[i].on_msec = RINGBACK_ON;
        tone[i].off_msec = RINGBACK_OFF;
    }
    tone[RINGBACK_CNT-1].off_msec = RINGBACK_INTERVAL;
    
    pjmedia_tonegen_play(_app_cfg.ringback_port, RINGBACK_CNT, tone,
                         PJMEDIA_TONEGEN_LOOP);
    
    
    status = pjsua_conf_add_port(_app_cfg.pool, _app_cfg.ringback_port,
                                 &_app_cfg.ringback_slot);
    
    if (status != PJ_SUCCESS) {
        NSLog(@"failed to setup ringtong!");
        goto on_error;
    }
    
    return ;
    
    
on_error:
    [self stop];
    
    return ;
}

- (BOOL)stop {
    pj_status_t status;
    pjsip_check_thread();
    NSLog(@"pre-start stop sip server===========================================");
    if (_callID != PJSUA_INVALID_ID && _voipProfile != nil) {
        //当前正在通话中
        //[self hangupAudioCall4Code:PJSIP_SC_BUSY_HERE];
    }
    pjsua_state state = pjsua_get_state();
    if (state == PJSUA_STATE_CLOSING || state == PJSUA_STATE_NULL) {
        NSLog(@"pjsua did destroied, no-need stop again!");
        return true;
    }
    NSLog(@"real-start stop sip server===========================================");
    //pjsua status
    
    /* close ringback port */
    if (_app_cfg.ringback_port && _app_cfg.ringback_slot != PJSUA_INVALID_ID) {
        pjsua_conf_remove_port(_app_cfg.ringback_slot);
        _app_cfg.ringback_slot = PJSUA_INVALID_ID;
        pjmedia_port_destroy(_app_cfg.ringback_port);
        _app_cfg.ringback_port = NULL;
    }
    
    /* close ring port */
    if (_app_cfg.ring_on) {
        _app_cfg.ring_on = PJ_FALSE;
        AudioServicesDisposeSystemSoundID(_app_cfg.ring_soundID);
    }
    
    /* release pool */
    if (_app_cfg.pool) {
        pj_pool_release(_app_cfg.pool);
        _app_cfg.pool = NULL;
    }
    
    /* clean pjsua */
    status = pjsua_destroy();
    pj_bzero(&_app_cfg, sizeof(_app_cfg));
    _callID = PJSUA_INVALID_ID;
    _callState = PJSIP_INV_STATE_NULL;
    
    return status == PJ_SUCCESS;
}

#pragma mark -- device's audio volume for microphone & speaker

- (BOOL)adjustSpeakerVolume2:(float)v {
    if (_callID == PJSUA_INVALID_ID)
        return NO;
    
    pjsip_check_thread();
    pjsua_call_info callInfo;
    if (pjsua_call_get_info(_callID, &callInfo) != PJ_SUCCESS) {
        return NO;
    }
    if (callInfo.media_status == PJSUA_CALL_MEDIA_ACTIVE) {
        pjsua_conf_port_id callPort = pjsua_call_get_conf_port(_callID);
        return pjsua_conf_adjust_rx_level(callPort, v) == PJ_SUCCESS;
    }
    return NO;
}

- (BOOL)adjustMicrophoneVolume2:(float)v {
    if (_callID == PJSUA_INVALID_ID)
        return NO;
    pjsip_check_thread();
    pjsua_call_info callInfo;
    if (pjsua_call_get_info(_callID, &callInfo) != PJ_SUCCESS) {
        return NO;
    }
    if (callInfo.media_status == PJSUA_CALL_MEDIA_ACTIVE) {
        pjsua_conf_port_id callPort = pjsua_call_get_conf_port(_callID);
        return pjsua_conf_adjust_tx_level(callPort, v) == PJ_SUCCESS;
    }
    return NO;
}

- (BOOL)handsFreeModeEnable:(BOOL)enable {
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSString *category = session.category;
    AVAudioSessionCategoryOptions oldOptions = session.categoryOptions;
    AVAudioSessionCategoryOptions options = enable?(oldOptions|AVAudioSessionCategoryOptionDefaultToSpeaker):(oldOptions & ~AVAudioSessionCategoryOptionDefaultToSpeaker);
    return [session setCategory:category withOptions:options error:nil];
}

- (UIApplicationState)applicationState {
    return [UIApplication sharedApplication].applicationState;
}

/**
 whether application's curent state was forground-mode
 */
- (BOOL)applicationWhetherForeground {
    return [self applicationState] == UIApplicationStateActive;
}

- (BOOL)serviceAvaliable {
    return pjsua_get_state() == PJSUA_STATE_RUNNING;
}

- (BOOL)whetherSuaWasStarting {
    pjsua_state state = pjsua_get_state();
    return (state == PJSUA_STATE_CREATED || state == PJSUA_STATE_INIT || state == PJSUA_STATE_STARTING);
}

/**
 是否可以重置(重新启动当且仅当状态为NULL时可以reboot)sip服务
 */
- (BOOL)whetherCanRebootSipService {
    return pjsua_get_state() == PJSUA_STATE_NULL;
}

/**
 sip服务是否正常（包括链接正常&&用户已认证）
 */
- (BOOL)whetherSipServiceRunning {
    return [self serviceAvaliable] && [self whetherExistLegalUsrOnLine];
}

- (BOOL)whetherExistLegalUsrOnLine {
    if (_accID == PJSUA_INVALID_ID) {
        return false;
    }
    return pjsua_acc_is_valid(_accID);
}

/**
 从后台换形时：询问是否存在需要激活sip server 并且自动添加用户
 */
- (BOOL)didExistShouldAutoAuthorUsr {
    return self.serverConfiguration.localUsrAcc.length > 0 && self.serverConfiguration.localUsrPwd.length > 0;
}

#pragma mark -- add sip account
- (void)autherizeUsr:(NSString *)acc withPwd:(NSString *)pwd withCompletion:(void (^_Nullable)(NSError * _Nullable error))completion {
    NSError * err;
    //首先检测服务是否已启动
    if (![self serviceAvaliable]) {
        err = [NSError errorWithDomain:@"服务不可用，请重新登录！" code:-1 userInfo:nil];
        if (completion) {
            completion(err);
        }
        return;
    }
    
    NSError * _Nullable(^block)() = ^(){
        NSError *err;
        NSString *sipServer = [self assembleSipServer];
        NSString *usrAcc = acc;
        NSString *usrPwd = pwd;
        if (sipServer.length == 0 || usrAcc.length==0 || usrPwd.length == 0) {
            err = [NSError errorWithDomain:@"当前服务配置出错，请重新登录！" code:-1 userInfo:nil];
            return err;
        }
        
        /* 暂存用户账号密码到内存 授权验证成功后写到文件 */
        self.serverConfiguration.localUsrAcc = usrAcc.copy;
        self.serverConfiguration.localUsrPwd = usrPwd.copy;
        
        NSLog(@"将要去注册");
        __block pj_status_t status;
        __block pjsua_acc_id acc_id;
        const char *acc_uri = [NSString stringWithFormat:@"sips:%@@%@",usrAcc,sipServer].UTF8String ;
        pjsip_check_thread();
        status = pjsua_verify_sip_url(acc_uri);
        if (status != PJ_SUCCESS) {
            NSLog(@"try to add an eligal local account!");
            err = [NSError errorWithDomain:@"当前登录账号非法，请检查账号！" code:-1 userInfo:nil];
            return err;
        }
        
        pjsua_acc_config cfg;
        pjsua_acc_config_default(&cfg);
        NSString *reg_uri = [NSString stringWithFormat:@"sips:%@",sipServer];
        cfg.id = pj_str((char *)acc_uri);
        cfg.reg_uri = pj_str((char *)reg_uri.UTF8String);
        cfg.reg_retry_interval = 0;
        cfg.cred_count = 1;
        cfg.cred_info[0].scheme = pj_str("Digest");
        cfg.cred_info[0].realm = pj_str("*");
        cfg.cred_info[0].username = pj_str((char *)usrAcc.UTF8String);
        cfg.cred_info[0].data_type = PJSIP_CRED_DATA_PLAIN_PASSWD;
        cfg.cred_info[0].data = pj_str((char *)usrPwd.UTF8String);
        cfg.allow_contact_rewrite = PJ_TRUE;
        //cfg.contact_rewrite_method = PJSUA_CONTACT_REWRITE_NO_UNREG;
        cfg.use_srtp = PJMEDIA_SRTP_OPTIONAL;
        cfg.reg_timeout = 180;//600
        cfg.unreg_timeout = 1600;//1.6sec
        cfg.ka_interval = 15;//secs
        cfg.auth_pref.initial_auth = PJ_FALSE;
        
        /* add account */
        pjsip_check_thread();
        //register account
        acc_id = PJSUA_INVALID_ID;
        
        status = pjsua_acc_add(&cfg, PJ_TRUE, &acc_id);
        if (status != PJ_SUCCESS) {
            NSString *errmsg = [NSString stringWithFormat:@"failed to login sip server, error code:%d!",status];
            NSLog(@"register error:%@",errmsg);
            err = [NSError errorWithDomain:errmsg code:-1 userInfo:nil];
            return err;
        } else {
            //TODO:此时并不代表添加账号成功 需要在register回调里边检测
            self.accID = acc_id;
            //[self registerUser2SipServer];
            return err;
        }
        
        return err;
    };
    [self excuteBlockEvent:block withCompletion:completion];
}

- (BOOL)registerUser2SipServer {
    pj_status_t status = PJ_FALSE;
    pjsip_check_thread();
    if (pjsua_acc_is_valid(_accID)) {
        /* set usr state to online */
        status = pjsua_acc_set_registration(_accID, PJ_TRUE);
    } else {
        NSLog(@"failed to register usr!!!");
    }
    return status == PJ_SUCCESS;
}

- (BOOL)unregisterCurrentUser {
    pj_status_t status = PJ_FALSE;
    pjsip_check_thread();
    if (pjsua_acc_is_valid(_accID)) {
        /* set usr state to online */
        //pjsua_acc_set_online_status(_accID, online);
        status = pjsua_acc_set_registration(_accID, PJ_FALSE);
    } else {
        NSLog(@"failed to unregister usr!!!");
    }
    return status == PJ_SUCCESS;
}

/**
 当前已认证用户是否在线
 */
- (BOOL)whetherCurrentUsrOnline {
    BOOL ret = false;
    pjsip_check_thread();
    if (pjsua_acc_is_valid(_accID)) {
        pjsua_acc_info info;
        pj_status_t status = pjsua_acc_get_info(_accID, &info);
        if (status == PJ_SUCCESS) {
            ret = info.online_status;
        }
    }
    
    return ret;
}

#pragma mark -- make audio call

- (BOOL)whetherExistingAudioCall {
    return _callID != PJSUA_INVALID_ID;
}

- (BOOL)whetherSystemOperationAbove10 {
    return [[UIDevice currentDevice].systemVersion floatValue] >= 10.f;
    //return [[UIDevice currentDevice].systemVersion compare:@"10.0" options:NSNumericSearch range:NSMakeRange(0, 2)] != NSOrderedDescending;
}

- (NSString * _Nullable)remoteEndia {
    if (_callID == PJSUA_INVALID_ID) {
        return nil;
    }
    pjsua_call_info info;
    
    pjsip_check_thread();
    
    if (pjsua_call_get_info(_callID, &info) != PJ_SUCCESS) {
        return nil;
    }
    if (info.remote_info.ptr != NULL) {
        return [[NSString alloc] initWithBytes:info.remote_info.ptr length:info.remote_info.slen encoding:NSUTF8StringEncoding];
    }
    if (info.remote_contact.ptr != NULL) {
        return [[NSString alloc] initWithBytes:info.remote_contact.ptr length:info.remote_contact.slen encoding:NSUTF8StringEncoding];
    }
    return nil;
}

- (NSString *)remoteEndiaAccount {
    NSString *remote = [self remoteEndia];
    if (remote.length == 0) {
        return remote;
    }
    NSString *pattern = @"(:).*(@)";
    NSError *error = nil;NSString *acc = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:&error];
    if (error) {
        NSLog(@"failed to generate regular with error:%@", error.localizedDescription);
    } else {
        NSRange range = NSMakeRange(0, remote.length);
        // 获取特特定字符串的范围
        NSTextCheckingResult *match = [regex firstMatchInString:remote options:0 range:range];
        if (match) {
            NSLog(@"range is:%@",NSStringFromRange(match.range));
            /* adgust match rang manualy */
            NSRange destRang = NSMakeRange(match.range.location+1, match.range.length-2);
            acc = [remote substringWithRange:destRang];
        }
    }
    return acc;
}

- (NSString * _Nullable)remoteEndiaFullAccount {
    return [self remoteEndia];
}

- (NSString *)fetchRemoteEndianAccount4Sip:(NSString *)sip {
    NSString *pattern = @"(:).*(@)";
    NSError *error = nil;NSString *acc = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:&error];
    if (error) {
        NSLog(@"failed to generate regular with error:%@", error.localizedDescription);
    } else {
        NSRange range = NSMakeRange(0, sip.length);
        // 获取特特定字符串的范围
        NSTextCheckingResult *match = [regex firstMatchInString:sip options:0 range:range];
        if (match) {
            NSLog(@"range is:%@",NSStringFromRange(match.range));
            /* adgust match rang manualy */
            NSRange destRang = NSMakeRange(match.range.location+1, match.range.length-2);
            acc = [sip substringWithRange:destRang];
        }
    }
    return acc;
}
/**
 当前通话 是否是自己（alice）主叫
 */
- (BOOL)whetherAliceWasCaller {
    if (_callID == PJSUA_INVALID_ID) {
        return false;
    }
    pjsua_call_info info;
    
    pjsip_check_thread();
    if (pjsua_call_get_info(_callID, &info) == PJ_SUCCESS) {
        return info.role == PJSIP_ROLE_UAC || info.role == PJSIP_UAC_ROLE;
    }
    return false;
}

/**
 获取当前通话的语音流状态
 */
- (pjsua_stream_stat)fetchCallStreamStat {
    pjsua_stream_stat stat;
    if (_callID == PJSUA_INVALID_ID) {
        return stat;
    }
    pjsip_check_thread();
    pjsua_call_info info;
    if (pjsua_call_get_info(_callID, &info) != PJ_SUCCESS) {
        return stat;
    }
    for (unsigned mi = 0; mi < info.media_cnt; mi++) {
        if (info.media[mi].type == PJMEDIA_TYPE_AUDIO) {
            if (pjsua_call_get_stream_stat(_callID, mi, &stat) == PJ_SUCCESS) {
                break;
            }
        } else if (info.media[mi].type == PJMEDIA_TYPE_VIDEO) {
            // video
        }
    }
    return stat;
}

#pragma mark == 拨打语音电话 audio call actions ==

- (void)resetAudioSessionPreCall {
    // Configure the audio session
    AVAudioSession *sessionInstance = [AVAudioSession sharedInstance];
    
    // we are going to play and record so we pick that category
    NSError *error = nil;
    [sessionInstance setCategory:AVAudioSessionCategoryPlayAndRecord error:&error];
    if (error) {
        NSLog(@"failed to set audio session category:%@", error.localizedDescription);
    }
    // set the mode to voice chat
    [sessionInstance setMode:AVAudioSessionModeVoiceChat error:&error];
    
    [sessionInstance setActive:true error:&error];
    if (error) {
        NSLog(@"===============================pre error:%@===============================", error.localizedDescription);
    }
}

- (void)resetAudioSessionAfterCall {
    // Configure the audio session
    AVAudioSession *sessionInstance = [AVAudioSession sharedInstance];
    // we are going to play and record so we pick that category
    NSError *error = nil;
    /*
    NSString *category;
    if ([self applicationWhetherForeground]) {
        category = AVAudioSessionCategoryMultiRoute;
    } else {
        category = AVAudioSessionCategoryAmbient;
    }
    //*/
    [sessionInstance setCategory:AVAudioSessionCategoryAmbient error:&error];
    if (error) {
        NSLog(@"failed to set audio session category:%@", error.localizedDescription);
    }
    
    //[sessionInstance setActive:[self applicationWhetherForeground] error:&error];
    //if (error) {
    //    NSLog(@"===============================after error:%@===============================", error.localizedDescription);
    //}
}

- (void)startVoipCall2UserAccount:(NSString *)acc withCompletion:(void (^ _Nullable)(NSError * _Nullable))completion{
    NSError *error;
    //*判断网络
    if (![self networkStateAvaliable]) {
        error = [NSError errorWithDomain:@"当前网络不可用，请检查网络连接或关闭VPN代理！" code:-1 userInfo:nil];
        if (completion) {
            completion(error);
        }
        return;
    }
    //*/
    
    //判断账号
    if (acc.length == 0) {
        error = [NSError errorWithDomain:@"呼叫对方账号不能为空！" code:-1 userInfo:nil];
        if (completion) {
            completion(error);
        }
        return;
    }
    //判断当前是否已显示profile
    if (_voipProfile != nil) {
        return;
    }
    //*
    if (![self serviceAvaliable]) {
        error = [NSError errorWithDomain:@"当前不在服务区,请稍后重试！或重新登录！" code:-1 userInfo:nil];
        if (completion) {
            completion(error);
        }
        [self restartSipServerWithCompletion:nil];
        return;
    }
    //*/
    
    NSError * _Nullable (^block)() = ^(){
        NSError *err;
        
        if (![self serviceAvaliable]) {
            err = [NSError errorWithDomain:@"failed to start voip call cause of service unavaliable!" code:-1 userInfo:nil];
            [self restartSipServerWithCompletion:nil];
            return err;
        }
        
        [self resetAudioSessionPreCall];
        
        NSString *sipServer = [self assembleSipServer];
        pjsua_acc_id acc_id = pjsua_acc_get_default();
        NSString *targetUri = [NSString stringWithFormat:@"sips:%@@%@",acc,sipServer];
        NSLog(@"acc_id:%d launched calling to %@",acc_id, acc);
        
        pj_status_t status;
        char *tmp_uri = (char *)targetUri.UTF8String;
        pjsip_check_thread();
        status = pjsua_verify_url(tmp_uri);
        if (status != PJ_SUCCESS){
            NSLog(@"invalid calling uri !");
            err = [NSError errorWithDomain:@"对方账号不存在！" code:-1 userInfo:nil];
            return err;
        }
        pj_str_t dest_uri = pj_str(tmp_uri);
        
        /* call setting */
        pjsua_call_setting call_cfg;
        pjsua_call_setting_default(&call_cfg);
        call_cfg.aud_cnt = 1;
        call_cfg.vid_cnt = 0;
        _callID = PJSUA_INVALID_ID;
        status = pjsua_call_make_call(acc_id, &dest_uri, &call_cfg, NULL, NULL, &_callID);
        if (status != PJ_SUCCESS) {
            char errmsg[PJ_ERR_MSG_SIZE];
            pj_strerror(status, errmsg, sizeof(errmsg));
            NSLog(@"calling error:%d---%s",status, errmsg);
            err = [NSError errorWithDomain:[NSString stringWithFormat:@"%s", errmsg] code:-1 userInfo:nil];
            return err;
        }
        
        return err;
    };
    [self excuteBlockEvent:block withCompletion:completion];
    
    /*
    NSString *sipServer = [self assembleSipServer];
    pjsua_acc_id acc_id = pjsua_acc_get_default();
    NSString *targetUri = [NSString stringWithFormat:@"sips:%@@%@",acc,sipServer];
    NSLog(@"acc_id:%d launched calling to %@",acc_id, acc);
    //
    //pjsua_set_null_snd_dev();
    
    pj_status_t status;
    char *tmp_uri = (char *)targetUri.UTF8String;
    pjsip_check_thread();
    status = pjsua_verify_url(tmp_uri);
    if (status != PJ_SUCCESS){
        NSLog(@"invalid calling uri !");
        error = [NSError errorWithDomain:@"对方账号不存在！" code:-1 userInfo:nil];
        if (completion) {
            completion(error);
        }
        return;
    }
    pj_str_t dest_uri = pj_str(tmp_uri);
    
    // call setting //
    pjsua_call_setting call_cfg;
    pjsua_call_setting_default(&call_cfg);
    call_cfg.aud_cnt = 1;
    call_cfg.vid_cnt = 0;
    _callID = PJSUA_INVALID_ID;
    status = pjsua_call_make_call(acc_id, &dest_uri, &call_cfg, NULL, NULL, &_callID);
    if (status != PJ_SUCCESS) {
        char errmsg[PJ_ERR_MSG_SIZE];
        pj_strerror(status, errmsg, sizeof(errmsg));
        NSLog(@"calling error:%d---%s",status, errmsg);
        error = [NSError errorWithDomain:[NSString stringWithFormat:@"%s", errmsg] code:-1 userInfo:nil];
        if (completion) {
            completion(error);
        }
        return;
    }
    if (completion) {
        completion(nil);
    }
     //*/
    //启动主叫 UI
    [self enableLocalVoipCallFlagWithUUID:nil];
    [self startOutGoingCallUI4Account:acc];
}

#pragma mark -- Call callback Event -

- (void)registerVoipCallbackEventHandler:(_Nullable FLKVoipCallbackBlock)completion {
    self.voipCallBackBlock = [completion copy];
}

- (void)registerVoipCallConvertDisplayEventHandler:(FLKVoipConvertDisplayBlock)completion {
    self.voipCallConvertBlock = [completion copy];
}

- (void)registerVoipCallProfileShowEventHandler:(FLKVoipCallProfileBlock)completion {
    self.voipCallProfileBlock = [completion copy];
}

- (void)registerVoipServiceShouldRestartWhenNetworkAvailable:(FLKVoipServiceRestartBlock)completion {
    self.voipServiceRestartBlock = [completion copy];
}

static NSString * const FLK_VOIPCALL_OTHER_EVENT_BUSY                       =   @"busy";//对方正在通话中
static NSString * const FLK_VOIPCALL_OTHER_EVENT_CANNOT_CONNECT             =   @"ll";//无法拨通
static NSString * const FLK_VOIPCALL_OTHER_EVENT_UNACCEPT                   =   @"oo";//无人接听

/**
 电话挂断是否是其他事件导致

 @param contact 联系人信息
 */
- (BOOL)whetherOtherEvent4Contact:(NSString *)contact {
    if (PBIsEmpty(contact)) {
        return false;
    }
    
    if ([contact rangeOfString:FLK_VOIPCALL_OTHER_EVENT_BUSY].location != NSNotFound
        ||[contact rangeOfString:FLK_VOIPCALL_OTHER_EVENT_UNACCEPT].location != NSNotFound
        ||[contact rangeOfString:FLK_VOIPCALL_OTHER_EVENT_CANNOT_CONNECT].location != NSNotFound) {
        return true;
    }
    return false;
}

- (FLKVoipCallEndState)fetchCallEndState4OtherEventWithContact:(NSString *)contact {
    FLKVoipCallEndState endState = FLKVoipCallEndStateRemoteUnavaliable;
    if ([contact rangeOfString:FLK_VOIPCALL_OTHER_EVENT_BUSY].location != NSNotFound) {
        endState = FLKVoipCallEndStateRemoteBusy;
    } else if ([contact rangeOfString:FLK_VOIPCALL_OTHER_EVENT_UNACCEPT].location != NSNotFound) {
        endState = FLKVoipCallEndStateRemoteUnAccept;
    } else if ([contact rangeOfString:FLK_VOIPCALL_OTHER_EVENT_CANNOT_CONNECT].location != NSNotFound) {
        endState = FLKVoipCallEndStateRemoteUnavaliable;
    }
    return endState;
}

- (FLKVoipCallEndState)fetchVoipCallEndState4Role:(FLKVoipCallRole)role {
    
    FLKVoipCallEndState endState = FLKVoipCallEndStateRemoteUnavaliable;
    if (_callID == PJSUA_INVALID_ID) {
        return endState;
    }
    
    pjsua_call_info info;
    pjsip_check_thread();
    if (pjsua_call_get_info(_callID, &info) == PJ_SUCCESS) {
        NSTimeInterval interval = info.connect_duration.sec;
        NSString *remoteContact = [[NSString alloc] initWithBytesNoCopy:info.remote_contact.ptr length:info.remote_contact.slen encoding:NSASCIIStringEncoding freeWhenDone:NO];
        //是否是其他事件打断
        BOOL whetherByOtherEvent = [self whetherOtherEvent4Contact:remoteContact];
        if (interval > 0) {
            //说明接通了电话 也有可能是语音提示
            
            if (whetherByOtherEvent) {
                //说明是语音提示
                endState = [self fetchCallEndState4OtherEventWithContact:remoteContact];
            } else {
                //已经接通 至少有一方主动挂断
                if (self.whetherHangupByMySelf && role == FLKVoipCallRoleUAC) {
                    endState = FLKVoipCallEndStateUACHangup;
                } else {
                    endState = FLKVoipCallEndStateUASHangup;
                }
            }
        } else {
            //此情况是在电话未confirm时的操作
            
            if (whetherByOtherEvent) {
                endState = [self fetchCallEndState4OtherEventWithContact:remoteContact];
            } else {
                //至少有一方 主动挂断
                if (self.whetherHangupByMySelf && role == FLKVoipCallRoleUAC) {
                    endState = FLKVoipCallEndStateUACCancel;
                } else {
                    endState = FLKVoipCallEndStateUASCancel;
                }
            }
        }
    }
    return endState;
}

/**
 语音电话结束状态:自己取消／对方拒接／挂断／对方忙／不在服务区
 */
- (void)callVoipCallbackWhileCallEnd {
    if (_callID == PJSUA_INVALID_ID) {
        return;
    }
    //judge account
    NSString *remoteAcc = [self remoteEndiaAccount];
    if (remoteAcc.length == 0) {
        return;
    }
    NSString *uuid = self.systemDelegate.currentCall.uuid.UUIDString;
    pjsua_call_info info;
    pjsip_check_thread();
    if (pjsua_call_get_info(_callID, &info) == PJ_SUCCESS) {
        NSTimeInterval interval = info.connect_duration.sec;
        FLKVoipCallRole role = FLKVoipCallRoleUAC;
        if (info.role == PJSIP_ROLE_UAS || info.role == PJSIP_UAS_ROLE) {
            role = FLKVoipCallRoleUAS;
        }
        FLKVoipCallEndState endState = [self fetchVoipCallEndState4Role:role];
        NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:@(interval), FLK_VOIPCALL_END_KEY_INTERVAL, @(endState), FLK_VOIPCALL_END_KEY_STATE, remoteAcc, FLK_VOIPCALL_END_KEY_ACCOUNT, @(role), FLK_VOIPCALL_END_KEY_ROLE, uuid, FLK_VOIPCALL_END_KEY_UUID, nil];
        NSLog(@"通话结束了-------%@", info);
        if (self.voipCallBackBlock) {
            self.voipCallBackBlock(info);
        }
    }
}

- (BOOL)answerAudioCall {
    if (_callID == PJSUA_INVALID_ID) {
        return false;
    }
    //[self createAudioRecordFile];
    pjsip_check_thread();
    return pjsua_call_answer(_callID, PJSIP_SC_OK, NULL, NULL) == PJ_SUCCESS;
}

- (BOOL)holdonAudioCall {
    if (_callID == PJSUA_INVALID_ID) {
        return false;
    }
    pjsip_check_thread();
    return pjsua_call_set_hold(_callID, NULL) == PJ_SUCCESS;
}

- (BOOL)releaseHoldonAudioCall {
    if (_callID == PJSUA_INVALID_ID) {
        return false;
    }
    pjsip_check_thread();
    return pjsua_call_reinvite(_callID, PJSUA_CALL_UNHOLD, NULL) == PJ_SUCCESS;
}

- (BOOL)hangupAudioCall4Code:(unsigned int)code {
    if (_callID == PJSUA_INVALID_ID) {
        return false;
    }
    //pjsua_call_hangup_all();
    pjsip_check_thread();
    pj_status_t status;
    if (pjsua_call_is_active(_callID) == PJ_TRUE) {
        status = pjsua_call_hangup(_callID, code, NULL, NULL);
    }
    //pjsua_call_hangup_all();
    
    self.whetherCallConfirmedBySystem = false;
    return  status == PJ_SUCCESS;
}

- (BOOL)hangupAllAudioCall {
    if (pjsua_call_get_count()) {
        pjsip_check_thread();
        if (_callID != PJSUA_INVALID_ID && pjsua_call_is_active(_callID)) {
            pjsua_call_hangup_all();
            //[self hangupAudioCall4Code:PJSIP_SC_BUSY_HERE];
        }
        _callState = PJSIP_INV_STATE_NULL;
    }
    self.whetherCallConfirmedBySystem = false;
    return true;
}

- (BOOL)isConnecting4CallID:(pjsua_call_id)cid {
    if (cid == PJSUA_INVALID_ID) {
        return false;
    }
    return pjsua_call_is_active(cid);
}

- (void)keepAlive {
    pjsip_check_thread();
    for (unsigned int i = 0, n = pjsua_acc_get_count(); i < n; ++i) {
        if (pjsua_acc_is_valid(i)) {
            pjsua_acc_set_registration(i, PJ_TRUE);
        }
    }
    
}

/**
 DTMF:双音多频，一个DTMF信号由两个频率的音频信号叠加构成

 @param digest :按键
 */
- (BOOL)sendDTMFDigest:(char)digest {
    if (_callID == PJSUA_INVALID_ID) {
        return false;
    }
    pj_str_t dtmf = pj_str(&digest);
    return pjsua_call_dial_dtmf(_callID, &dtmf) == PJ_SUCCESS;
}

#pragma mark -- pjsua rings methods --

- (AVAudioPlayer *)audioPlayer {
    if (!_audioPlayer) {
        //TODO: extent ring files that not in the bundle to support
        NSString *ringFilePath = [self localAudioPath4File:self.serverConfiguration.ringFile];
        NSURL *soundURL = [NSURL fileURLWithPath:ringFilePath];
        NSError *error = nil;
        _audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:soundURL error:&error];
        if (error) {
            NSLog(@"failed to create audio player!");
            return nil;
        }
    }
    return _audioPlayer;
}

- (void)startRingWithSpeaker {
    if (!_app_cfg.ring_on) {
        _app_cfg.ring_on = PJ_TRUE;
        
        //setting ring sound
        SystemSoundID soundFileObject = 0;
        //TODO: extent ring files that not in the bundle to support
        NSString *ringFilePath = [self localAudioPath4File:self.serverConfiguration.ringFile];
        NSURL *soundURL = [NSURL fileURLWithPath:ringFilePath];
        //AudioServicesCreateSystemSoundID((__bridge CFURLRef)soundURL, &_app_cfg.ring_soundID);
        CFURLRef soundFileURLRef = (__bridge CFURLRef)soundURL;
        OSStatus status = AudioServicesCreateSystemSoundID(soundFileURLRef, &soundFileObject);
        if (status == kAudioServicesNoError) {
            /* 对于提醒音来说，与系统声音之间的差别在于，如果手机处于静音状态，提醒音将自动触发震动 */
            //AudioServicesPlaySystemSound(_app_cfg.ring_soundID);
            AudioServicesPlayAlertSound(soundFileObject);
            _app_cfg.ring_soundID = soundFileObject;
        } else {
            NSLog(@"failed to creat system sound id!");
            if (self.audioPlayer) {
                //设置声音的大小
                self.audioPlayer.volume = 0.5;//范围为（0到1）；
                //设置循环次数，如果为负数，就是无限循环
                self.audioPlayer.numberOfLoops =-1;
                //设置播放进度
                self.audioPlayer.currentTime = 0;
                //准备播放
                [self.audioPlayer prepareToPlay];
                [self.audioPlayer play];
            } else {
                NSLog(@"failed to create audio player!");
            }
        }
    }
}

- (void)stopRingWithSpeaker {
    NSLog(@"------%s", __FUNCTION__);
    if (_app_cfg.ring_on) {
        _app_cfg.ring_on = PJ_FALSE;
        AudioServicesDisposeSystemSoundID(_app_cfg.ring_soundID);
    }
    
    if (self.audioPlayer) {
        [self.audioPlayer stop];
        _audioPlayer = nil;
    }
    /*
    if (_app_cfg.record_id != PJSUA_INVALID_ID && _callID != PJSUA_INVALID_ID) {
        pjsua_recorder_destroy(_app_cfg.record_id);
        _app_cfg.record_id = PJSUA_INVALID_ID;
    }
     */
}

- (void)startSuaRingBack {
    if (!_app_cfg.ringback_on) {
        _app_cfg.ringback_on = PJ_TRUE;
        if (_app_cfg.ringback_slot != PJSUA_INVALID_ID) {
            pjsua_conf_connect(_app_cfg.ringback_slot, 0);
        }
    }
}

- (void)stopSuaRingBack {
    NSLog(@"------%s", __FUNCTION__);
    if (_app_cfg.ringback_on) {
        _app_cfg.ringback_on = PJ_FALSE;
        if (_app_cfg.ringback_slot != PJSUA_INVALID_ID) {
            pjsua_conf_disconnect(_app_cfg.ringback_slot, 0);
            pjmedia_tonegen_rewind(_app_cfg.ringback_port);
        }
    }
}

- (void)vibrate {
    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
}

/* Configs */
#define CLOCK_RATE 8000
#define NCHANNELS 2
#define SAMPLES_PER_FRAME (NCHANNELS * (CLOCK_RATE * 10 / 1000))
#define BITS_PER_SAMPLE 16
- (int)createAudioRecordFile {
    pj_caching_pool cp;
    pjmedia_endpt *med_endpt;
    pj_pool_t *pool;
    pjmedia_port *file_port;
    pjmedia_snd_port *snd_port;
    //char tmp[10];
    pj_status_t status;

    /* Verify cmd line arguments. */
    
    
    /* Must init PJLIB first: */
    status = pj_init();
    PJ_ASSERT_RETURN(status == PJ_SUCCESS, 1);
    
    /* Must create a pool factory before we can allocate any memory. */
    pj_caching_pool_init(&cp, &pj_pool_factory_default_policy, 0);

    /*
          106  * Initialize media endpoint.
          107  * This will implicitly initialize PJMEDIA too.
          108  */
    status = pjmedia_endpt_create(&cp.factory, NULL, 1, &med_endpt);
    PJ_ASSERT_RETURN(status == PJ_SUCCESS, 1);

    /* Create memory pool for our file player */
    pool = pj_pool_create( &cp.factory, /* pool factory */
                                "app", /* pool name. */
                                4000, /* init size */
                                4000, /* increment size */
                                NULL /* callback on error */
                                );
    
    /* Create WAVE file writer port. */
    const char *filename = "/Users/nanhujiaju/Desktop/voip.wav";
    status = pjmedia_wav_writer_port_create( pool, filename,
                                                CLOCK_RATE,
                                                NCHANNELS,
                                                SAMPLES_PER_FRAME,
                                                BITS_PER_SAMPLE,
                                                0, 0,
                                                &file_port);
    if (status != PJ_SUCCESS) {
        printf( "Unable to open WAV file for writing %d", status);
        return 1;
    }

    /* Create sound player port. */
    status = pjmedia_snd_port_create_rec(
                                            pool, /* pool */
                                            -1, /* use default dev. */
                                            PJMEDIA_PIA_SRATE(&file_port->info),/* clock rate. */
                                            PJMEDIA_PIA_CCNT(&file_port->info),/* # of channels. */
                                            PJMEDIA_PIA_SPF(&file_port->info), /* samples per frame. */
                                            PJMEDIA_PIA_BITS(&file_port->info),/* bits per sample. */
                                            0, /* options */
                                            &snd_port /* returned port */
                                            );
    if (status != PJ_SUCCESS) {
        printf("Unable to open sound device %d", status);
        return 1;
    }
    
    /* Connect file port to the sound player.
          150  * Stream playing will commence immediately.
          151  */
    status = pjmedia_snd_port_connect( snd_port, file_port);
    PJ_ASSERT_RETURN(status == PJ_SUCCESS, 1);
    
    return 1;
      /** Recording should be started now.*/
}

/**
 是否对方拒接
 此方法在confirm时有用（因目前后台逻辑在对方拒接时也会返回confirm状态） 可判断当confirm时是否为对方拒接／不在服务区／busy/未接通
 */
- (BOOL)whetherRejectedByInverse4CallID:(pjsua_call_id)call_id {
    if(call_id == PJSUA_INVALID_ID) {
        return false;
    }
    
    pjsua_call_info info;
    pj_status_t ret = pjsua_call_get_info(call_id, &info);
    if(ret != PJ_SUCCESS) {
        return false;
    }
    
    NSString *remoteContact = [[NSString alloc] initWithBytesNoCopy:info.remote_contact.ptr length:info.remote_contact.slen encoding:NSASCIIStringEncoding freeWhenDone:NO];
    if ([remoteContact rangeOfString:@"busy"].location != NSNotFound ||//对方正在通话中
        [remoteContact rangeOfString:@"ll"].location != NSNotFound ||//lost link 无法拨通
        [remoteContact rangeOfString:@"oo"].location != NSNotFound) {//无 人接听
        return true;
    }
    
    return false;
}

#pragma mark -- pjsua callbacks c methods --
/* Incoming IM message (i.e. MESSAGE request)!  */
static void on_pager(pjsua_call_id call_id, const pj_str_t *from,
                     const pj_str_t *to, const pj_str_t *contact,
                     const pj_str_t *mime_type, const pj_str_t *body){
    @autoreleasepool {
        [[FLKSipService shared] suaOnPager:call_id from:from to:to contact:contact mimeType:mime_type body:body];
    }
}
static void on_reg_state(pjsua_acc_id acc_id) {
    @autoreleasepool {
        [[FLKSipService shared] suaOnRegisterState4AccountID:acc_id];
    }
}

static void on_call_media_state(pjsua_call_id call_id) {
    @autoreleasepool {
        [[FLKSipService shared] suaOnCallMediaState4CallID:call_id];
    }
}

static void on_call_state(pjsua_call_id call_id, pjsip_event *e) {
    @autoreleasepool {
        [[FLKSipService shared] suaOnCallStateWithEvent:e withCallID:call_id];
    }
}

static void on_incoming_call(pjsua_acc_id acc_id, pjsua_call_id call_id, pjsip_rx_data *rdata) {
    @autoreleasepool {
        [[FLKSipService shared] suaOnIncomingCallWithRData:rdata withCallID:call_id forAccountID:acc_id];
    }
}

static pjsip_redirect_op on_call_redirected(pjsua_call_id call_id, const pjsip_uri *target, const pjsip_event *e) {
    return PJSIP_REDIRECT_ACCEPT;
    @autoreleasepool {
        return [[FLKSipService shared] suaOnCallRedirect:call_id withTarget:target withEvent:e];
    }
}

#pragma mark -- PJSUA Callbacks objc methods --

- (void)suaOnPager:(pjsua_call_id)cid from:(const pj_str_t *)from to:(const pj_str_t *)to contact:(const pj_str_t *)contact mimeType:(const pj_str_t *)mime body:(const pj_str_t *)body {
    NSLog(@"****************  on_pager called  **********************");
    NSString *msg_body = [NSString stringWithUTF8String:body->ptr];
    NSLog(@"received page message:%@---from:%@", msg_body, [NSString stringWithUTF8String:from->ptr]);
}

- (void)suaOnRegisterState4AccountID:(pjsua_acc_id)acc_id {
    pj_status_t status;
    pjsua_acc_info info;
    
    status = pjsua_acc_get_info(acc_id, &info);
    if (status != PJ_SUCCESS) {
        return;
    }
    
    int code = info.status;
    if (code == 200) {
        if (info.expires > 0) {
            NSLog(@"did register user successful!");
            //注册
            self.accID = acc_id;
            //TODO:此处仅仅表示添加账号成功 用户并没有设置在线 需要额外设置在线状态
            [self saveAuthorizedUsrInfosWhileDidSignedIn];
            //*
            UIApplicationState state = [self applicationState];
            if (state == UIApplicationStateBackground) {
                dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
                queue = self.sipServiceQueue;
                weakify(self)
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(FLK_BACKGROUND_MODE_EXCUTE_INTERVAL * NSEC_PER_SEC)), queue, ^{
                    strongify(self)
                    [self autoStopSipServiceIfNoIncomingCallAfterDelay];
                });
            }
            //*/
        } else {
            //注销
            NSLog(@"did unregister user successful!");
        }
    } else if (code >= 400 && code < 600) {
        _accID = PJSUA_INVALID_ID;
    }
    
    id argument = @{@"acc_id":@(acc_id),@"status_text":[NSString stringWithUTF8String:info.status_text.ptr],@"status":@(info.status)};
    
    //TODO:notification acc register state changed
    NSLog(@"acc register state changed...:%@", argument);
}

- (void)suaOnCallMediaState4CallID:(pjsua_call_id)cid {
    pjsua_call_info info;
    pjsua_call_get_info(cid, &info);
    
    //自测 在接通瞬间振铃bubugao还会播放极小一段间隔
    if ([self applicationWhetherForeground]) {
        if (info.role == PJSIP_ROLE_UAC) {
            [self stopSuaRingBack];
        } else {
            [self stopRingWithSpeaker];
        }
    }
    
    for (unsigned media_cnt = 0; media_cnt < info.media_cnt; media_cnt++) {
        if (info.media[media_cnt].type == PJMEDIA_TYPE_AUDIO) {
            if (info.media_status == PJSUA_CALL_MEDIA_ACTIVE
                || info.media_status == PJSUA_CALL_MEDIA_REMOTE_HOLD) {
                //when media is active, connect call to sound device.
                pjsua_conf_connect(info.conf_slot, 0);
                pjsua_conf_connect(0, info.conf_slot);
            }
        } else if (info.media_status == PJMEDIA_TYPE_VIDEO) {
            // video media
        }
    }
    
    NSLog(@"call media state changed...");
    /*
    pjsua_call_media_status call_media_status = info.media_status;
    if (call_media_status == PJSUA_CALL_MEDIA_ACTIVE ||
       call_media_status == PJSUA_CALL_MEDIA_REMOTE_HOLD) {
        //pjsua_recorder_id recorder_id;
        pj_status_t status;
        NSString *filePath = [self localPath4File:@"voip.wav"];
        pj_str_t fileName =pj_str((char *)filePath.UTF8String);
        status = pjsua_recorder_create(&fileName, 0, NULL, 0, 0, &_app_cfg.record_id);
        if (status != PJ_SUCCESS) {
            NSLog(@"failed to create audio recorder!");
        } else {
            pjsua_conf_connect(pjsua_call_get_conf_port(cid), pjsua_recorder_get_conf_port(_app_cfg.record_id));
            pjsua_conf_connect(0, pjsua_recorder_get_conf_port(_app_cfg.record_id));
            //_app_cfg.record_id = recorder_id;
            NSLog(@"app record file id:%d", _app_cfg.record_id);
        }
    }
     */
}
/**
 *  每个状态的描述如下：
 PJSIP_INV_STATE_NULL
 会话第一次被创建时的状态。在状态时，没有消息已经被发送或接收。
 PJSIP_INV_STATE_CALLING
 第一个INVITE消息发送后，在收到任何临时响应之前的会话状态。
 PJSIP_INV_STATE_INCOMING
 接收到第一个INVITE消息后，在没有发送任何临时响应之前的会话状态。
 PJSIP_INV_STATE_EARLY
 在Dialog已经发送或接收到INVITE请求的临时响应之后的会话状态，仅当To标签存在时。
 PJSIP_INV_STATE_CONNECTING
 2xx响应被发送或者接收之后的会话状态
 PJSIP_INV_STATE_CONFIRMED
 ACK请求被发送或者接收之后的会话状态
 PJSIP_INV_STATE_DISCONNECTED
 当会话已经失去连接时，或者INVITE的非成功的响应或BYE请求时的会话状态
 */
- (void)suaOnCallStateWithEvent:(pjsip_event *)event withCallID:(pjsua_call_id)cid {
    pjsua_call_info info;
    if (pjsua_call_get_info(cid, &info) != PJ_SUCCESS) {
        NSLog(@"failed to fetch call info!");
        return;
    }
    
    id argument = @{@"call_id":@(cid),@"state":@(info.state)};
    NSLog(@"call state changed...:%@", argument);
    //TODO:notification call state changed
    PJ_LOG(3,(THIS_FILE, "Call %d state=%.*s", cid,
              (int)info.state_text.slen,
              info.state_text.ptr));
    
    // get the call state
    pjsip_inv_state state = info.state;
    self.callState = state;
    if (self.delegate && [self.delegate respondsToSelector:@selector(audioCallDidChanged2State:)]) {
        PBMAINDelay(PBANIMATE_DURATION, ^{
           [self.delegate audioCallDidChanged2State:state];
        });
    }
    
    //TODO:notification delegates
    //judge the state
    if (state == PJSIP_INV_STATE_DISCONNECTED) {
        NSLog(@"=================================================================");
        //后台可执行时间较短 在这里hook后台
        NSString *remote_acc = [self remoteEndiaAccount];
        UIApplicationState state = [self applicationState];
        if (state == UIApplicationStateBackground) {
            NSLog(@"---------------------------state:%zd----------------------------------------", state);
            //self.taskIdentifier = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
            //    self.taskIdentifier = UIBackgroundTaskInvalid;
            //}];
            if ([self whetherSystemOperationAbove10]) {
                //结束call end
                [self cancelSystemProfileWithUsrAccount:remote_acc withCompletion:^(NSError * _Nullable error) {
                    NSLog(@"cancel system-call ui with error: %@", error.localizedDescription);
                }];
            } else {
                
            }
            //通话结束 在后台时是否需要生成未接来电 此处不再生成未接来电转而由推送生成未接来电
            [self whetherShouldGenerateUnAcceptCallRecord4LocalNotification];
        } else {
            if (info.role == PJSIP_ROLE_UAC) {
                [self stopSuaRingBack];
            } else {
                [self stopRingWithSpeaker];
            }
            //app 处于前台
            remote_acc = [self.systemDelegate.currentHandle copy];
            if ([self whetherSystemOperationAbove10]) {
                [self cancelSystemProfileWithUsrAccount:remote_acc withCompletion:^(NSError * _Nullable error) {
                    NSLog(@"cancel system-call ui with error-------: %@", error.localizedDescription);
                }];
            }
            
            //防止挂不断
            if (self.delegate && [self.delegate respondsToSelector:@selector(audioCallDidChanged2State:)]) {
                PBMAINDelay(PBANIMATE_DURATION, ^{
                    [self.delegate audioCallDidChanged2State:PJSIP_INV_STATE_DISCONNECTED];
                });
            }
        }
        
        //每次通话结束后 需要判断在通话中（前台时）是否有网络切换 有则注销重连 否则不做操作
        //[self networkStateChanged];
        [self callVoipCallbackWhileCallEnd];
        [self disableLocalVoipCallFlag];
        [self resetAudioSessionAfterCall];
        self.whetherHangupByMySelf = false;
        self.whetherCallConfirmedBySystem = false;
        _callID = PJSUA_INVALID_ID;
        _voipProfile.delegate = nil;
        _voipProfile = nil;
        //if (_systemDelegate) {
        //    _systemDelegate.delegate = nil;
        //    _systemDelegate = nil;
        //}
        
        //如果在后台则停止sua 服务
        if (state == UIApplicationStateBackground) {
            self.taskIdentifier = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
                self.taskIdentifier = UIBackgroundTaskInvalid;
            }];
            //stop safely
            NSError * _Nullable(^block)() = ^(){
                NSError *err;
                [self stop];
                return err;
            };
            [self excuteBlockEvent:block withCompletion:nil];
            
            dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
            queue = self.sipServiceQueue;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(FLK_BACKGROUND_MODE_EXCUTE_INTERVAL * NSEC_PER_SEC)), queue, ^{
                [[UIApplication sharedApplication] endBackgroundTask:self.taskIdentifier];
            });
        }
    } else if (state == PJSIP_INV_STATE_CALLING) {
        
    } else if (state == PJSIP_INV_STATE_INCOMING) {
        
    } else if (state == PJSIP_INV_STATE_CONNECTING) {
        
    } else if (state == PJSIP_INV_STATE_EARLY) {
        int code = -1;
        pjsip_msg *msg = NULL;
        msg = event->body.tsx_state.type == PJSIP_EVENT_RX_MSG?event->body.tsx_state.src.rdata->msg_info.msg:event->body.tsx_state.src.tdata->msg;
        code = msg->line.status.code;
        /* Start ringback for UAC unless there's SDP */
        //UAC:user agent client UAS:user agent server
        pjsip_role_e role = info.role;
        if (role == PJSIP_ROLE_UAC && msg->body == NULL && info.media_status == PJSUA_CALL_MEDIA_NONE) {
            if (code >= 100 && code < 200) {
                [self startSuaRingBack];
            }
        }
    } else if (state == PJSIP_INV_STATE_CONFIRMED) {
        if ([self applicationWhetherForeground]) {
            if (info.role == PJSIP_ROLE_UAC) {
                [self stopSuaRingBack];
            } else {
                [self stopRingWithSpeaker];
            }
        }
    } else {
        _callID = PJSUA_INVALID_ID;
    }
}

- (void)suaOnIncomingCallWithRData:(pjsip_rx_data *)rdata withCallID:(pjsua_call_id)cid forAccountID:(pjsua_acc_id)acc_id {
    pjsua_call_info info;
    pjsua_call_get_info(cid, &info);
    
    //reject action whether there was exist an already voip-call
    if (_callID != PJSUA_INVALID_ID && _callID != cid) {
        //reject call with busy state
        pjsua_call_answer(cid, PJSIP_SC_BUSY_HERE, NULL, NULL);
        return;
    } else {
        //answer call with ring state
        pjsua_call_answer(cid, PJSIP_SC_RINGING, NULL, NULL);
    }
    
    //handle the call and make sure the call belongs to myself! acc_id that was caller's id not mine!
    NSLog(@"mine id:%zd-----caller id:%zd", self.accID, acc_id);
    _callID = cid;
    NSString *remoteEndia = [self remoteEndiaAccount];
    if (remoteEndia.length == 0 || [remoteEndia isEqual:[NSNull null]]) {
        //伪来电
        NSLog(@"收到了一个伪来电！");
        pjsua_call_answer(cid, PJSIP_SC_NOT_FOUND, NULL, NULL);
        _callID = PJSUA_INVALID_ID;
        if ([self applicationWhetherForeground]) {
            if (info.role == PJSIP_ROLE_UAC) {
                [self stopSuaRingBack];
            } else {
                [self stopRingWithSpeaker];
            }
        }
        return;
    }
    
    NSLog(@"received an incoming call...:%@", remoteEndia);
    //收到了一个来电 UI处理逻辑如下：
    [self startInComingCallUI];
}
//pjsua_call_id call_id, const pjsip_uri *target, const pjsip_event *e
- (pjsip_redirect_op)suaOnCallRedirect:(pjsua_call_id)call_id withTarget:(const pjsip_uri *)target withEvent:(const pjsip_event *)event {
    if (call_id != PJSUA_INVALID_ID && call_id == _callID) {
        return PJSIP_REDIRECT_ACCEPT_REPLACE;
    }
    return PJSIP_REDIRECT_REJECT;
}

#pragma mark == test methods for extentions ==

- (void)getBuddyCount {
    unsigned int counts = pjsua_get_buddy_count();
    NSLog(@"buddy count:%d",counts);
    //NSString *acc = @"15557365118";//sunkai
    NSString *acc = @"13656680031";//lean
    //NSString *acc = @"10086";//xiaomishu
    //NSString *acc = @"13023622337";//nanhu
    //NSString *acc = @"18657123805";//qiangge
    NSString *sipServer = [self assembleSipServer];
    NSString *targetUri = [NSString stringWithFormat:@"sips:%@@%@",acc,sipServer];
    pj_status_t status;
    char *tmp_uri = (char *)targetUri.UTF8String;
    pjsip_check_thread();
    status = pjsua_verify_url(tmp_uri);
    if (status != PJ_SUCCESS){
        NSLog(@"invalid calling uri !");
        return ;
    }
    const pj_str_t buddy_uri = pj_str((char *)targetUri.UTF8String);
    pjsua_buddy_id buddy_id = pjsua_buddy_find(&buddy_uri);
    if (buddy_id == PJSUA_INVALID_ID) {
        NSLog(@"failed to find buddy !");
    }
    pjsua_acc_id acc_ids[16];
    unsigned count = PJ_ARRAY_SIZE(acc_ids);
    status = pjsua_enum_accs(acc_ids, &count);
    if (status != PJ_SUCCESS){
        NSLog(@"failed enum ids !");
        return ;
    }
    
    /*
    pj_str_t str_method;
    pjsip_method method;
    pjsip_tx_data *tdata;
    pjsip_endpoint *endpt;
    //pj_status_t status;
    
    endpt = pjsua_get_pjsip_endpt();
    
    str_method = pjsip_options_method.name;
    pjsip_method_init_np(&method, &str_method);
    
    status = pjsua_acc_create_request(_accID, &pjsip_options_method, &buddy_uri, &tdata);
    
    status = pjsip_endpt_send_request(endpt, tdata, -1, NULL, NULL);
    if (status != PJ_SUCCESS) {
        pjsua_perror(THIS_FILE, "Unable to send request", status);
        return;
    }
    //*/
    
    pj_str_t text;
    const char *msgText = [@"Hello there!" UTF8String];
    text = pj_str((char*)msgText);
    pj_str_t to;
    const char *toText = [targetUri UTF8String];
    to = pj_str((char*)toText);
    status = pjsua_im_send(_accID, &to, NULL, &text, NULL, NULL);
    if (status != PJ_SUCCESS) {
        NSLog(@"failed to send im sms!");
        return;
    }
    
    //pjsua_acc_create_request(;, <#const pjsip_method *method#>, <#const pj_str_t *target#>, <#pjsip_tx_data **p_tdata#>)
}

#pragma mark -- iOS10+ CallKits && PushKits UI Logics--

static NSString * const FLK_SYSTEM_CALL_IDENTIFIER                      =   @"com.flk.mxt.voip-call.identifier";
static NSString * const FLK_SYSTEM_CALL_TYPE                            =   @"com.flk.mxt.voip-call.type";
static NSString * const FLK_SYSTEM_CALL_DATE                            =   @"com.flk.mxt.voip-call.date";
- (void)startInComingCallUI {
    NSString *remoteEndia = [self remoteEndiaAccount];
    if ([self applicationWhetherForeground]) {
        //reset audio category
        [self resetAudioSessionPreCall];
        //enable flag for unique call-id
        [self enableLocalVoipCallFlagWithUUID:nil];
        //start rings
        [self startRingWithSpeaker];
        PBMAINDelay(PBANIMATE_DURATION, ^{
            [self showCustomProfile4LaunchType:FLKCallLaunchTypeCalled withUsrAccount:remoteEndia];
        });
    } else {
        NSLog(@"ios version:%@", [UIDevice currentDevice].systemVersion);
        if ([self whetherSystemOperationAbove10]) {
            //系统CallKits
            PBMAINDelay(PBANIMATE_DURATION, ^{
                [self showSystemProfileWithUsrAccount:remoteEndia];
            });
        } else {
            /*
            UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
            content.title = [NSString localizedUserNotificationStringForKey:@"来电提醒" arguments:nil];
            NSString *body = PBFormat(@"您有一个来自%@的加密来电...",remoteEndia);
            content.body = [NSString localizedUserNotificationStringForKey:body arguments:nil];
            content.sound = [UNNotificationSound defaultSound];
            
            /// 4. update application icon badge number
            NSUInteger badgeValue = [UIApplication sharedApplication].applicationIconBadgeNumber;
            content.badge = [NSNumber numberWithInteger:badgeValue + 1];
            // Deliver the notification in five seconds.
            UNTimeIntervalNotificationTrigger *trigger = [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:.1f repeats:NO];
            UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:FLK_SYSTEM_CALL_IDENTIFIER content:content trigger:trigger];
            /// 3. schedule localNotification
            UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
            [center addNotificationRequest:request withCompletionHandler:^(NSError * _Nullable error) {
                if (!error) {
                    NSLog(@"add NotificationRequest succeeded!");
                }
            }];
             //*/
            if (PBIsEmpty(remoteEndia)) {
                return;
            }
            self.systemCallFiredDate = [NSDate date];
            [self enableLocalVoipCallFlagWithUUID:nil];
            NSString *nick = [self convertAccount2Nick4Account:remoteEndia];
            //local notification
            NSString *body = PBFormat(@"来自%@的加密来电...", PBIsEmpty(nick)?remoteEndia:nick);
            NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:remoteEndia, FLK_SYSTEM_CALL_IDENTIFIER, @"new", FLK_SYSTEM_CALL_TYPE, self.systemCallFiredDate, FLK_SYSTEM_CALL_DATE, nil];
            UILocalNotification *notis = [[UILocalNotification alloc] init];
            notis.repeatInterval = 0;
            notis.alertBody = body;
            notis.userInfo = info;
            NSString *soundName = UILocalNotificationDefaultSoundName;
            soundName = PBFormat(@"%@.%@",PJ_SIP_RING_FILE, PJ_SIP_RING_FILE_EXT);
            NSLog(@"local notification sound file:%@", soundName);
            notis.soundName = soundName;
            [[UIApplication sharedApplication] presentLocalNotificationNow:notis];
            //TODO:此处待验证 在后台时已经设置好界面 这里弹出不好 还是在'applicationWillEnterForeground'method中弹出
            //PBMAINDelay(PBANIMATE_DURATION*0.5, ^{
            //    [self showCustomProfile4LaunchType:FLKCallLaunchTypeCalled withUsrAccount:remoteEndia];
            //});
        }
    }
}

- (void)startOutGoingCallUI4Account:(NSString *)acc {
    PBMAINDelay(PBANIMATE_DURATION, ^{
        [self showCustomProfile4LaunchType:FLKCallLaunchTypeCaller withUsrAccount:acc];
    });
}

/**
 当通话结束时 如果在后台时判断是否需要显示未接通知
 */
- (void)whetherShouldGenerateUnAcceptCallRecord4LocalNotification {
    if (_callID == PJSUA_INVALID_ID) {
        return;
    }
    //judge account
    NSString *remoteAcc = [self remoteEndiaAccount];
    if (remoteAcc.length == 0) {
        return;
    }
    pjsua_call_info info;
    pjsip_check_thread();
    if (pjsua_call_get_info(_callID, &info) != PJ_SUCCESS) {
        return;
    }
    //电话未接通则生成未接来电
    if (info.connect_duration.sec <= 0) {
        //取消本地通知
        //[self cancelSystemVoipCallLocalNotification];
        [self generateUnAcceptLocalNotification4VoipCallAccount:remoteAcc];
    }
    /*
    FLKVoipCallRole role = FLKVoipCallRoleUAC;
    if (info.role == PJSIP_ROLE_UAS || info.role == PJSIP_UAS_ROLE) {
        role = FLKVoipCallRoleUAS;
    }
    FLKVoipCallEndState endState = [self fetchVoipCallEndState4Role:role];
    if (endState & FLKVoipCallEndStateUACCancel) {
        NSString *acc = [self remoteEndiaAccount];
        //取消本地通知
        //[self cancelSystemVoipCallLocalNotification];
        [self generateUnAcceptLocalNotification4VoipCallAccount:acc];
    }
    //*/
}

- (void)cancelSystemVoipCallLocalNotification {
    NSString *remote_acc = [self remoteEndiaAccount];
    if (remote_acc.length == 0) {
        return;
    }
    //取消本地通知
    
    UILocalNotification *notificationToCancel = nil;
    NSArray *localNotis = [[UIApplication sharedApplication] scheduledLocalNotifications];
    if (localNotis.count == 0) {
        //系统bug 获取本地通知nil
        NSLog(@"本地通知数组为空....");
        [UIApplication sharedApplication].scheduledLocalNotifications = nil;
    } else {
        for(UILocalNotification *tmpNoti in localNotis) {
            NSString *idntifier = [[tmpNoti userInfo] objectForKey:FLK_SYSTEM_CALL_IDENTIFIER];
            NSString *type = [[tmpNoti userInfo] objectForKey:FLK_SYSTEM_CALL_TYPE];
            NSDate *date = [[tmpNoti userInfo] objectForKey:FLK_SYSTEM_CALL_DATE];
            if ([type isEqualToString:@"new"] && [date isEqualToDate:self.systemCallFiredDate] && [idntifier isEqualToString:remote_acc]) {
                notificationToCancel = tmpNoti;
                break;
            }
        }
    }
    
    
    if(notificationToCancel) {
        NSLog(@"将要取消已经展示的本地通知:%@", notificationToCancel.userInfo);
        [[UIApplication sharedApplication] cancelLocalNotification:notificationToCancel];
    }
}
//生成未接来电
- (void)generateUnAcceptLocalNotification4VoipCallAccount:(NSString *)acc {
    if (acc.length == 0) {
        return;
    }
    NSString *nick = [self convertAccount2Nick4Account:acc];
    NSString *body = PBFormat(@"来自%@的未接加密来电...",PBIsEmpty(nick)?acc:nick);
    NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:acc, FLK_SYSTEM_CALL_IDENTIFIER, @"unaccept", FLK_SYSTEM_CALL_TYPE, [NSDate date], FLK_SYSTEM_CALL_DATE, nil];
    UILocalNotification *notis = [[UILocalNotification alloc] init];
    notis.repeatInterval = 0;
    notis.alertBody = body;
    notis.userInfo = info;
    //notis.soundName = UILocalNotificationDefaultSoundName;
    [[UIApplication sharedApplication] presentLocalNotificationNow:notis];
    //NSInteger badgeValue = [UIApplication sharedApplication].applicationIconBadgeNumber;
    //[UIApplication sharedApplication].applicationIconBadgeNumber = badgeValue + 1;
}

/**
 展示自定义来电、呼叫界面

 @param type 主叫／被叫
 @param acc 账号
 */
- (void)showCustomProfile4LaunchType:(FLKCallLaunchType)type withUsrAccount:(NSString *)acc {
    
    if (type ^ FLKCallLaunchTypeCaller) {
        /**
         such as:resign firstResponder in old window
         */
        if (self.voipCallProfileBlock) {
            self.voipCallProfileBlock(true);
        }
    }
    [self printlnAudioDevices];
    FLKVoipCallProfile *profile = [FLKVoipCallProfile call4Uid:acc andWithCallType:type];
    self.voipProfile = profile;
    profile.delegate = self;
    [profile launch];
}

#pragma mark ==== FLK Screen Lock Notification ===

static void screenLockStateChanged(CFNotificationCenterRef center,void* observer,CFStringRef name,const void* object,CFDictionaryRef userInfo) {
    NSString* lockstate = (__bridge NSString*)name;
    if ([lockstate isEqualToString:(__bridge  NSString*)FLKSCREEN_LOCK]) {
        NSLog(@"locked.");
        [[FLKSipService shared] screenLockEvent];
    } else {
        NSLog(@"lock state changed.");
    }
}

- (void)screenLockEvent {
    if (_callID != PJSUA_INVALID_ID && _callState == PJSIP_INV_STATE_EARLY) {
        [self didTouchHangUpWithProfile:nil];
    }
}

#pragma mark ==== FLKVoipCallProfile Delegate ====

- (voipCallQuality)fetchVoipCallQuality {
    voipCallQuality qos = voipCallQualityNone;
    pjsua_stream_stat stat = [self fetchCallStreamStat];
    int lossRate = stat.rtcp.rx.pkt > 0 ? (stat.rtcp.rx.loss*100/stat.rtcp.rx.pkt) : 100;
    if (lossRate < 5 && stat.rtcp.rtt.mean < 300000) {
        qos = voipCallQualityHigh;
    } else if (lossRate < 10 && stat.rtcp.rtt.mean < 700000) {
        qos = voipCallQualityMedium;
    } else {
        qos = voipCallQualityLow;
    }
    return qos;
}

- (NSTimeInterval)fetchVoipCallCurrentTimeInterval {
    NSTimeInterval interval = 0;
    if (_callID != PJSUA_INVALID_ID) {
        pjsua_call_info info;
        pjsip_check_thread();
        if (pjsua_call_get_info(_callID, &info) == PJ_SUCCESS) {
            interval = info.connect_duration.sec;
        };
    }
    return interval;
}

- (NSString * _Nullable)convertAccount2DisplayWithAccount:(NSString *)acc {
    return [self convertAccount2Nick4Account:acc];
}

/**
 静音与否
 */
- (void)profile:(FLKVoipCallProfile *)profile didClickMute:(BOOL)on{
    NSError * _Nullable(^block)() = ^(){
        NSError *err;
        [self adjustMicrophoneVolume2:on?0:1];
        return err;
    };
    [self excuteBlockEvent:block withCompletion:nil];
}

- (void)profile:(FLKVoipCallProfile *)profile didClickSuspend:(BOOL)on {
    NSError * _Nullable(^block)() = ^(){
        NSError *err;
        if (on) {
            [self holdonAudioCall];
        } else {
            [self releaseHoldonAudioCall];
        }
        return err;
    };
    [self excuteBlockEvent:block withCompletion:nil];
}

- (void)profile:(FLKVoipCallProfile *)profile didClickHandFree:(BOOL)on {
    NSError * _Nullable(^block)() = ^(){
        NSError *err;
        [self handsFreeModeEnable:on];
        return err;
    };
    [self excuteBlockEvent:block withCompletion:nil];
}

- (void)didTouchAcceptWithProfile:(FLKVoipCallProfile *)profile {
    NSError * _Nullable(^block)() = ^(){
        NSError *err;
        [self answerAudioCall];
        return err;
    };
    [self excuteBlockEvent:block withCompletion:nil];
}

- (void)didTouchHangUpWithProfile:(FLKVoipCallProfile *)profile {
    NSError * _Nullable(^block)() = ^(){
        NSError *err;
        
        self.whetherHangupByMySelf = true;
        
        [self hangupAudioCall4Code:PJSIP_SC_BUSY_HERE];
        return err;
    };
    [self excuteBlockEvent:block withCompletion:nil];
}

#pragma mark ==== FLKSystem voip CallKit Delegate ====

- (FLKProviderDelegate *)systemDelegate {
    if (!_systemDelegate) {
        FLKCallManager *manager = [[FLKCallManager alloc] init];
        _systemDelegate = [[FLKProviderDelegate alloc] initWithCallManager:manager];
        _systemDelegate.delegate = self;
    }
    return _systemDelegate;
}

/**
 展示系统来电界面(目前只能展示来电、接通界面 主叫界面系统还未支持)
 
 @param acc 账号
 */
- (void)showSystemProfileWithUsrAccount:(NSString *)acc {
    if (acc.length == 0) {
        NSLog(@"收到伪来电:%@", acc);
        return;
    }
    NSString *nick = [self convertAccount2Nick4Account:acc];
    NSLog(@"后台系统来电来自:%@------------", nick);
    NSUUID *uuid = [self.systemDelegate reportInComingCallWithHandle:acc withNick:nick whetherVideo:false withCompletion:^(NSError * _Nullable error) {
        NSLog(@"system report incoming call with error:%@", error);
    }];
    [self enableLocalVoipCallFlagWithUUID:uuid];
}

/**
 取消／结束 会话

 @param acc 账号
 @param completion callback block
 */
- (void)cancelSystemProfileWithUsrAccount:(NSString *)acc withCompletion:(void(^ _Nullable)(NSError * _Nullable error))completion {
    //if (acc.length == 0) {
    //    NSLog(@"收到伪账号:%@", acc);
    //    return;
    //}
    if (self.systemDelegate) {
        [self.systemDelegate reportCancelInComingCallWithHandle:acc withCompletion:completion];
    }
    //_systemDelegate.delegate = nil;
    //_systemDelegate = nil;
}

- (void)systemProviderDidReset {
    [self didTouchHangUpWithProfile:nil];
}

- (void)systemProviderDidUpdateAction:(CXAction *)action withType:(FLKSystemCallActionType)type {
    if (type & FLKSystemCallActionTypeAnswer) {
        NSLog(@"选择了接听");
        
        [self didTouchAcceptWithProfile:nil];
        [self startCustomVoipUIWhenConfirmedBySystem];
    } else if (type & FLKSystemCallActionTypeHold) {
        CXSetHeldCallAction *holdAction = (CXSetHeldCallAction *)action;
        [self profile:nil didClickSuspend:holdAction.isOnHold];
    } else if (type & FLKSystemCallActionTypeMute) {
        CXSetMutedCallAction *muteAction = (CXSetMutedCallAction *)action;
        [self profile:nil didClickMute:muteAction.isMuted];
    } else if (type & FLKSystemCallActionTypeEnd) {
        [self didTouchHangUpWithProfile:nil];
    } else if (type & FLKSystemCallActionTypeTimeout) {
        [self didTouchHangUpWithProfile:nil];
    } else if (type & FLKSystemCallActionTypeAudio) {
        CXSetMutedCallAction *muteAction = (CXSetMutedCallAction *)action;
        //系统audio session changed
        NSLog(@"系统audio session changed---------------");
        //*
         NSError * _Nullable(^block)() = ^(){
             NSError *err;
             [self setPJSuaAudioDeviceEnable:muteAction.isMuted];
             return err;
         };
         [self excuteBlockEvent:block withCompletion:nil];
         //*/
        
    } else if (type & FLKSystemCallActionTypeStart) {
        
    } else if (type & FLKSystemCallActionTypeCallIncoming) {
        CXCallAction *callAction = (CXCallAction *)action;
        [self didObservedSystemIncomingCall4UUIDString:callAction.callUUID.UUIDString];
    }
}

- (void)startCustomVoipUIWhenConfirmedBySystem {
    self.whetherCallConfirmedBySystem = true;
    /*
    NSString *remote_acc = [self remoteEndiaAccount];
    [self.systemDelegate reportConfirmInComingCallWithHandle:remote_acc withCompletion:^(NSError * _Nullable error) {
        NSLog(@"accept system call with error:%@", error.localizedDescription);
    }];
    //*/
}

#pragma mark ----- 系统来电事件
//这里设置标志位是是为了区分本地电话 和 系统电话 当有系统电话来时 此时标志位必存在 否则为自己调用callkit产生的系统事件
- (void)enableLocalVoipCallFlagWithUUID:(NSUUID * _Nullable)uuid {
    if (uuid == nil) {
        uuid = [NSUUID UUID];
    }
    //新的来电 首次记录 下次再来则挂断
    NSString *remoteAcc = [self remoteEndiaAccount];
    BOOL isOutgoing = [self whetherAliceWasCaller];
    FLKCall *call = [FLKCall callWithUUID:uuid withHandle:remoteAcc whetherOutgoing:isOutgoing];
    self.systemDelegate.currentCall = call;
}

- (void)disableLocalVoipCallFlag {
    self.systemDelegate.currentCall = nil;
}

- (void)didObservedSystemIncomingCall4UUIDString:(NSString *)uuid {
    if (uuid.length == 0) {
        return;
    }
    if (![self.systemDelegate.currentCall.uuid.UUIDString isEqualToString:uuid]) {
        NSLog(@"监听到系统来电=================");
        if (_callID != PJSUA_INVALID_ID) {
            if (self.whetherCallConfirmedBySystem) {
                [self cancelSystemProfileWithUsrAccount:self.systemDelegate.currentHandle withCompletion:^(NSError * _Nullable error) {
                    NSLog(@"挂断系统电话错误：%@", error.localizedDescription);
                }];
            }
            [self didTouchHangUpWithProfile:nil];
        }
    }
}

@end
