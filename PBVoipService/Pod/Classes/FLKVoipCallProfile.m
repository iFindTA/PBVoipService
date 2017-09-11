//
//  FLKVoipCallProfile.m
//  voipCall
//
//  Created by nanhujiaju on 2017/3/15.
//  Copyright © 2017年 nanhujiaju. All rights reserved.
//

#import "FLKVoipCallProfile.h"
#import <PBKits/PBKits.h>
#import <Masonry/Masonry.h>
#import "FLKSipService.h"

void getPermissionFromAppSetting(NSString *title,UIViewController *vc){
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:title message:@"请到手机设置中开启相关权限" preferredStyle:UIAlertControllerStyleAlert];
    [alertController addAction: [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
    }]];
    
    [alertController addAction: [UIAlertAction actionWithTitle:@"去设置" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
        if ([[UIDevice currentDevice].systemVersion intValue] >= 10) {
            [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString] options:@{} completionHandler:nil];
        }else{
            [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString]];
        }
    }]];
    [vc presentViewController:alertController animated:YES completion:nil];
}

BOOL hasMicrophoneAuthorization(){
    static BOOL gRecordPermissionGranted = YES;
    if ([[UIDevice currentDevice].systemVersion intValue]  >= 7) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            [[AVAudioSession sharedInstance] requestRecordPermission:^(BOOL granted) {
                gRecordPermissionGranted = granted;
            }];
        });
    }
    return gRecordPermissionGranted;
}

typedef NS_ENUM(NSUInteger, callButtonType){
    callButtonTypeMute              =   1 << 0,
    callButtonTypeSuspend           =   1 << 1,
    callButtonTypeHangFree          =   1 << 2, // 免提
    callButtonTypeHangUpOn          =   1 << 3, // 挂断
    callButtonTypeAccept            =   1 << 4, // 接听
};

@interface FLKVoipCallProfile ()<FLKSipServiceDelegate>

@property (nonatomic, copy) NSString                 * uid;
@property (nonatomic, assign) FLKCallLaunchType      launchType;
@property (nonatomic, strong) UILabel                * titleL;
@property (nonatomic, strong) UILabel                * stateDescribeL;
@property (nonatomic, strong) UIView                 * buttonBackV;
@property (nonatomic, strong) UIButton               * muteBut;      // 静音按钮
@property (nonatomic, strong) UIButton               * suspendBut;   // 暂停按钮
@property (nonatomic, strong) UIButton               * handFreeBut;  // 免提按钮
@property (nonatomic, strong) UIButton               * hangUpBut;    // 挂断按钮
@property (nonatomic, strong) UILabel                * showQualityLabel; // 当前通话质量
@property (nonatomic, assign) FLKCallViewType        callViewType;   // 当前电话状态
@property (nonatomic, assign) BOOL                   muteButisSelected;
@property (nonatomic, assign) BOOL                   suspendButisSelected;
@property (nonatomic, assign) BOOL                   handFreeButisSelected;
@property (nonatomic, assign) int                    callDuration;   // in second
@property (nonatomic, strong) UIView                * inCommingbottomView;
@property (nonatomic, strong) UIButton              * refuseButton;
@property (nonatomic, strong) UIButton              * acceptButton;
@property (nonatomic, strong) UILabel               * refuseLabel;
@property (nonatomic, strong) UILabel               * acceptLabel;
@property (nonatomic, strong) NSTimer               * timer;        // 计时器
@property (nonatomic, assign) BOOL                  willBeDismiss;  // 将要退出
@property (nonatomic, assign) voipCallQuality       currentQuality; // 当前通话质量
@property (nonatomic, assign) pjsip_inv_state       lastState;      //  保存上次状态来判断  对方拒接／对方挂断
@property (nonatomic, assign) BOOL                  isHangUpBySelf; // 判断是否是自己点击了挂断
@property (nonatomic, strong) UILabel               * endTipView;   //通话结束提示  （对方拒接）
@property (nonatomic, assign) SystemSoundID         soundFileObject;
@end


#define margin                                  PBSCREEN_WIDTH * 0.1
#define buttonW                                 (PBSCREEN_WIDTH -(1.5*margin)*2 - 40) / 3

@implementation FLKVoipCallProfile
-(void)dealloc{

}
-(void)releaseTimer{
    if (_timer) {
        if ([_timer isValid]) {
            [_timer invalidate];
        }
        _timer = nil;
    }
}
-(NSTimer *)timer{
    if (!_timer) {
        _timer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(updateCallDuration:) userInfo:nil repeats:YES];
        [[NSRunLoop currentRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
    }
    return _timer;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor grayColor];
    _timer = [[NSTimer alloc]init];
    
    UIImageView *bgImgView = [[UIImageView alloc] initWithFrame:self.view.bounds];
    bgImgView.image = [UIImage imageNamed:@"back4test"];
    bgImgView.tag = 100;
    [self.view addSubview:bgImgView];
    UIToolbar *toolbar = [[UIToolbar alloc] initWithFrame:self.view.frame];
    toolbar.barStyle = UIBarStyleBlackTranslucent;
    [bgImgView addSubview:toolbar];
    
    // 根据type判断 界面类型
    self.callViewType = self.launchType&FLKCallLaunchTypeCaller?FLKCallViewTypeAsCaller:FLKCallViewTypeAsCallee;
    
    FLKCallViewType viewType;
    if (self.launchType & FLKCallLaunchTypeCaller) {
        viewType = FLKCallViewTypeAsCaller;
    }else if (self.launchType & FLKCallLaunchTypeCalled){
        viewType = FLKCallViewTypeAsCallee;
    }else if (self.launchType & FLKCallLaunchTypeTalking){
        viewType = FLKCallViewTypeTalking;
    }
    _callViewType = viewType;
    
    [self initUI];
    [self updateContent];
}

-(instancetype)initwithUid:(NSString *)uid andWithCallType:(FLKCallLaunchType)type{
    if([super init]){
        self.uid = uid;
        self.launchType = type;
        FLKSipService *sipServer = [FLKSipService shared];
        sipServer.delegate = self;
        [self initTipAudio];
        [UIDevice currentDevice].proximityMonitoringEnabled = YES;
    }
    return self;
}
- (void)initTipAudio{
    _soundFileObject = 0;
    NSString * fileExtPath = [NSString stringWithFormat:@"audio/%@",@"close.wav"];
    NSString *ringFilePath = [[self.sipBundle resourcePath] stringByAppendingPathComponent:fileExtPath];
    NSURL *soundURL = [NSURL fileURLWithPath:ringFilePath];
    CFURLRef soundFileURLRef = (__bridge CFURLRef)soundURL;
    AudioServicesCreateSystemSoundID(soundFileURLRef, &_soundFileObject);
}
+ (instancetype)call4Uid:(NSString *)uid andWithCallType:(FLKCallLaunchType)type{
    FLKVoipCallProfile * profile = [[FLKVoipCallProfile alloc] initwithUid:uid andWithCallType:type];
    return profile;
}
- (NSBundle *)sipBundle {
    return [NSBundle bundleWithURL:[[NSBundle mainBundle] URLForResource:@"sipService" withExtension:@"bundle"]];
}

- (NSString * _Nullable)convertAccount2DisplayWithAccount:(NSString *)acc {
    NSString *displayName = nil;
    if (self.delegate && [self.delegate respondsToSelector:@selector(convertAccount2DisplayWithAccount:)]) {
        displayName = [self.delegate convertAccount2DisplayWithAccount:acc];
    }
    return displayName;
}

-(void)initUI{
    
    _titleL = [[UILabel alloc]init];
    _titleL.font = [UIFont systemFontOfSize:35.0];
    _titleL.textColor = [UIColor whiteColor];
    _titleL.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:_titleL];
    
    _stateDescribeL = [[UILabel alloc]init];
    _stateDescribeL.font = [UIFont systemFontOfSize:17.0];
    _stateDescribeL.textColor = [UIColor whiteColor];
    _stateDescribeL.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:_stateDescribeL];
    
    _showQualityLabel = [[UILabel alloc]init];
    _showQualityLabel.font = [UIFont systemFontOfSize:17.0];
    _showQualityLabel.textColor = [UIColor whiteColor];
    _showQualityLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:_showQualityLabel];
    
    NSString *defaultInfo = @"通话结束";
    NSAttributedString *attrInfo = [self fetchHeadAndTailIntentStyle4Text:defaultInfo];
    _endTipView = [[UILabel alloc]init];
    _endTipView.backgroundColor = [UIColor blackColor];
    _endTipView.textAlignment = NSTextAlignmentCenter;
//    _endTipView.textColor = [UIColor whiteColor];
//    _endTipView.font = [UIFont systemFontOfSize:15.0];
    _endTipView.layer.cornerRadius = 4;
    _endTipView.layer.masksToBounds = YES;
    _endTipView.attributedText = attrInfo;
    _endTipView.hidden = YES;
    
    [self.view addSubview:_endTipView];
    
    
    _buttonBackV = [[UIView alloc]init];
    [self.view addSubview:_buttonBackV];
    
    _hangUpBut = [[UIButton alloc]init];
    _hangUpBut.layer.cornerRadius = buttonW/2;
    _hangUpBut.backgroundColor = [UIColor colorWithRed:233.0/255 green:63.0/255 blue:51.0/255 alpha:1];
    [_hangUpBut setImage:[UIImage imageNamed:@"call_hangUp.png"] forState:UIControlStateNormal];
    _hangUpBut.tag = callButtonTypeHangUpOn;
    [_hangUpBut addTarget:self action:@selector(clickButton:) forControlEvents:UIControlEventTouchUpInside];
    [_buttonBackV addSubview:_hangUpBut];

    

    
    _inCommingbottomView = [[UIView alloc]init];
//    _inCommingbottomView.backgroundColor = [UIColor orangeColor];
    [self.view addSubview:_inCommingbottomView];
    
    
    _refuseButton = [[UIButton alloc]init];
    _refuseButton.layer.cornerRadius = buttonW/2;
    _refuseButton.backgroundColor = [UIColor colorWithRed:233.0/255 green:63.0/255 blue:51.0/255 alpha:1];
    [_refuseButton setImage:[UIImage imageNamed:@"call_accept.png"] forState:UIControlStateNormal];
    _refuseButton.tag = callButtonTypeHangUpOn;
    [_refuseButton addTarget:self action:@selector(clickButton:) forControlEvents:UIControlEventTouchUpInside];
    [_inCommingbottomView addSubview:_refuseButton];
    

    _refuseLabel = [UILabel new];
    [_refuseLabel setTextColor:[UIColor whiteColor]];
    [_refuseLabel setFont:[UIFont systemFontOfSize:16]];
    [_refuseLabel setTextAlignment:NSTextAlignmentCenter];
    [_refuseLabel setText:@"拒绝"];
    [_inCommingbottomView addSubview:_refuseLabel];
    
    
    _acceptButton = [[UIButton alloc]init];
    _acceptButton.layer.cornerRadius = buttonW/2;
    _acceptButton.backgroundColor = [UIColor colorWithRed:90.0/255 green:170.0/255 blue:98.0/255 alpha:1];
    [_acceptButton setImage:[UIImage imageNamed:@"call_hangUp.png"] forState:UIControlStateNormal];
    _acceptButton.tag = callButtonTypeAccept;
    [_acceptButton addTarget:self action:@selector(clickButton:) forControlEvents:UIControlEventTouchUpInside];
    [_inCommingbottomView addSubview:_acceptButton];
    
    
    _acceptLabel = [UILabel new];
    [_acceptLabel setText:@"接受"];
    [_acceptLabel setFont:[UIFont systemFontOfSize:16]];
    [_acceptLabel setTextColor:[UIColor whiteColor]];
    [_acceptLabel setTextAlignment:NSTextAlignmentCenter];
    [_inCommingbottomView addSubview:_acceptLabel];
    

    NSArray *imgArr = @[@"mute",@"suspend",@"handFree"];
    NSArray *labArr = @[@"静音",@"暂停",@"免提"];
    for(int j = 0 ;j<imgArr.count;j++) {
        UIView *itemView = [[UIView alloc]init];
        UIButton *but = [[UIButton alloc]init];
        NSString *imgName = imgArr[j];
        [but setBackgroundImage:[UIImage imageNamed:[NSString stringWithFormat:@"%@_off",imgName]] forState:UIControlStateNormal];
        but.tag = j;
        [but addTarget:self action:@selector(clickButton:) forControlEvents:UIControlEventTouchUpInside];
        if (j == 0) {
            but.tag = callButtonTypeMute;
            _muteBut = but;
        }else if (j == 1){
            but.tag = callButtonTypeSuspend;
            _suspendBut = but;
//            _suspendBut.alpha = 0.2;
//            _suspendBut.enabled = NO;
        }else if (j == 2){
            but.tag = callButtonTypeHangFree;
            _handFreeBut = but;
        }
        UILabel *lab = [[UILabel alloc]init];
        [lab setFont:[UIFont boldSystemFontOfSize:13.0]];
        [lab setTextAlignment:NSTextAlignmentCenter];
        [lab setTextColor:[UIColor whiteColor]];
        [lab setText:labArr[j]];
        [itemView addSubview:but];
        [itemView addSubview:lab];
        [_buttonBackV addSubview:itemView];
        if (j == 1) {
//            lab.alpha = 0.2;
//            lab.enabled = NO;
        }

        [itemView mas_remakeConstraints:^(MASConstraintMaker *make) {
            make.top.equalTo(_buttonBackV).offset(10);
            make.left.mas_equalTo(j*(buttonW+20));
            make.size.mas_equalTo(CGSizeMake(buttonW,buttonW+30));
        }];
        
        [but mas_remakeConstraints:^(MASConstraintMaker *make) {
            make.top.equalTo(itemView);
            make.left.equalTo(itemView);
            make.bottom.equalTo(itemView).offset(-30);
            make.right.equalTo(itemView);
        }];
        [lab mas_remakeConstraints:^(MASConstraintMaker *make) {
            make.top.equalTo(but.mas_bottom).offset(10);
            make.left.equalTo(but.mas_left);
            make.bottom.equalTo(itemView.mas_bottom);
            make.right.equalTo(but.mas_right);
        }];
    }
}
-(void)viewWillLayoutSubviews{
    [super viewWillLayoutSubviews];
    
    [_titleL mas_remakeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.view).offset(1.5*margin);
        make.left.equalTo(self.view).offset(margin);
        make.right.equalTo(self.view).offset(-margin);
        make.height.mas_equalTo(40);
    }];
    [_stateDescribeL mas_remakeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(_titleL.mas_bottom);
        make.left.right.equalTo(_titleL);
        make.height.mas_equalTo(30);
    }];
    [_showQualityLabel mas_remakeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(_stateDescribeL.mas_bottom);
        make.left.right.equalTo(_titleL);
        make.height.mas_equalTo(40);
    }];
    
    [_buttonBackV mas_remakeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(self.view).offset(1.5*margin);
        make.right.equalTo(self.view).offset(-1.5*margin);
        make.bottom.equalTo(self.view).offset(-margin);
        make.height.mas_equalTo(PBSCREEN_HEIGHT/2);
    }];
    
    [_inCommingbottomView mas_remakeConstraints:^(MASConstraintMaker *make) {
        make.top.left.right.height.equalTo(_buttonBackV);
    }];
    
    [_endTipView mas_remakeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.view.mas_bottom).offset(-200);
        make.centerX.equalTo(_showQualityLabel.mas_centerX);
        make.height.mas_equalTo(20);
    }];
    
    [_refuseButton mas_remakeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(_inCommingbottomView);
        make.bottom.equalTo(_inCommingbottomView).offset(-30);
        make.size.mas_equalTo(CGSizeMake(buttonW, buttonW));
    }];
    
    [_refuseLabel mas_remakeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(_refuseButton.mas_bottom);
        make.left.right.equalTo(_refuseButton);
        make.height.mas_equalTo(30);
    }];
    
    [_acceptButton mas_remakeConstraints:^(MASConstraintMaker *make) {
        make.right.equalTo(_inCommingbottomView);
        make.bottom.equalTo(_inCommingbottomView).offset(-30);
        make.size.mas_equalTo(CGSizeMake(buttonW, buttonW));
    }];
    
    [_acceptLabel mas_remakeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(_acceptButton.mas_bottom);
        make.left.right.equalTo(_acceptButton);
        make.height.mas_equalTo(30);
    }];
    
    [_hangUpBut mas_remakeConstraints:^(MASConstraintMaker *make) {
        make.bottom.equalTo(_buttonBackV);
        make.size.mas_equalTo(buttonW);
        make.centerX.equalTo(_buttonBackV.mas_centerX);
    }];
}

#pragma mark ======= click UI  button ========

-(void)clickButton:(UIButton *)sender{
    if (sender.tag & callButtonTypeMute) {
        _muteButisSelected = !_muteButisSelected;
        if (_muteButisSelected) {
            [_muteBut setBackgroundImage:[UIImage imageNamed:@"mute_on.png"] forState:UIControlStateNormal];
        }else{
            [_muteBut setBackgroundImage:[UIImage imageNamed:@"mute_off.png"] forState:UIControlStateNormal];
        }
        if ([self.delegate respondsToSelector:@selector(profile:didClickMute:)]) {
            [self.delegate profile:self didClickMute:_muteButisSelected];
        }
    }else if (sender.tag & callButtonTypeSuspend){
        _suspendButisSelected = !_suspendButisSelected;
        if (_suspendButisSelected) {
            [_suspendBut setBackgroundImage:[UIImage imageNamed:@"suspend_on.png"] forState:UIControlStateNormal];
        }else{
            [_suspendBut setBackgroundImage:[UIImage imageNamed:@"suspend_off.png"] forState:UIControlStateNormal];
        }
        if ([self.delegate respondsToSelector:@selector(profile:didClickSuspend:)]) {
            [self.delegate profile:self didClickSuspend:_suspendButisSelected];
        }
    }else if (sender.tag & callButtonTypeHangFree){
        _handFreeButisSelected = !_handFreeButisSelected;
        if (_handFreeButisSelected) {
            [_handFreeBut setBackgroundImage:[UIImage imageNamed:@"handFree_on"] forState:UIControlStateNormal];
        }else{
            [_handFreeBut setBackgroundImage:[UIImage imageNamed:@"handFree_off"] forState:UIControlStateNormal];
        }
        if ([self.delegate respondsToSelector:@selector(profile:didClickHandFree:)]) {
            [self.delegate profile:self didClickHandFree:_handFreeButisSelected];
        }
    }else if (sender.tag & callButtonTypeHangUpOn){
        if ([self.delegate respondsToSelector:@selector(didTouchHangUpWithProfile:)]) {
            [self.delegate didTouchHangUpWithProfile:self];
        }
        _isHangUpBySelf = YES;
    }else if (sender.tag & callButtonTypeAccept){
        if ([self.delegate respondsToSelector:@selector(didTouchAcceptWithProfile:)]) {
            [self.delegate didTouchAcceptWithProfile:self];
        }
    }
}

/**
 接通时震动
 */
- (void)vibrate {
    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
}
/**
 挂断提示音
 */
- (void)playStopCallAudioTip{
    AudioServicesPlaySystemSound(_soundFileObject);
}

- (void)updateCallDuration:(NSTimer *)timer {
//    UIColor *redColor =  [UIColor colorWithRed:233.0/255 green:63.0/255 blue:51.0/255 alpha:1];
    UIColor *greenColor = [UIColor colorWithRed:90.0/255 green:170.0/255 blue:98.0/255 alpha:1];
    _callDuration++;
    
   // NSLog(@"---:%@ -------- %d",[NSRunLoop currentRunLoop],_callDuration);

//    if (_callDuration % 5 == 0) {
//        if ([self.delegate respondsToSelector:@selector(fetchVoipCallQuality)]) {
//           _currentQuality = [self.delegate fetchVoipCallQuality];
//            NSAttributedString *qualityString;
//            if (_currentQuality & voipCallQualityNone) {
//                qualityString = [[NSAttributedString alloc] initWithString:@"检测中"
//                                                                attributes:@{NSForegroundColorAttributeName: greenColor}];
//            } else if (_currentQuality & voipCallQualityHigh) {
//                qualityString = [[NSAttributedString alloc] initWithString:@"优质"
//                                                          attributes:@{NSForegroundColorAttributeName:greenColor}];
//            } else if(_currentQuality & voipCallQualityMedium){
//                qualityString = [[NSAttributedString alloc] initWithString:@"中等"
//                                                          attributes:@{NSForegroundColorAttributeName:greenColor}];
//            }else if (_currentQuality & voipCallQualityLow){
//                qualityString = [[NSAttributedString alloc] initWithString:@"较差"
//                                                                attributes:@{NSForegroundColorAttributeName:redColor}];
//            }
//            NSMutableAttributedString *as = [[NSMutableAttributedString alloc] initWithString:@"当前网络信号: "];
//            [as appendAttributedString:qualityString];
//            _showQualityLabel.attributedText = as;
//        }
//    }
    
    NSAttributedString *qualityString;
    qualityString = [[NSAttributedString alloc] initWithString:@"加密通话中..."
                                                    attributes:@{NSForegroundColorAttributeName:greenColor}];
    NSMutableAttributedString *as = [[NSMutableAttributedString alloc] initWithString:@""];
    [as appendAttributedString:qualityString];
    _showQualityLabel.attributedText = as;

    int min, sec, hour;
    min = _callDuration / 60;
    min = min>=60 ? min % 60:min;
    sec = _callDuration % 60;
    NSString *showInfo;
    if (_callDuration >= 3600) {
        hour = _callDuration / 3600;
        showInfo = [NSString stringWithFormat:@"%02d:%02d:%02d",hour, min, sec];
    }else{
        showInfo = [NSString stringWithFormat:@"%02d:%02d", min, sec];
    }
    PBMAIN(^{
        _stateDescribeL.text = showInfo;
    });
}

- (NSAttributedString * _Nullable)fetchHeadAndTailIntentStyle4Text:(NSString *)text {
    if (text.length == 0) {
        return nil;
    }
    NSDictionary *attrs = [NSDictionary dictionaryWithObjectsAndKeys:[UIFont systemFontOfSize:15], NSFontAttributeName, [UIColor whiteColor], NSForegroundColorAttributeName,nil];
    NSMutableAttributedString *attributeString = [[NSMutableAttributedString alloc] initWithString:text attributes:attrs];
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.headIndent = 10.f;
    style.tailIndent = 10.f;
    NSRange range = NSMakeRange(0, attributeString.length);
    [attributeString addAttribute:NSParagraphStyleAttributeName value:style range:range];
    return attributeString.copy;
}

-(void)updateContent{

    if (_callViewType == FLKCallViewTypeAsCaller || _callViewType == FLKCallViewTypeTalking) {
        _buttonBackV.hidden = NO;
        _inCommingbottomView.hidden = YES;
        if (_callViewType == FLKCallViewTypeTalking) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(PBANIMATE_DURATION*2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self timer];
            });
        }
    }else if(_callViewType == FLKCallViewTypeAsCallee){
        _buttonBackV.hidden = YES;
        _inCommingbottomView.hidden = NO;
    }
    if (_willBeDismiss) {
        
        CGFloat alpha = 0.4;
        _hangUpBut.alpha = alpha;
        _titleL.alpha = alpha;
        _stateDescribeL.alpha = alpha;
        _buttonBackV.alpha = alpha;
        _inCommingbottomView.alpha = alpha;
        self.view.userInteractionEnabled = NO;
        _showQualityLabel.hidden = YES;
        _endTipView.hidden = NO;
        NSString *textInfo = nil;
        if (!_isHangUpBySelf) { // 对方挂断
            if (self.lastState == PJSIP_INV_STATE_EARLY ) {
                textInfo = @"对方已拒绝";
            }
            if (self.lastState == PJSIP_INV_STATE_CONFIRMED) {
                textInfo = @"对方已挂断，通话结束";
            }
        }else{
            if (self.lastState == PJSIP_INV_STATE_EARLY ) {
                textInfo = @"通话已取消";
            }
        }
        NSAttributedString *attrInfo = [self fetchHeadAndTailIntentStyle4Text:textInfo];
        if (attrInfo != nil) {
            _endTipView.attributedText = attrInfo;
        }
    }
    
    //MHContact *contact = [MHContact objectWithConnection:[MHDatabase instance].userStorage condition:@"number=?" valuesToBind:@[self.uid]];
    NSString *displayName = [self convertAccount2DisplayWithAccount:self.uid];
    _titleL.text = PBIsEmpty(displayName)?self.uid:displayName;
    
    NSString *displayStr;
    if (_callViewType == FLKCallViewTypeAsCaller || _callViewType == FLKCallViewTypeAsCallee) {
        displayStr = @"正在协商密钥...";
    }else if (_callViewType == FLKCallViewTypeTalking){
//        if (!_willBeDismiss) {
//            displayStr = @"00:00";
//        }
    }
    if (displayStr.length != 0) {
        _stateDescribeL.text = displayStr;
    }
}
- (void)launch{
    if (hasMicrophoneAuthorization()) {
        // DO
    }else{
        getPermissionFromAppSetting(@"麦克风权限获取失败", self);
    }
    CGRect bounds = [UIScreen mainScreen].bounds;
    bounds.origin.y -= CGRectGetHeight(bounds);
    UIWindow *window = [[UIWindow alloc] initWithFrame:bounds];
    window.windowLevel = UIWindowLevelNormal;
    window.backgroundColor = [UIColor whiteColor];
    window.rootViewController = self;
    [window makeKeyAndVisible];
    self.actionWindow = window;
    //动画淡入
    weakify(self)
    bounds.origin.y += CGRectGetHeight(bounds);
    [UIView animateWithDuration:PBANIMATE_DURATION*1.2 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        strongify(self)
        self.actionWindow.frame = bounds;
    } completion:^(BOOL finished) {
        
        if ([self.delegate respondsToSelector:@selector(fetchVoipCallCurrentTimeInterval)]) {
            CGFloat current = [self.delegate fetchVoipCallCurrentTimeInterval];
            if (current != 0) {
                _callDuration = current;
                [self timer];
            }
        }
    }];
}

- (void)dismiss{
    
    CGRect bounds = [UIScreen mainScreen].bounds;
    bounds.origin.y -= CGRectGetHeight(bounds);
    [UIView animateWithDuration:PBANIMATE_DURATION*1.2 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        //self.actionWindow.layer.opacity = 0.01f;
        self.actionWindow.frame = bounds;
    } completion:^(BOOL finished) {
        PBMAINDelay(PBANIMATE_DURATION, ^{
            self.actionWindow.hidden = true;
            [self.actionWindow removeFromSuperview];
            //[self.actionWindow resignKeyWindow];
            self.actionWindow = nil;
        });
    }];
}

/**
     PJSIP_INV_STATE_NULL,                     无状态     0
     PJSIP_INV_STATE_CALLING,                  播出       1
     PJSIP_INV_STATE_INCOMING,                 收到       2
     PJSIP_INV_STATE_EARLY,                    响铃       3
     PJSIP_INV_STATE_CONNECTING,               正在连接    4
     PJSIP_INV_STATE_CONFIRMED,                已经连接    5
     PJSIP_INV_STATE_DISCONNECTED,             断开       6
 */
#pragma mark === sip server statechange delegate -- update UI
- (void)audioCallDidChanged2State:(pjsip_inv_state)state{
    
    NSLog(@" ######## state:   %d",state);
    
    if (state == PJSIP_INV_STATE_CALLING) {     // 拨出
        _callViewType = FLKCallViewTypeAsCaller;
    }else if (state == PJSIP_INV_STATE_INCOMING ) {  // 来电
        _callViewType = FLKCallViewTypeAsCallee;
    }else if(state == PJSIP_INV_STATE_DISCONNECTED) {  // 挂断
        _willBeDismiss = YES;
        [self playStopCallAudioTip];
        [self releaseTimer];
        [UIDevice currentDevice].proximityMonitoringEnabled = NO;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(PBANIMATE_DURATION*6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self dismiss];
        });
    }else if (state == PJSIP_INV_STATE_CONFIRMED){
        _callViewType = FLKCallViewTypeTalking;
        [self vibrate];
    }
    if (state != PJSIP_INV_STATE_DISCONNECTED) {
        self.lastState = state;
    }
    // 更新UI状态的方法
    [self updateContent];
}
@end
