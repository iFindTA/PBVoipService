//
//  FLKSipServiceDelegate.h
//  PJSip2.5.5Pro
//
//  Created by nanhujiaju on 2017/1/6.
//  Copyright © 2017年 nanhu. All rights reserved.
//

#ifndef FLKSipServiceDelegate_h
#define FLKSipServiceDelegate_h
#include <pjsip-ua/sip_inv.h>

NS_ASSUME_NONNULL_BEGIN

/**
 语音电话结束状态:自己取消／对方拒接／挂断／对方忙／不在服务区
 */
typedef NS_ENUM(NSUInteger, FLKVoipCallEndState) {
    FLKVoipCallEndStateUACCancel                                    =   1   <<  0,//主叫取消
    FLKVoipCallEndStateUASCancel                                    =   1   <<  1,//被叫取消
    FLKVoipCallEndStateUACHangup                                    =   1   <<  2,//主叫挂断
    FLKVoipCallEndStateUASHangup                                    =   1   <<  3,//被叫挂断
    FLKVoipCallEndStateRemoteBusy                                   =   1   <<  4,//对方忙
    FLKVoipCallEndStateRemoteUnAccept                               =   1   <<  5,//对方未接听
    FLKVoipCallEndStateRemoteUnavaliable                            =   1   <<  6,//对方无法接通
};

typedef NS_ENUM(NSUInteger, FLKVoipCallRole) {
    FLKVoipCallRoleUAC                                              =   1   <<  0,
    FLKVoipCallRoleUAS                                              =   1   <<  1,
};

static NSString * const FLK_VOIPCALL_END_KEY_UUID                               =   @"com.flk.voip-end.key.uuid";
static NSString * const FLK_VOIPCALL_END_KEY_ROLE                               =   @"com.flk.voip-end.key.role";
static NSString * const FLK_VOIPCALL_END_KEY_STATE                              =   @"com.flk.voip-end.key.state";
static NSString * const FLK_VOIPCALL_END_KEY_ACCOUNT                            =   @"com.flk.voip-end.key.account";
static NSString * const FLK_VOIPCALL_END_KEY_INTERVAL                           =   @"com.flk.voip-end.key.interval";

@protocol FLKSipServiceDelegate <NSObject>

@optional

/**
 called when the audio call state changed

 @param state :current call state
 */
- (void)audioCallDidChanged2State:(pjsip_inv_state)state;

/**
 return current timeinterval of current video call
 */
- (NSTimeInterval)audioCallTimeIntervalSinceAnswerState;

@end

NS_ASSUME_NONNULL_END

#endif /* FLKSipServiceDelegate_h */
