//
//  FLKProviderDelegate.m
//  FLKVoipCallPro
//
//  Created by nanhujiaju on 2017/3/17.
//  Copyright © 2017年 nanhujiaju. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <PBKits/PBKits.h>
#import "FLKCallManager.h"
#import "FLKSipConstants.h"
//#import "AudioController.h"
#import "FLKProviderDelegate.h"
#import <AVFoundation/AVFoundation.h>

static unsigned int const FLK_AUDIO_UNIT_TOOL_KIT                     = 0;

@implementation FLKCall

- (id)initWithUUID:(NSUUID *)uuid withHandle:(NSString *)handle whetherOutgoing:(BOOL)outgoing {
    self = [super init];
    if (self) {
        self.uuid = uuid;
        self.handle = handle;
        self.isOutgoing = outgoing;
    }
    return self;
}
+ (FLKCall *)callWithUUID:(NSUUID *)uuid withHandle:(NSString *)handle whetherOutgoing:(BOOL)outgoing {
    return [[FLKCall alloc] initWithUUID:uuid withHandle:handle whetherOutgoing:outgoing];
}

- (BOOL)isEqualToCall:(FLKCall *)call {
    if (call == nil) {
        return false;
    }
    if (call.isOutgoing != self.isOutgoing) {
        return false;
    }
    if (![call.handle isEqualToString:self.handle]) {
        return false;
    }
    if (![call.uuid.UUIDString isEqual:self.uuid.UUIDString]) {
        return false;
    }
    return true;
}

@end


@interface FLKProviderDelegate () <CXProviderDelegate, CXCallObserverDelegate>

@property (nonatomic, strong) CXProvider * provider;
@property (nonatomic, strong) CXProviderConfiguration * configuration;

#pragma mark -- system call observer
@property (nonatomic, strong) CXCallObserver * systemObserver;

#pragma mark -- system ui update transmition
@property (nonatomic, strong) CXCallController *callController;

#pragma mark -- voip call
@property (nonatomic, strong, nullable) NSUUID *currentUUID;
@property (nonatomic, copy, nullable) NSString *currentHandle;

@property (nonatomic, strong) FLKCallManager *callManager;

#if FLK_AUDIO_UNIT_TOOL_KIT
@property (nonatomic, strong, nullable) AudioController *audioController;
#endif

@end

@implementation FLKProviderDelegate

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (id)initWithCallManager:(FLKCallManager *)manager {
    self = [super init];
    if (self) {
        NSAssert(manager != nil, @"can not pass an empty value for call manager!");
        self.callManager = manager;
        [self.provider setDelegate:self queue:nil];
        if ([CXCallObserver class] != nil) {
            [self.systemObserver description];
        }
    }
    return self;
}

#pragma mark -- getter --

- (CXProviderConfiguration *)configuration {
    static CXProviderConfiguration* configInternal = nil;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *appName = [NSBundle pb_displayName];
        configInternal = [[CXProviderConfiguration alloc] initWithLocalizedName:appName];
        configInternal.supportsVideo = false;
        configInternal.maximumCallGroups = 1;
        configInternal.maximumCallsPerCallGroup = 1;
        configInternal.supportedHandleTypes = [NSSet setWithObject:@(CXHandleTypePhoneNumber)];
        //NSBundle *sipBundle = [NSBundle bundleWithURL:[[NSBundle mainBundle] URLForResource:@"sipService" withExtension:@"bundle"]];
        UIImage *iconMaskImage = [UIImage imageNamed:@"sipIcon.png"];
        NSData *iconData = UIImagePNGRepresentation(iconMaskImage);
        NSLog(@"sip icon size:%@----length:%zd", NSStringFromCGSize(iconMaskImage.size), [iconData length]);
        configInternal.iconTemplateImageData = iconData;
        configInternal.ringtoneSound = @"Ringtong.caf";
    });
    
    return configInternal;
}

- (CXProvider *)provider {
    if (!_provider) {
        _provider = [[CXProvider alloc] initWithConfiguration:self.configuration];
    }
    return _provider;
}

- (CXCallObserver *)systemObserver {
    if (!_systemObserver) {
        _systemObserver = [[CXCallObserver alloc] init];
        [_systemObserver setDelegate:self queue:dispatch_get_main_queue()];
    }
    return _systemObserver;
}

- (CXCallController *)callController {
    if (!_callController) {
        _callController = [[CXCallController alloc] initWithQueue:dispatch_get_main_queue()];
    }
    return _callController;
}

- (NSUUID *)currentUUID {
    if (!_currentUUID) {
        _currentUUID = [NSUUID UUID];
    }
    return _currentUUID;
}
#if FLK_AUDIO_UNIT_TOOL_KIT
- (AudioController *)audioController {
    if (!_audioController) {
        _audioController = [[AudioController alloc] init];
        _audioController.muteAudio = false;
    }
    return _audioController;
}

 - (void)startAudio {
     if ([self.audioController startIOUnit] != kAudioServicesNoError) {
         [self.audioController setMuteAudio:false];
         NSLog(@"failed to start audio io unit!!!");
     };
 }
 
 - (void)stopAudio {
     if ([self.audioController stopIOUnit] != kAudioSessionNoError) {
         NSLog(@"failed to stop audio io unit!!!");
     }
 }

- (void)configureAudioSession {
    [self.audioController setupAudioChain];
}
#endif

#pragma mark -- audio session configure

- (void)configureAudioSessionStart {
    // Configure the audio session
    AVAudioSession *sessionInstance = [AVAudioSession sharedInstance];
    
    // we are going to play and record so we pick that category
    NSError *error = nil;
    [sessionInstance setCategory:AVAudioSessionCategoryPlayAndRecord error:&error];
    if (error) {
        NSLog(@"%s --- failed to set audio session category:%@", __FUNCTION__, error.localizedDescription);
    }
    // set the mode to voice chat
    [sessionInstance setMode:AVAudioSessionModeVoiceChat error:&error];
    if (error) {
        NSLog(@"%s --- failed to set audio mode with error :%@", __FUNCTION__, error.localizedDescription);
    }
    //* set the buffer duration to 5 ms
    NSTimeInterval bufferDuration = .005;
    [sessionInstance setPreferredIOBufferDuration:bufferDuration error:&error];
    if (error) {
        NSLog(@"%s --- failed to active audio buffer with error:%@", __FUNCTION__, error.localizedDescription);
    }
    // set the session's sample rate
    [sessionInstance setPreferredSampleRate:44100 error:&error];
    if (error) {
        NSLog(@"%s --- failed to active audio sampleRate with error:%@", __FUNCTION__, error.localizedDescription);
    }
    //*/
    [sessionInstance setActive:true error:&error];
    if (error) {
        NSLog(@"%s --- failed to active audio active with error:%@", __FUNCTION__, error.localizedDescription);
    }
    // add interruption handler
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleInterruption:)
                                                 name:AVAudioSessionInterruptionNotification
                                               object:sessionInstance];
    // if media services are reset, we need to rebuild our audio chain
    [[NSNotificationCenter defaultCenter]	addObserver:self
                                             selector:@selector(handleMediaServerReset:)
                                                 name:AVAudioSessionMediaServicesWereResetNotification
                                               object:sessionInstance];
}

- (void)configureAudioSessionEnd {
    //[self.audioController description];
    
    // Configure the audio session
    AVAudioSession *sessionInstance = [AVAudioSession sharedInstance];
    
    // we are going to play and record so we pick that category
    NSError *error = nil;
    [sessionInstance setCategory:AVAudioSessionCategoryAmbient error:&error];
    
    // set the mode to voice chat
    //[sessionInstance setMode:AVAudioSessionModeDefault error:&error];
}

- (void)handleInterruption:(NSNotification *)notification {
    @try {
        UInt8 theInterruptionType = [[notification.userInfo valueForKey:AVAudioSessionInterruptionTypeKey] intValue];
        NSLog(@"Session interrupted > --- %s ---\n", theInterruptionType == AVAudioSessionInterruptionTypeBegan ? "Begin Interruption" : "End Interruption");
        
        if (theInterruptionType == AVAudioSessionInterruptionTypeBegan) {
            CXSetMutedCallAction *muteAction = [[CXSetMutedCallAction alloc] initWithCallUUID:self.currentUUID muted:false];
            if (self.delegate && [self.delegate respondsToSelector:@selector(systemProviderDidUpdateAction:withType:)]) {
                [self.delegate systemProviderDidUpdateAction:muteAction withType:FLKSystemCallActionTypeAudio];
            }
        }else if (theInterruptionType == AVAudioSessionInterruptionTypeEnded) {
            // make sure to activate the session
            NSError *error = nil;
            [[AVAudioSession sharedInstance] setActive:YES error:&error];
            if (nil != error) NSLog(@"AVAudioSession set active failed with error: %@", error);
            
            CXSetMutedCallAction *muteAction = [[CXSetMutedCallAction alloc] initWithCallUUID:self.currentUUID muted:true];
            if (self.delegate && [self.delegate respondsToSelector:@selector(systemProviderDidUpdateAction:withType:)]) {
                [self.delegate systemProviderDidUpdateAction:muteAction withType:FLKSystemCallActionTypeAudio];
            }
        }
    } @catch (NSException *exception) {
        //char buf[256];
        fprintf(stderr, "Error: %s (%s)\n", exception.name.UTF8String, exception.reason.UTF8String);
    } @finally {
        
    }
}

- (void)handleMediaServerReset:(NSNotification *)notification {
    NSLog(@"Media server has reset");
}

#pragma mark -- system call-ui report event --

- (NSUUID *)reportInComingCallWithHandle:(NSString *)handle withNick:(NSString * _Nullable)nick whetherVideo:(BOOL)video withCompletion:(void (^)(NSError * _Nullable))completion {
    NSError *err;
    if (handle.length == 0) {
        err = [NSError errorWithDomain:@"empty parameters!" code:-1 userInfo:nil];
        if (completion) {
            completion(err);
        }
        return nil;
    }
    
    [self configureAudioSessionStart];
    
    self.currentHandle = [handle copy];
    // Construct a CXCallUpdate describing the incoming call, including the caller.
    CXCallUpdate *update = [[CXCallUpdate alloc] init];
    update.hasVideo = false;
    update.localizedCallerName = nick;
    update.remoteHandle = [[CXHandle alloc] initWithType:CXHandleTypePhoneNumber value:handle];
    // Report the incoming call to the system
    [self.provider reportNewIncomingCallWithUUID:self.currentUUID update:update completion:^(NSError * _Nullable error) {
        /*
         Only add incoming call to the app's list of calls if the call was allowed (i.e. there was no error)
         since calls may be "denied" for various legitimate reasons. See CXErrorCodeIncomingCallError.
         */
        //[self configureAudioSessionStart];
        
        if (completion) {
            completion(error);
        }
    }];
    return self.currentUUID;
}

- (void)reportCancelInComingCallWithHandle:(NSString *)handle withCompletion:(void (^)(NSError * _Nullable))completion {
    
    //method 1
    [self.provider reportCallWithUUID:self.currentUUID endedAtDate:[NSDate date] reason:CXCallEndedReasonRemoteEnded];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(PBANIMATE_DURATION * 0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (completion) {
            completion(nil);
        }
    });
    
    //method 2
//    CXEndCallAction *endAction = [[CXEndCallAction alloc] initWithCallUUID:self.currentUUID];
//    CXTransaction *transaction = [[CXTransaction alloc] initWithAction:endAction];
//    [self requestTransaction:transaction withCompletion:completion];
    
    [self releaseCall];
}

- (void)reportConfirmInComingCallWithHandle:(NSString *)handle withCompletion:(void (^)(NSError * _Nullable))completion {
    CXAnswerCallAction *answerAction = [[CXAnswerCallAction alloc] initWithCallUUID:self.currentUUID];
    CXTransaction *transaction = [[CXTransaction alloc] initWithAction:answerAction];
    [self requestTransaction:transaction withCompletion:completion];
}

//无论何种操作都需要 话务控制器 去 提交请求 给系统
- (void)requestTransaction:(CXTransaction *)trans withCompletion:(void (^)(NSError * _Nullable))completion {
    if (trans == nil) {
        return;
    }
    [self.callController requestTransaction:trans completion:^(NSError * _Nullable error) {
        NSLog(@"end call-transaction with error:%@", error.localizedDescription);
        if (completion) {
            completion(error);
        }
    }];
}

- (void)releaseCall {
    _currentUUID = nil;
    _currentHandle = nil;
}

#pragma mark == Provider Delegate ==

- (void)providerDidReset:(CXProvider *)provider {
    NSLog(@"provider __%s", __FUNCTION__);
    if (self.delegate && [self.delegate respondsToSelector:@selector(systemProviderDidReset)]) {
        [self.delegate systemProviderDidReset];
    }
}

/**
 incoming call
 */
- (void)provider:(CXProvider *)provider performAnswerCallAction:(CXAnswerCallAction *)action {
    NSLog(@"provider __%s", __FUNCTION__);
    
    /*
     Configure the audio session, but do not start call audio here, since it must be done once
     the audio session has been activated by the system after having its priority elevated.
     */
#if FLK_AUDIO_UNIT_TOOL_KIT
    [self configureAudioSession];
#else
    [self configureAudioSessionStart];
#endif
    
    if (self.delegate && [self.delegate respondsToSelector:@selector(systemProviderDidUpdateAction:withType:)]) {
        [self.delegate systemProviderDidUpdateAction:action withType:FLKSystemCallActionTypeAnswer];
    }
    [action fulfill];
}

- (void)provider:(CXProvider *)provider performEndCallAction:(CXEndCallAction *)action {
    NSLog(@"provider __%s", __FUNCTION__);
#if FLK_AUDIO_UNIT_TOOL_KIT
    [self stopAudio];
#else
    [self configureAudioSessionEnd];
#endif
    
    if (self.delegate && [self.delegate respondsToSelector:@selector(systemProviderDidUpdateAction:withType:)]) {
        [self.delegate systemProviderDidUpdateAction:action withType:FLKSystemCallActionTypeEnd];
    }
    [action fulfill];
    
    [self releaseCall];
}

- (void)provider:(CXProvider *)provider performSetHeldCallAction:(CXSetHeldCallAction *)action {
    NSLog(@"provider __%s", __FUNCTION__);
    if (self.delegate && [self.delegate respondsToSelector:@selector(systemProviderDidUpdateAction:withType:)]) {
        [self.delegate systemProviderDidUpdateAction:action withType:FLKSystemCallActionTypeHold];
    }
    [action fulfill];
}

- (void)provider:(CXProvider *)provider performSetMutedCallAction:(CXSetMutedCallAction *)action {
    NSLog(@"provider __%s", __FUNCTION__);
    
#if FLK_AUDIO_UNIT_TOOL_KIT
    BOOL mute = action.muted;
    if (mute) {
        [self stopAudio];
    } else {
        [self startAudio];
    }
#endif
    //*/
    
    if (self.delegate && [self.delegate respondsToSelector:@selector(systemProviderDidUpdateAction:withType:)]) {
        [self.delegate systemProviderDidUpdateAction:action withType:FLKSystemCallActionTypeMute];
    }
    [action fulfill];
}

- (void)provider:(CXProvider *)provider didActivateAudioSession:(AVAudioSession *)audioSession {
#if FLK_AUDIO_UNIT_TOOL_KIT
    [self startAudio];
#endif
    
    CXSetMutedCallAction *muteAction = [[CXSetMutedCallAction alloc] initWithCallUUID:self.currentUUID muted:true];
    if (self.delegate && [self.delegate respondsToSelector:@selector(systemProviderDidUpdateAction:withType:)]) {
        [self.delegate systemProviderDidUpdateAction:muteAction withType:FLKSystemCallActionTypeAudio];
    }
}

- (void)provider:(CXProvider *)provider didDeactivateAudioSession:(nonnull AVAudioSession *)audioSession {
    /*
    CXSetMutedCallAction *muteAction = [[CXSetMutedCallAction alloc] initWithCallUUID:self.currentUUID muted:false];
    if (self.delegate && [self.delegate respondsToSelector:@selector(systemProviderDidUpdateAction:withType:)]) {
        [self.delegate systemProviderDidUpdateAction:muteAction withType:FLKSystemCallActionTypeAudio];
    }
    //*/
}

- (void)provider:(CXProvider *)provider timedOutPerformingAction:(CXAction *)action {
    NSLog(@"provider __%s", __FUNCTION__);
    if (self.delegate && [self.delegate respondsToSelector:@selector(systemProviderDidUpdateAction:withType:)]) {
        [self.delegate systemProviderDidUpdateAction:action withType:FLKSystemCallActionTypeTimeout];
    }
    [action fulfill];
}

/**
 OutgoingCall
 */
- (void)provider:(CXProvider *)provider performStartCallAction:(CXStartCallAction *)action {
    NSLog(@"provider __%s", __FUNCTION__);
    
    /*
     Configure the audio session, but do not start call audio here, since it must be done once
     the audio session has been activated by the system after having its priority elevated.
     */
#if FLK_AUDIO_UNIT_TOOL_KIT
    [self configureAudioSession];
#endif
    
    if (self.delegate && [self.delegate respondsToSelector:@selector(systemProviderDidUpdateAction:withType:)]) {
        [self.delegate systemProviderDidUpdateAction:action withType:FLKSystemCallActionTypeStart];
    }
    if (action.handle != nil) {
        [action fulfill];
    } else {
        [action fail];
    }
}

#pragma mark == CallObserver Delegate ==

- (void)callObserver:(CXCallObserver *)callObserver callChanged:(CXCall *)call {
    NSLog(@"CallKit observed an incoming call with uuid:%@------------------------", call.UUID.UUIDString);
    if (call == nil || call.UUID == nil) {
        return;
    }
    
    CXCallAction *action = [[CXCallAction alloc] initWithCallUUID:call.UUID];
    if (self.delegate && [self.delegate respondsToSelector:@selector(systemProviderDidUpdateAction:withType:)]) {
        [self.delegate systemProviderDidUpdateAction:action withType:FLKSystemCallActionTypeCallIncoming];
    }
}

@end
