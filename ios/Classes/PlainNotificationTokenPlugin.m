#import "PlainNotificationTokenPlugin.h"
#import <UserNotifications/UserNotifications.h>

@implementation PlainNotificationTokenPlugin {
    NSString *_lastToken;
    FlutterMethodChannel *_channel;
}
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    FlutterMethodChannel* channel = [FlutterMethodChannel
                                     methodChannelWithName:@"plain_notification_token"
                                     binaryMessenger:[registrar messenger]];
    PlainNotificationTokenPlugin* instance = [[PlainNotificationTokenPlugin alloc] initWithChannel:channel];
    [registrar addApplicationDelegate:instance];
    [registrar addMethodCallDelegate:instance channel:channel];
}

- (instancetype)initWithChannel:(FlutterMethodChannel *)channel {
    self = [super init];
    
    if (self) {
        _channel = channel;
        dispatch_async(dispatch_get_main_queue(), ^() {
            [[UIApplication sharedApplication] registerForRemoteNotifications];
        });
        [[UNUserNotificationCenter currentNotificationCenter] getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings * _Nonnull settings) {
            NSDictionary *settingsDictionary = @{
                @"sound" : [NSNumber numberWithBool:settings.soundSetting == UNNotificationSettingEnabled],
                @"badge" : [NSNumber numberWithBool:settings.badgeSetting == UNNotificationSettingEnabled],
                @"alert" : [NSNumber numberWithBool:settings.alertSetting == UNNotificationSettingEnabled],
            };
            [self->_channel invokeMethod:@"onIosSettingsRegistered" arguments:settingsDictionary];
        }];
    }
    return self;
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    if ([@"getToken" isEqualToString:call.method]) {
        result([self getToken]);
    } else if ([@"requestPermission" isEqualToString:call.method]) {
        [self requestPermissionWithSettings:[call arguments]];
        result(nil);
    } else {
        result(FlutterMethodNotImplemented);
    }
}

- (NSString *)getToken {
    return _lastToken;
}

- (void)requestPermissionWithSettings: (NSDictionary<NSString*, NSNumber*> *)settings {
    UNAuthorizationOptions options = UNAuthorizationOptionNone;
    if ([[settings objectForKey:@"sound"] boolValue]) {
        options |= UNAuthorizationOptionSound;
    }
    if ([[settings objectForKey:@"badge"] boolValue]) {
        options |= UNAuthorizationOptionBadge;
    }
    if ([[settings objectForKey:@"alert"] boolValue]) {
        options |= UNAuthorizationOptionAlert;
    }
    [[UNUserNotificationCenter currentNotificationCenter] requestAuthorizationWithOptions:options completionHandler:^(BOOL granted, NSError * _Nullable error) {
        if (error != nil) {
            NSLog(@"Error during requesting notification permission: %@", error);
        }
        if (granted) {
            dispatch_async(dispatch_get_main_queue(), ^() {
                [[UIApplication sharedApplication] registerForRemoteNotifications];
            });
            [self->_channel invokeMethod:@"onIosSettingsRegistered" arguments:settings];
        } else {
            NSNumber* falseNumber = [NSNumber numberWithBool: NO];
            NSDictionary<NSString*, NSNumber*> *empty = [NSDictionary dictionaryWithObjectsAndKeys: falseNumber, @"badge", falseNumber, @"alert", falseNumber, @"sound", nil];
            [self->_channel invokeMethod:@"onIosSettingsRegistered" arguments:empty];
        }
    }];
}

#pragma mark - AppDelegate
- (void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken {
    NSString *tokenStr = [NSString stringWithFormat:@"%@",deviceToken];
    if ([tokenStr containsString:@"length"]) {
        NSMutableString *deviceTokenString = [NSMutableString string];
        const char *bytes = (char *)(deviceToken.bytes);
        NSInteger count = deviceToken.length;
        for (int i = 0; i < count; i++) {
            [deviceTokenString appendFormat:@"%02x", bytes[i]&0x000000FF];
        }
        tokenStr = deviceTokenString;
    }else{
        NSString *token = [[tokenStr substringFromIndex:1] substringToIndex:71];
        tokenStr = [token stringByReplacingOccurrencesOfString:@" " withString:@""];
    }
    _lastToken = [tokenStr copy];
    NSLog(@"PlainNotificationTokenPlugin -- 原生解析到的APNS_TOKEN: %@",tokenStr);
    [_channel invokeMethod:@"onToken" arguments:_lastToken];
}

//MARK: APP收到报警消息
- (BOOL)application:(UIApplication*)application
didReceiveRemoteNotification:(NSDictionary*)userInfo
fetchCompletionHandler:(void (^)(UIBackgroundFetchResult result))completionHandler{
    //    NSDictionary *apsDic = userInfo[@"aps"];
    //    __block NSString *msgContent = apsDic[@"alert"];
    //
    //    //NSLog(@"cycy = %@",msgContent);
    //    //发送一条新消息的通知，相关界面收到通知后刷新界面
    //    //todo:推送服务器还需要新增这些字段才能完成消息计数数的功能
    //    NSString *alarmId = userInfo[@"ALARMID"];
    //    NSString *devID = userInfo[@"UUID"];
    //    NSString *subSN = userInfo[@"SUBSN"];
    //
    //    if (!devID) {
    //        return YES;
    //    }
    
    NSString *messageJsonStr = [self _toJsonStr: userInfo];
    NSLog(@"PlainNotificationTokenPlugin -- 原生收到推送消息: %@",messageJsonStr);
    [_channel invokeMethod:@"onReceiveNotificationMessage" arguments:messageJsonStr];
    return YES;
}

-(void)userNotificationCenter:(UNUserNotificationCenter *)center willPresentNotification:(UNNotification *)notification withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler{
    completionHandler(UNNotificationPresentationOptionSound | UNNotificationPresentationOptionAlert | UNNotificationPresentationOptionBadge);
}

// 注册通知失败 处理方法
-(void)application:(UIApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error{
    NSLog(@"PlainNotificationTokenPlugin -- 原生注册推送失败");
}

#pragma mark -- Privte ===============================================
- (NSString *)_toJsonStr:(NSDictionary *)dictionary {
    // 将NSDictionary转换为JSON数据
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dictionary options:NSJSONWritingPrettyPrinted error:&error];
    if (error) {
        NSLog(@"Error converting NSDictionary to JSON: %@", error.localizedDescription);
        return @"";
    } else {
        // 将JSON数据转换为字符串
        NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        return jsonString;
    }
}

@end
