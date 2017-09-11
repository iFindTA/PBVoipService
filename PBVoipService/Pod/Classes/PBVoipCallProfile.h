//
//  PBVoipCallProfile.h
//  PBVoipService
//
//  Created by nanhujiaju on 2017/9/11.
//  Copyright © 2017年 nanhujiaju. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "PBVoipCallProfileDelegate.h"

NS_ASSUME_NONNULL_BEGIN

/**
 界面的三种状态  主叫拨出 ／ 被叫ing ／ 通话ing
 */
typedef NS_ENUM(int, PBCallViewType) {
    PBCallViewTypeAsCaller,                        // 主叫
    PBCallViewTypeAsCallee,                        // 被叫
    PBCallViewTypeTalking,
};
/**
 voip电话发起类型
 */
typedef NS_ENUM(NSUInteger, PBCallLaunchType) {
    PBCallLaunchTypeCaller                     =   1   <<  0,//电话主叫方
    PBCallLaunchTypeCalled                     =   1   <<  1,//电话被叫方
    PBCallLaunchTypeTalking                    =   1   <<  2,//以接通状态初始化
};

/**
 电话当前状态 对应pjsip定义的电话状态pjsip_inv_state
 */
typedef NS_ENUM(NSUInteger, PBCallState) {
    PBCallStateNULL,                   /**< Before INVITE is sent or received  */
    PBCallStateCALLING,                /**< After INVITE is sent               */
    PBCallStateINCOMING,               /**< After INVITE is received.          */
    PBCallStateEARLY,                  /**< After response with To tag.        */
    PBCallStateCONNECTING,             /**< After 2xx is sent/received.	    */
    PBCallStateCONFIRMED,              /**< After ACK is sent/received.	    */
    PBCallStateDISCONNECTED,
};

/**
 电话呼叫UI 实现要与系统一致 需要实现电话状态改变的委托'PBSipServiceDelegate'
 */
@interface PBVoipCallProfile : UIViewController

@property (nonatomic, strong, nullable)UIWindow *actionWindow;

@property(nonatomic, weak) id<PBVoipCallProfileDelegate>delegate;
/**
 工厂方法创建电话呼叫／振铃／接听界面
 
 @param uid 对方uid
 @param type 主叫／被叫
 @return 电话呼叫／振铃／接听界面
 */
+ (instancetype)call4Uid:(NSString *)uid andWithCallType:(PBCallLaunchType)type;

/**
 launch启动电话页面
 */
- (void)launch;

@end

NS_ASSUME_NONNULL_END
