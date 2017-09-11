//
//  ViewController.m
//  PBVoipService
//
//  Created by nanhujiaju on 2017/9/8.
//  Copyright © 2017年 nanhujiaju. All rights reserved.
//

#import "ViewController.h"
#import <PBKits/PBKits.h>
#import "PBVoipService.h"

@interface ViewController ()
@property (weak, nonatomic) IBOutlet UITextField *fd_callee;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    NSLog(@"homePath:%@",NSHomeDirectory());
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (NSString *)convertState2InfoString:(BOOL)linked {
    return linked?@"已链接":@"未链接";
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesBegan:touches withEvent:event];
    [self.view endEditing:true];
}

- (IBAction)startCallEvent:(id)sender {
    
    NSString *bob_acc = self.fd_callee.text;
    if (bob_acc.length == 0) {
        return;
    }
    [[PBVoipService shared] startVoipCall2UserAccount:bob_acc withCompletion:^(NSError * _Nullable err) {
        
    }];
}

@end
