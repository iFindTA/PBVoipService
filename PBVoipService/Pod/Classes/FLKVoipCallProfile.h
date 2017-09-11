//
//  FLKVoipCallProfile.h
//  voipCall
//
//  Created by nanhujiaju on 2017/3/15.
//  Copyright © 2017年 nanhujiaju. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "FLKVoipCallProfileDelegate.h"

NS_ASSUME_NONNULL_BEGIN

/**
 界面的三种状态  主叫拨出 ／ 被叫ing ／ 通话ing
 */
typedef NS_ENUM(int, FLKCallViewType) {
    FLKCallViewTypeAsCaller,                        // 主叫
    FLKCallViewTypeAsCallee,                        // 被叫
    FLKCallViewTypeTalking,
};
/**
 voip电话发起类型
 */
typedef NS_ENUM(NSUInteger, FLKCallLaunchType) {
    FLKCallLaunchTypeCaller                     =   1   <<  0,//电话主叫方
    FLKCallLaunchTypeCalled                     =   1   <<  1,//电话被叫方
    FLKCallLaunchTypeTalking                    =   1   <<  2,//以接通状态初始化
};

/**
 电话当前状态 对应pjsip定义的电话状态pjsip_inv_state
 */
typedef NS_ENUM(NSUInteger, FLKCallState) {
    FLKCallStateNULL,                   /**< Before INVITE is sent or received  */
    FLKCallStateCALLING,                /**< After INVITE is sent               */
    FLKCallStateINCOMING,               /**< After INVITE is received.          */
    FLKCallStateEARLY,                  /**< After response with To tag.        */
    FLKCallStateCONNECTING,             /**< After 2xx is sent/received.	    */
    FLKCallStateCONFIRMED,              /**< After ACK is sent/received.	    */
    FLKCallStateDISCONNECTED,
};

@class FLKVoipCallProfile;

/**
 电话呼叫UI 实现要与系统一致 需要实现电话状态改变的委托'FLKSipServiceDelegate'
 */
@interface FLKVoipCallProfile : UIViewController

@property (nonatomic, strong, nullable)UIWindow *actionWindow;

@property(nonatomic, weak) id<FLKVoipCallProfileDelegate>delegate;
/**
 工厂方法创建电话呼叫／振铃／接听界面

 @param uid 对方uid
 @param type 主叫／被叫
 @return 电话呼叫／振铃／接听界面
 */
+ (instancetype)call4Uid:(NSString *)uid andWithCallType:(FLKCallLaunchType)type;

/**
 launch启动电话页面
 */
- (void)launch;

@end

NS_ASSUME_NONNULL_END
