//
//  PBSipServiceDelegate.h
//  PBVoipService
//
//  Created by nanhujiaju on 2017/9/11.
//  Copyright © 2017年 nanhujiaju. All rights reserved.
//

#ifndef PBSipServiceDelegate_h
#define PBSipServiceDelegate_h
#include <pjsip-ua/sip_inv.h>

NS_ASSUME_NONNULL_BEGIN

/**
 语音电话结束状态:自己取消／对方拒接／挂断／对方忙／不在服务区
 */
typedef NS_ENUM(NSUInteger, PBVoipCallEndState) {
    PBVoipCallEndStateUACCancel                                    =   1   <<  0,//主叫取消
    PBVoipCallEndStateUASCancel                                    =   1   <<  1,//被叫取消
    PBVoipCallEndStateUACHangup                                    =   1   <<  2,//主叫挂断
    PBVoipCallEndStateUASHangup                                    =   1   <<  3,//被叫挂断
    PBVoipCallEndStateRemoteBusy                                   =   1   <<  4,//对方忙
    PBVoipCallEndStateRemoteUnAccept                               =   1   <<  5,//对方未接听
    PBVoipCallEndStateRemoteUnavaliable                            =   1   <<  6,//对方无法接通
};

typedef NS_ENUM(NSUInteger, PBVoipCallRole) {
    PBVoipCallRoleUAC                                              =   1   <<  0,
    PBVoipCallRoleUAS                                              =   1   <<  1,
};

static NSString * const PB_VOIPCALL_END_KEY_UUID                               =   @"com.PB.voip-end.key.uuid";
static NSString * const PB_VOIPCALL_END_KEY_ROLE                               =   @"com.PB.voip-end.key.role";
static NSString * const PB_VOIPCALL_END_KEY_STATE                              =   @"com.PB.voip-end.key.state";
static NSString * const PB_VOIPCALL_END_KEY_ACCOUNT                            =   @"com.PB.voip-end.key.account";
static NSString * const PB_VOIPCALL_END_KEY_INTERVAL                           =   @"com.PB.voip-end.key.interval";

@protocol PBSipServiceDelegate <NSObject>

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

#endif /* PBSipServiceDelegate_h */
