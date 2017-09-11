//
//  PBProviderDelegate.h
//  PBVoipService
//
//  Created by nanhujiaju on 2017/9/11.
//  Copyright © 2017年 nanhujiaju. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void(^PBSystemCallBack)(void);

typedef NS_ENUM(NSUInteger, PBSystemCallActionType) {
    PBSystemCallActionTypeStart                            =   1   <<  0,//发起会话
    PBSystemCallActionTypeAnswer                           =   1   <<  1,//接听
    PBSystemCallActionTypeHold                             =   1   <<  2,//hold on
    PBSystemCallActionTypeMute                             =   1   <<  3,//静音
    PBSystemCallActionTypeEnd                              =   1   <<  4,//结束会话
    PBSystemCallActionTypeAudio                            =   1   <<  5,//语音事件
    PBSystemCallActionTypeTimeout                          =   1   <<  6,//超时
    PBSystemCallActionTypeCallIncoming                     =   1   <<  7,//系统来电
};

@interface PBCall : NSObject

@property (nonatomic, copy) NSUUID *uuid;

@property (nonatomic, assign) BOOL isOutgoing;

@property (nonatomic, copy) NSString *handle;

+ (PBCall *)callWithUUID:(NSUUID *)uuid withHandle:(NSString *)handle whetherOutgoing:(BOOL)outgoing;

- (BOOL)isEqualToCall:(PBCall *)call;

@end

@class PBCallManager, CXAction;
@protocol PBSystemProviderDelegate;
@interface PBProviderDelegate : NSObject

/**
 weak delegate for system voip call
 */
@property (nonatomic, weak) id <PBSystemProviderDelegate> delegate;

/**
 current handle for incoming call
 */
@property (nonatomic, copy, nullable, readonly) NSString * currentHandle;

/**
 current call for incoming/outgoing
 */
@property (nonatomic, strong, nullable) PBCall *currentCall;

/**
 init for call provider delegate
 
 @param manager call manager
 @return delegate
 */
- (instancetype)initWithCallManager:(PBCallManager *)manager;

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

@protocol PBSystemProviderDelegate <NSObject>

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
- (void)systemProviderDidUpdateAction:(CXAction *)action withType:(PBSystemCallActionType)type;

@end

NS_ASSUME_NONNULL_END
