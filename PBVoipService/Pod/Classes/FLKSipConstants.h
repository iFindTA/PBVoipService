//
//  FLKSipConstants.h
//  FLKVoipCallPro
//
//  Created by nanhujiaju on 2017/1/8.
//  Copyright © 2017年 nanhujiaju. All rights reserved.
//

#ifndef FLKSipConstants_h
#define FLKSipConstants_h

/* handle this for build time */
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_10_0
#import <CallKit/CallKit.h>
#endif
#ifndef FLK_CALLKIT_ENABLE
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_10_0
#define FLK_CALLKIT_ENABLE              1
#else
#define FLK_CALLKIT_ENABLE              0
#endif
#endif

#define THIS_FILE                                                           "FLKSipService.m"
static NSString * const      PJ_SIP_THREAD                              =   @"com.flk.pjsua-thread.io";
static const   char *        PJ_SIP_POOL                                =   "com.flk.pjsua-pool.io";
static NSString * const      PJ_SIP_SERVER_HOST                         =   @"112.74.77.9";
static uint64_t const        PJ_SIP_SERVER_PORT                         =   8443;
static NSString * const      PJ_SIP_BACKUP_SERVER                       =   @"talk.mihuatong.com:8443";
static NSString * const      PJ_SIP_RING_FILE                           =   @"call";
static NSString * const      PJ_SIP_RING_FILE_EXT                       =   @"caf";

/* Ringtones                US              UK  */
#define RINGBACK_FREQ1	    440         /* 400 */
#define RINGBACK_FREQ2	    480         /* 450 */
#define RINGBACK_ON         2000        /* 400 */
#define RINGBACK_OFF	    4000        /* 200 */
#define RINGBACK_CNT	    1           /* 2   */
#define RINGBACK_INTERVAL   4000        /* 2000 */

#define RING_FREQ1          800
#define RING_FREQ2          640
#define RING_ON             200
#define RING_OFF            100
#define RING_CNT            3
#define RING_INTERVAL	    3000

/**
 此通知是为了与其他模块解耦合(主要是appDelegate) 中收到voip push时 自动启动/关闭（用户cancel）／结束 sip服务
 */
FOUNDATION_EXTERN NSString * const FLK_VOIPCALL_DID_RECEIVED_INCOMING_PUSH;


/**
 枚举类型 voipCall接收到呼叫时app所处于的状态
 */
typedef NS_ENUM(NSUInteger, FLKVoipCallRisePoint) {
    FLKVoipCallRisePointActive                          =   1   <<  0,
    FLKVoipCallRisePointUnActive                        =   1   <<  1,
};

#endif /* FLKSipConstants_h */
