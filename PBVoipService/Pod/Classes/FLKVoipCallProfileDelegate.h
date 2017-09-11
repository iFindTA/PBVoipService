//
//  FLKVoipCallProfileDelegate.h
//  FLKVoipCallPro
//
//  Created by nanhujiaju on 2017/3/16.
//  Copyright © 2017年 nanhujiaju. All rights reserved.
//

#ifndef FLKVoipCallProfileDelegate_h
#define FLKVoipCallProfileDelegate_h

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, voipCallQuality){
    voipCallQualityNone                     = 1 << 0,
    voipCallQualityHigh                     = 1 << 1,
    voipCallQualityMedium                   = 1 << 2,
    voipCallQualityLow                      = 1 << 3
};

@class FLKVoipCallProfile;
@protocol FLKVoipCallProfileDelegate <NSObject>
@optional
/**
 点击了接通按钮
 */
- (void)didTouchAcceptWithProfile:(FLKVoipCallProfile * _Nullable)profile;
/**
 点击了挂断按钮
 */
- (void)didTouchHangUpWithProfile:(FLKVoipCallProfile * _Nullable)profile;
/**
 点击了静音按钮
 */
- (void)profile:(FLKVoipCallProfile * _Nullable)profile didClickMute:(BOOL)on;
/**
 点击了暂停按钮
 */
- (void)profile:(FLKVoipCallProfile * _Nullable)profile didClickSuspend:(BOOL)on;
/**
 点击了免提按钮
 */
- (void)profile:(FLKVoipCallProfile * _Nullable)profile didClickHandFree:(BOOL)on;

/**
 fetch quality from sipserver timely
 */
- (voipCallQuality)fetchVoipCallQuality;

/**
 电话当前时间
 */
- (NSTimeInterval)fetchVoipCallCurrentTimeInterval;

/**
 convert user's account(mobile num) to display name
 
 @param acc for user
 @return display name
 */
- (NSString * _Nullable)convertAccount2DisplayWithAccount:(NSString *)acc;

@end

NS_ASSUME_NONNULL_END

#endif /* FLKVoipCallProfileDelegate_h */
