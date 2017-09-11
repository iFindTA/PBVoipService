//
//  FLKProviderDelegate.h
//  FLKVoipCallPro
//
//  Created by nanhujiaju on 2017/3/17.
//  Copyright © 2017年 nanhujiaju. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void(^FLKSystemCallBack)(void);

typedef NS_ENUM(NSUInteger, FLKSystemCallActionType) {
    FLKSystemCallActionTypeStart                            =   1   <<  0,//发起会话
    FLKSystemCallActionTypeAnswer                           =   1   <<  1,//接听
    FLKSystemCallActionTypeHold                             =   1   <<  2,//hold on
    FLKSystemCallActionTypeMute                             =   1   <<  3,//静音
    FLKSystemCallActionTypeEnd                              =   1   <<  4,//结束会话
    FLKSystemCallActionTypeAudio                            =   1   <<  5,//语音事件
    FLKSystemCallActionTypeTimeout                          =   1   <<  6,//超时
    FLKSystemCallActionTypeCallIncoming                     =   1   <<  7,//系统来电
};

@interface FLKCall : NSObject

@property (nonatomic, copy) NSUUID *uuid;

@property (nonatomic, assign) BOOL isOutgoing;

@property (nonatomic, copy) NSString *handle;

+ (FLKCall *)callWithUUID:(NSUUID *)uuid withHandle:(NSString *)handle whetherOutgoing:(BOOL)outgoing;

- (BOOL)isEqualToCall:(FLKCall *)call;

@end

@class FLKCallManager, CXAction;
@protocol FLKSystemProviderDelegate;
@interface FLKProviderDelegate : NSObject

/**
 weak delegate for system voip call
 */
@property (nonatomic, weak) id <FLKSystemProviderDelegate> delegate;

/**
 current handle for incoming call
 */
@property (nonatomic, copy, nullable, readonly) NSString * currentHandle;

/**
 current call for incoming/outgoing
 */
@property (nonatomic, strong, nullable) FLKCall *currentCall;

/**
 init for call provider delegate

 @param manager call manager
 @return delegate
 */
- (instancetype)initWithCallManager:(FLKCallManager *)manager;

/**
 report a voip call to system
 
 @param handle current call's account
 @param nick    for user
 @param video whether current call was video call or not
 @param completion callback block
 */
- (NSUUID *)reportInComingCallWithHandle:(NSString *)handle withNick:(NSString * _Nullable)nick whetherVideo:(BOOL)video withCompletion:(void(^ _Nullable)(NSError * _Nullable error))completion;

/**
 report to system to cancel current voip call-UI

 @param handle current call's account
 @param completion callback block
 */
- (void)reportCancelInComingCallWithHandle:(NSString *)handle withCompletion:(void(^ _Nullable)(NSError * _Nullable error))completion;

/**
 report to system to confirm the current voip call-ui

 @param handle current call's account
 @param completion callback block
 */
- (void)reportConfirmInComingCallWithHandle:(NSString *)handle withCompletion:(void(^ _Nullable)(NSError * _Nullable error))completion;

@end

@protocol FLKSystemProviderDelegate <NSObject>

@optional

/**
 reset for provider
 */
- (void)systemProviderDidReset;

/**
 update system-ui action

 @param action for voip call
 @param type for action
 */
- (void)systemProviderDidUpdateAction:(CXAction *)action withType:(FLKSystemCallActionType)type;

@end

NS_ASSUME_NONNULL_END
