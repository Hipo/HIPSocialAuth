//
//  HIPSocialAuthManager.m
//  Chroma
//
//  Created by Taylan Pince on 2013-07-18.
//  Copyright (c) 2013 Change Theory. All rights reserved.
//

#import "TWAPIManager.h"
#import "NSData+Base64.h"

#import "HIPSocialAuthManager.h"


static NSString * const HIPSocialAuthErrorDomain = @"com.hipo.HIPSocialAuthManager.error";
static NSString * const HIPSocialAuthTwitterVerifyURL = @"https://api.twitter.com/1.1/account/verify_credentials.json";
static NSString * const HIPSocialAuthTwitterTokenKey = @"twitterToken";
static NSString * const HIPSocialAuthTwitterSecretKey = @"twitterSecret";
static NSString * const HIPSocialAuthTwitterUsernameKey = @"twitterUsername";


@interface HIPSocialAuthManager () <UIActionSheetDelegate>

@property (nonatomic, copy) NSString *facebookAppID;
@property (nonatomic, copy) NSArray *facebookPermissions;
@property (nonatomic, retain) ACAccountStore *accountStore;
@property (nonatomic, retain) TWAPIManager *twitterManager;
@property (nonatomic, copy) HIPSocialAuthHandler authHandler;
@property (nonatomic, assign) BOOL facebookAutoLoginInProgress;

- (void)authenticateFacebookAccount;
- (void)authenticateTwitterAccount;

- (void)checkSystemTwitterAccountsAgainstUsername:(NSString *)username;
- (void)generateTokenForTwitterAccount:(ACAccount *)twitterAccount;
- (void)fetchDetailsForTwitterAccount:(ACAccount *)twitterAccount;

- (void)openFacebookSession;
- (void)fetchDetailsForFacebookAccountAndRetryOnError:(BOOL)retryOnError;

- (void)completeAuthProcessWithAccount:(HIPSocialAccount *)account
                           profileInfo:(NSDictionary *)profileInfo
                                 error:(HIPSocialAuthError)error;

- (void)didReceiveApplicationDidBecomeActiveNotification:(NSNotification *)notification;
- (void)didReceiveApplicationWillTerminateNotification:(NSNotification *)notification;

@end


@implementation HIPSocialAuthManager

+ (HIPSocialAuthManager *)sharedManager {
    static HIPSocialAuthManager *_sharedManager = nil;
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        _sharedManager = [[HIPSocialAuthManager alloc] init];
    });
    
    return _sharedManager;
}

- (id)init {
    self = [super init];
    
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(didReceiveApplicationWillTerminateNotification:)
                                                     name:UIApplicationWillTerminateNotification
                                                   object:[UIApplication sharedApplication]];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(didReceiveApplicationDidBecomeActiveNotification:)
                                                     name:UIApplicationDidBecomeActiveNotification
                                                   object:[UIApplication sharedApplication]];
    }
    
    return self;
}

#pragma mark - Setup


- (void)setupWithFacebookAppID:(NSString *)facebookAppID
        facebookAppPermissions:(NSArray *)facebookAppPermissions
          facebookSchemeSuffix:(NSString *)facebookSchemeSuffix
            twitterConsumerKey:(NSString *)twitterConsumerKey
         twitterConsumerSecret:(NSString *)twitterConsumerSecret {
    
    if (_facebookAppID != nil || _twitterManager != nil) {
        return;
    }
    
    _facebookAppID = facebookAppID;
    _facebookPermissions = facebookAppPermissions;
    _facebookSchemeSuffix = facebookSchemeSuffix;
    
    [FBSettings setDefaultAppID:facebookAppID];
    
    _authHandler = nil;
    _accountStore = [[ACAccountStore alloc] init];
    _twitterManager = [[TWAPIManager alloc] init];
    
    [_twitterManager setConsumerKey:twitterConsumerKey];
    [_twitterManager setConsumerSecret:twitterConsumerSecret];
    
    if ([self hasAuthenticatedAccountOfType:HIPSocialAccountTypeFacebook]) {
        [self authenticateFacebookAccount];
    }
    
    if (self.twitterToken != nil && self.twitterTokenSecret != nil && self.twitterUsername != nil) {
        [self checkSystemTwitterAccountsAgainstUsername:self.twitterUsername];
    }
}

#pragma mark - Authentication check

- (BOOL)hasAuthenticatedAccountOfType:(HIPSocialAccountType)accountType {
    switch (accountType) {
        case HIPSocialAccountTypeFacebook: {
            FBSessionState sessionState = [[FBSession activeSession] state];
            
            return (sessionState == FBSessionStateCreatedTokenLoaded ||
                    sessionState == FBSessionStateOpen ||
                    sessionState == FBSessionStateOpenTokenExtended);
            break;
        }
        case HIPSocialAccountTypeTwitter: {
            return (_twitterAccount != nil);
            
            break;
        }
        default:
            break;
    }
    
    return NO;
}

#pragma mark - Authentication

- (void)authenticateAccountOfType:(HIPSocialAccountType)accountType
                      withHandler:(HIPSocialAuthHandler)handler {
    if (accountType == HIPSocialAccountTypeUnknown) {
        handler(nil, nil, [NSError errorWithDomain:HIPSocialAuthErrorDomain
                                              code:HIPSocialAuthErrorUnknownServiceType
                                          userInfo:nil]);
        
        return;
    }
    
    if (_authHandler != nil) {
        handler(nil, nil, [NSError errorWithDomain:HIPSocialAuthErrorDomain
                                              code:HIPSocialAuthErrorAuthenticationInProcess
                                          userInfo:nil]);
        
        return;
    }
    
    _authHandler = handler;
    
    switch (accountType) {
        case HIPSocialAccountTypeFacebook: {
            [self authenticateFacebookAccount];
            
            break;
        }
        case HIPSocialAccountTypeTwitter: {
            [self authenticateTwitterAccount];
            
            break;
        }
        default:
            break;
    }
}

#pragma mark - Facebook login

- (void)authenticateFacebookAccount {
    if ([[FBSession activeSession] isOpen] && [self hasAuthenticatedAccountOfType:HIPSocialAccountTypeFacebook]) {
        _facebookAutoLoginInProgress = YES;
        
        [self fetchDetailsForFacebookAccountAndRetryOnError:YES];
        
        return;
    }
    
    _facebookAutoLoginInProgress = NO;
    
    ACAccountStoreRequestAccessCompletionHandler completionHandler = ^(BOOL granted, NSError *error) {
        if (!granted) {
            HIPSocialAuthError errorCode = HIPSocialAuthErrorAccessNotGranted;
            
            if (error != nil && [error code] == ACErrorAccountNotFound) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self openFacebookSession];
                });
                
                return;
            }
            
            [self completeAuthProcessWithAccount:nil
                                     profileInfo:nil
                                           error:errorCode];
            
            return;
        } else if (error != nil) {
            HIPSocialAuthError errorCode = HIPSocialAuthErrorAuthenticationFailed;
            
            if ([error code] == ACErrorAccountNotFound) {
                errorCode = HIPSocialAuthErrorNoAccountFound;
            }

            [self completeAuthProcessWithAccount:nil
                                     profileInfo:nil
                                           error:errorCode];
            
            return;
        }
        
        dispatch_block_t completionBlock = ^{
            [self openFacebookSession];
        };
        
        dispatch_async(dispatch_get_main_queue(), completionBlock);
    };
    
    if ([_accountStore respondsToSelector:@selector(requestAccessToAccountsWithType:options:completion:)]) {
        ACAccountType *facebookAccountType = [_accountStore accountTypeWithAccountTypeIdentifier:
                                              ACAccountTypeIdentifierFacebook];
        
        [_accountStore requestAccessToAccountsWithType:facebookAccountType
                                               options:@{
                                                         ACFacebookAppIdKey : _facebookAppID,
                                                         ACFacebookPermissionsKey : _facebookPermissions,
                                                         ACFacebookAudienceKey : ACFacebookAudienceEveryone
                                                         }
                                            completion:completionHandler];
    } else {
        [self openFacebookSession];
    }
}

- (void)openFacebookSession {
    FBSession *session = [[FBSession alloc] initWithAppID:_facebookAppID
                                              permissions:_facebookPermissions
                                          defaultAudience:FBSessionDefaultAudienceEveryone
                                          urlSchemeSuffix:_facebookSchemeSuffix
                                       tokenCacheStrategy:nil];
    
    [FBSession setActiveSession:session];
    
    [[FBSession activeSession] openWithCompletionHandler:^(FBSession *session, FBSessionState status, NSError *error) {
        switch (status) {
            case FBSessionStateClosed:
                if (_facebookAutoLoginInProgress) {
                    return;
                }

                break;
            case FBSessionStateClosedLoginFailed: {
                [FBSession.activeSession closeAndClearTokenInformation];
                break;
            }
            case FBSessionStateCreated:
                break;
            case FBSessionStateCreatedOpening:
                break;
            case FBSessionStateCreatedTokenLoaded:
                break;
            case FBSessionStateOpen:
                break;
            case FBSessionStateOpenTokenExtended:
                break;
            default:
                break;
        }
        
        if (_authHandler == nil) {
            return;
        }
        
        if (status != FBSessionStateOpen && status != FBSessionStateOpenTokenExtended) {
            
            [self completeAuthProcessWithAccount:nil
                                     profileInfo:nil
                                           error:HIPSocialAuthErrorAuthenticationFailed];
            
            return;
        }
        
        [self fetchDetailsForFacebookAccountAndRetryOnError:NO];
    }];
}

- (void)fetchDetailsForFacebookAccountAndRetryOnError:(BOOL)retryOnError {
    [FBRequestConnection startForMeWithCompletionHandler:^(FBRequestConnection *connection, id result, NSError *error) {
        if (result != nil && error == nil) {
            HIPSocialAccount *account = [HIPSocialAccount accountWithType:HIPSocialAccountTypeFacebook
                                                               identifier:[result objectForKey:@"id"]];
            
            [self completeAuthProcessWithAccount:account
                                     profileInfo:result
                                           error:HIPSocialAuthErrorNone];
        } else if (retryOnError) {
            [self openFacebookSession];
        } else {
            [self completeAuthProcessWithAccount:nil
                                     profileInfo:nil
                                           error:HIPSocialAuthErrorAuthenticationFailed];
        }
    }];
}

#pragma mark - Twitter login

- (void)authenticateTwitterAccount {
    // Request access to Twitter accounts, once permission is given, check available accounts
    // If there is more than one, display picker interface, or if there is only one, move on
    // Once an account is selected, fetch profile by using the verify endpoint
    // Then call the authHandler block with the STAccount instance
    
    ACAccountType *twitterAccountType = [_accountStore accountTypeWithAccountTypeIdentifier:
                                         ACAccountTypeIdentifierTwitter];
    
    ACAccountStoreRequestAccessCompletionHandler completionHandler = ^(BOOL granted, NSError *error) {
        if (!granted) {
            HIPSocialAuthError errorCode = HIPSocialAuthErrorAccessNotGranted;
            
            if (error != nil && [error code] == ACErrorAccountNotFound) {
                errorCode = HIPSocialAuthErrorNoAccountFound;
            }
            
            [self completeAuthProcessWithAccount:nil
                                     profileInfo:nil
                                           error:errorCode];
            
            return;
        } else if (error != nil) {
            HIPSocialAuthError errorCode = HIPSocialAuthErrorAuthenticationFailed;
            
            if ([error code] == ACErrorAccountNotFound) {
                errorCode = HIPSocialAuthErrorNoAccountFound;
            }
            
            [self completeAuthProcessWithAccount:nil
                                     profileInfo:nil
                                           error:errorCode];
            
            return;
        }
        
        dispatch_block_t completionBlock = ^{
            [self checkSystemTwitterAccountsAgainstUsername:self.twitterUsername];
        };
        
        dispatch_async(dispatch_get_main_queue(), completionBlock);
    };
    
    [_accountStore requestAccessToAccountsWithType:twitterAccountType
                                           options:nil
                                        completion:completionHandler];
}

- (void)checkSystemTwitterAccountsAgainstUsername:(NSString *)username {
    ACAccountType *twitterAccountType = [_accountStore accountTypeWithAccountTypeIdentifier:
                                         ACAccountTypeIdentifierTwitter];
    
    NSArray *systemTwitterAccounts = [_accountStore accountsWithAccountType:twitterAccountType];
    
    if (systemTwitterAccounts == nil || [systemTwitterAccounts count] == 0) {
        if (_authHandler != nil) {
            [self completeAuthProcessWithAccount:nil
                                     profileInfo:nil
                                           error:HIPSocialAuthErrorNoAccountFound];
        }
        
        return;
    }
    
    if (username != nil) {
        for (ACAccount *systemTwitterAccount in systemTwitterAccounts) {
            if (systemTwitterAccount.username != nil) {
                if ([username isEqualToString:systemTwitterAccount.username]) {
                    _twitterAccount = systemTwitterAccount;
                    
                    if (_authHandler != nil) {
                        [self fetchDetailsForTwitterAccount:systemTwitterAccount];
                    }
                    
                    return;
                }
            }
        }
    }
    
    if ([systemTwitterAccounts count] == 1) {
        [self generateTokenForTwitterAccount:[systemTwitterAccounts objectAtIndex:0]];
    } else {
        dispatch_block_t completionBlock = ^{
            UIActionSheet *actionSheet = [[UIActionSheet alloc]
                                          initWithTitle:NSLocalizedString(@"Select an account", nil)
                                          delegate:self
                                          cancelButtonTitle:nil
                                          destructiveButtonTitle:nil
                                          otherButtonTitles:nil];
            
            for (ACAccount *systemTwitterAccount in systemTwitterAccounts) {
                [actionSheet addButtonWithTitle:systemTwitterAccount.accountDescription];
            }
            
            [actionSheet addButtonWithTitle:NSLocalizedString(@"Nevermind", nil)];
            [actionSheet setCancelButtonIndex:[systemTwitterAccounts count]];
            
            UIWindow *mainWindow = [[UIApplication sharedApplication] keyWindow];
            UIViewController *parentController = mainWindow.rootViewController;
            UIViewController *modalController = parentController.presentedViewController;
            
            while (modalController != nil) {
                parentController = modalController;
                modalController = parentController.presentedViewController;
            }
            
            if (parentController != nil) {
                [actionSheet showInView:parentController.view];
            } else {
                [actionSheet showInView:mainWindow];
            }
        };
        
        dispatch_async(dispatch_get_main_queue(), completionBlock);
    }
}

- (void)generateTokenForTwitterAccount:(ACAccount *)twitterAccount {
    [_twitterManager
     performReverseAuthForAccount:twitterAccount
     withHandler:^(NSData *responseData, NSError *error) {
         if (error != nil) {
             [self completeAuthProcessWithAccount:nil
                                      profileInfo:nil
                                            error:HIPSocialAuthErrorAuthenticationFailed];
             
             return;
         }
         
         NSString *response = [[NSString alloc]
                               initWithData:responseData
                               encoding:NSUTF8StringEncoding];
         
         NSArray *components = [response componentsSeparatedByString:@"&"];
         NSString *token = nil;
         NSString *tokenSecret = nil;
         
         for (NSString *component in components) {
             NSArray *parts = [component componentsSeparatedByString:@"="];
             
             if ([[parts objectAtIndex:0] isEqualToString:@"oauth_token"]) {
                 token = [parts objectAtIndex:1];
             } else if ([[parts objectAtIndex:0] isEqualToString:@"oauth_token_secret"]) {
                 tokenSecret = [parts objectAtIndex:1];
             }
         }
         
         if (token == nil || tokenSecret == nil) {
             [self completeAuthProcessWithAccount:nil
                                      profileInfo:nil
                                            error:HIPSocialAuthErrorAuthenticationFailed];
             
             return;
         }
         
         NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
         
         [prefs setObject:token forKey:HIPSocialAuthTwitterTokenKey];
         [prefs setObject:tokenSecret forKey:HIPSocialAuthTwitterSecretKey];
         [prefs setObject:twitterAccount.username forKey:HIPSocialAuthTwitterUsernameKey];
         [prefs synchronize];
         
         [self fetchDetailsForTwitterAccount:twitterAccount];
     }];
}

- (void)fetchDetailsForTwitterAccount:(ACAccount *)twitterAccount {
    SLRequest *request = [SLRequest requestForServiceType:SLServiceTypeTwitter
                                            requestMethod:SLRequestMethodGET
                                                      URL:[NSURL URLWithString:HIPSocialAuthTwitterVerifyURL]
                                               parameters:nil];
    
    [request setAccount:twitterAccount];
    [request performRequestWithHandler:^(NSData *responseData, NSHTTPURLResponse *urlResponse, NSError *error) {
        if ([urlResponse statusCode] != 200) {
            [self completeAuthProcessWithAccount:nil
                                     profileInfo:nil
                                           error:HIPSocialAuthErrorAuthenticationFailed];
            
            return;
        }
        
        NSError *parseError = nil;
        NSDictionary *userInfo = [NSJSONSerialization JSONObjectWithData:responseData
                                                                 options:0
                                                                   error:&parseError];
        
        if (parseError == nil) {
            _twitterAccount = twitterAccount;
            
            HIPSocialAccount *account = [HIPSocialAccount accountWithType:HIPSocialAccountTypeTwitter
                                                               identifier:[userInfo valueForKey:@"id_str"]];
            
            [self completeAuthProcessWithAccount:account
                                     profileInfo:userInfo
                                           error:HIPSocialAuthErrorNone];
        } else {
            [self completeAuthProcessWithAccount:nil
                                     profileInfo:nil
                                           error:HIPSocialAuthErrorAuthenticationFailed];
        }
    }];
}

#pragma mark - UIActionSheet delegate

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    ACAccountType *twitterAccountType = [_accountStore accountTypeWithAccountTypeIdentifier:
                                         ACAccountTypeIdentifierTwitter];
    
    NSArray *systemTwitterAccounts = [_accountStore accountsWithAccountType:twitterAccountType];
    
    if (buttonIndex >= [systemTwitterAccounts count]) {
        [self completeAuthProcessWithAccount:nil
                                 profileInfo:nil
                                       error:HIPSocialAuthErrorCancelled];
        
        return;
    }
    
    [self generateTokenForTwitterAccount:[systemTwitterAccounts objectAtIndex:buttonIndex]];
}

#pragma mark - Completion

- (void)completeAuthProcessWithAccount:(HIPSocialAccount *)account
                           profileInfo:(NSDictionary *)profileInfo
                                 error:(HIPSocialAuthError)error {
    if (_authHandler == nil) {
        return;
    }
    
    dispatch_block_t completionBlock = ^{
        switch (error) {
            case HIPSocialAuthErrorNone: {
                _authHandler(account, profileInfo, nil);
                _authHandler = nil;
                break;
            }
            case HIPSocialAuthErrorNoAccountFound:{
                [self openFacebookSession];
                break;
            }
            default: {
                _authHandler(account, profileInfo, [NSError errorWithDomain:HIPSocialAuthErrorDomain
                                                                       code:error
                                                                   userInfo:nil]);
                _authHandler = nil;
                break;
            }
        }
    };
    
    dispatch_async(dispatch_get_main_queue(), completionBlock);
}

#pragma mark - URL handling

- (BOOL)handleOpenURL:(NSURL *)url {
    return [[FBSession activeSession] handleOpenURL:url];
}

#pragma mark - Notifications

- (void)didReceiveApplicationDidBecomeActiveNotification:(NSNotification *)notification {
    [[FBSession activeSession] handleDidBecomeActive];
}

- (void)didReceiveApplicationWillTerminateNotification:(NSNotification *)notification {
    [[FBSession activeSession] close];
}

#pragma mark - Twitter Tokens

- (NSString *)twitterToken {
    return [[NSUserDefaults standardUserDefaults] objectForKey:HIPSocialAuthTwitterTokenKey];
}

- (NSString *)twitterTokenSecret {
    return [[NSUserDefaults standardUserDefaults] objectForKey:HIPSocialAuthTwitterSecretKey];
}

- (NSString *)twitterUsername {
    return [[NSUserDefaults standardUserDefaults] objectForKey:HIPSocialAuthTwitterUsernameKey];
}

#pragma mark - Facebook Token

- (NSString *)facebookToken {
    return [[[FBSession activeSession] accessTokenData] accessToken];
}

#pragma mark - Reset

- (void)removeAccountOfType:(HIPSocialAccountType)accountType {
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    
    switch (accountType) {
        case HIPSocialAccountTypeTwitter: {
            [prefs removeObjectForKey:HIPSocialAuthTwitterTokenKey];
            [prefs removeObjectForKey:HIPSocialAuthTwitterSecretKey];
            [prefs removeObjectForKey:HIPSocialAuthTwitterUsernameKey];
            
            _twitterAccount = nil;
            break;
        }
        case HIPSocialAccountTypeFacebook: {
            [[FBSession activeSession] closeAndClearTokenInformation];

            break;
        }
        default:
            break;
    }

    [prefs synchronize];
}

- (void)resetCachedTokens {
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    
    [prefs removeObjectForKey:HIPSocialAuthTwitterTokenKey];
    [prefs removeObjectForKey:HIPSocialAuthTwitterSecretKey];
    [prefs removeObjectForKey:HIPSocialAuthTwitterUsernameKey];
    [prefs synchronize];
    
    [[FBSession activeSession] closeAndClearTokenInformation];
    
    _twitterAccount = nil;
}

@end
