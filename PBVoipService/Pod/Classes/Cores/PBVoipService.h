//
//  PBVoipService.h
//  PBVoipService
//
//  Created by nanhujiaju on 2017/9/11.
//  Copyright © 2017年 nanhujiaju. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <pjsua-lib/pjsua.h>
#import "PBSipServiceDelegate.h"

NS_ASSUME_NONNULL_BEGIN

typedef struct {
    /* release pool */
    pj_pool_t                       *               pool;
    /* the real config */
    pjsua_config                                    cfg;
    /* media configure */
    pjsua_media_config                              media_cfg;
    pjmedia_port                    *               ringback_port;
    /* call settings */
    pjsua_call_setting                              call_cfg;
    
    /* transport */
    pjsip_transport                                 transport;
    pjsua_transport_config                          tcp_cfg;
    pjsua_transport_config                          rtp_cfg;
    
    /* log info */
    pjsua_logging_config                            log_cfg;
    
    /* call record id */
    pjsua_recorder_id                               record_id;
    
    /* ring back */
    pj_bool_t                                       ringback_on;
    pjsua_conf_port_id                              ringback_slot;
    
    /* wether ring on & sound id */
    BOOL                                            ring_on;
    SystemSoundID                                   ring_soundID;
    
} pjsua_app_config_t;

#pragma mark -- sip configuration

@interface PBSipConfigure : NSObject

/**
 server host
 */
@property (nonatomic, copy, readonly) NSString * host;

/**
 server port
 */
@property (nonatomic, assign, readonly) uint64_t port;

/**
 the sip ring file full name, such as: ring26.caf
 */
@property (nonatomic, copy, readonly) NSString * ringFile;

/**
 the default configure for PB
 */
+ (PBSipConfigure *)defaultConfiguration;

/**
 generate configuration with host:port
 
 @param host the sip server host
 @param port the sip server port
 @param ringFile the sip server ring file full name, default is ring26.caf
 @return the configuration
 */
+ (PBSipConfigure *)configureWithServerHost:(NSString *)host withPort:(uint64_t)port withRingFile:(NSString * _Nullable)ringFile;

@end

#pragma mark -- sip service --
//号码转换为显示的名字
typedef NSString * _Nullable(^PBVoipConvertDisplayBlock)(NSString * account);


/**
 通话记录的回调
 */
typedef void(^_Nullable PBVoipCallbackBlock)(NSDictionary * _Nullable error);

/**
 profile for voip call whether show
 */
typedef void(^PBVoipCallProfileBlock)(BOOL show);

/**
 是否允许sip服务断网（在有网的情况下）重联 如果用户注销则不用重联
 */
typedef BOOL(^PBVoipServiceRestartBlock)(void);

@interface PBVoipService : NSObject

/**
 the call id
 */
@property (assign, readonly) pjsua_call_id callID;

/**
 the usr account id
 */
@property (assign, readonly) pjsua_acc_id accID;

/**
 the configure for app
 */
@property (assign, readonly) pjsua_app_config_t app_cfg;

/**
 the current call state
 */
@property (assign, readonly) pjsip_inv_state callState;

/**
 async operation queue
 */
@property (nonatomic, readonly) dispatch_queue_t sipServiceQueue;

/**
 sip service delegate
 */
@property (nonatomic, weak) id <PBSipServiceDelegate> delegate;

/**
 singletone mode
 
 @return the instance
 */
+ (PBVoipService *)shared;

/**
 start sip connect to server
 
 @discussion 此方法其实是只有用户登录时才会要调取的 其他情形下后台自启动的调用用另外方法启动@see:'outterAutoStartSipServiceWithCompletion:'
 
 @param config sip configurations
 @param completion the callback block
 */
- (void)startWithConfiguration:(PBSipConfigure *)config withCompletion:(void(^_Nullable)(NSError * _Nullable error))completion;

/**
 start sip server automaticly
 
 @param completion the callback block
 */
- (void)outterAutoStartSipServiceWithCompletion:(void(^_Nullable)(NSError * _Nullable error))completion;
- (void)startSipServiceFromBackgroundModeWithCompletion:(void (^_Nullable)(NSError * _Nullable error))completion;

/**
 stop and disconnect to server and un-register user from sip server
 
 @param completion the callback block
 */
- (void)outterStopSipServiceAndResignAuthorizedWithCompletion:(void(^_Nullable)(NSError *_Nullable error))completion;

/**
 query wether sip server avaliable
 
 @return :the result
 */
- (BOOL)serviceAvaliable;

/**
 whether sip service running(link && user register)
 */
- (BOOL)whetherSipServiceRunning;

#pragma mark -- audio device settings --

/**
 adjust the volume of microphone, value can be 0~1
 
 @param v default was the same with device
 */
- (BOOL)adjustMicrophoneVolume2:(float)v;

/**
 adjust the volume of speaker, value can be 0~1
 
 @param v default was the same with device
 */
- (BOOL)adjustSpeakerVolume2:(float)v;

/**
 wether enable hands-free mode
 
 @param enable wether enable
 @return result
 */
- (BOOL)handsFreeModeEnable:(BOOL)enable;

#pragma mark -- authorization user --

/**
 add sip account to sip server online
 
 @param acc        system account, such as mobile num
 @param pwd        system password
 @param completion block
 
 */
- (void)autherizeUsr:(NSString *)acc withPwd:(NSString *)pwd withCompletion:(void(^_Nullable)(NSError * _Nullable error))completion;

#pragma mark -- start voip call --

/**
 audio call method
 
 @param acc usr to be called
 */
- (void)startVoipCall2UserAccount:(NSString *)acc withCompletion:(void (^_Nullable)(NSError * _Nullable err))completion;

/**
 取消／结束 会话
 
 @param acc 账号
 @param completion callback block
 */
- (void)cancelSystemProfileWithUsrAccount:(NSString *)acc withCompletion:(void(^_Nullable)(NSError * _Nullable error))completion;

/**
 handle voip call callback event
 */
- (void)registerVoipCallbackEventHandler:(_Nullable PBVoipCallbackBlock)completion;

/**
 handle voip call convert user's account to display name
 
 @param completion callback event
 */
- (void)registerVoipCallConvertDisplayEventHandler:(_Nullable PBVoipConvertDisplayBlock)completion;

/**
 handle voip call profile whether show or not, such as resignFirstResponder for current window
 
 @param completion callback event
 */
- (void)registerVoipCallProfileShowEventHandler:(_Nullable PBVoipCallProfileBlock)completion;

/**
 handle voip service re-start or not, default was true
 
 @param completion callback event
 */
- (void)registerVoipServiceShouldRestartWhenNetworkAvailable:(_Nullable PBVoipServiceRestartBlock)completion;

#pragma mark -- auto test extentions --

- (void)getBuddyCount;

/**
 get the remote endian sip account
 
 @param sip :<sips:10086@112.74.77.9>
 
 @return 10086
 */
- (NSString * _Nullable)unitTest2FetchRemoteEndianAccount4Sip:(NSString *)sip;

- (NSString * _Nullable)unitTest2FetchSipBunbleResource;

@end

NS_ASSUME_NONNULL_END
