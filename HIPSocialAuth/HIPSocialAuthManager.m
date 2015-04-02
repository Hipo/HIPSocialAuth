//
//  HIPSocialAuthManager.m
//
//  Created by Taylan Pince on 2013-07-18.
//  Copyright (c) 2013 Hipo. All rights reserved.
//

#import <TwitterKit/TwitterKit.h>

#import "HIPSocialAuthManager.h"


static NSString * const HIPSocialAuthErrorDomain = @"com.hipo.HIPSocialAuthManager.error";
static NSString * const HIPSocialAuthTwitterVerifyURL = @"https://api.twitter.com/1.1/account/verify_credentials.json";
static NSString * const HIPSocialAuthTwitterTokenKey = @"twitterToken";
static NSString * const HIPSocialAuthTwitterSecretKey = @"twitterSecret";
static NSString * const HIPSocialAuthTwitterUsernameKey = @"twitterUsername";


@interface HIPSocialAuthManager ()

@property (nonatomic, copy) NSString *facebookAppID;
@property (nonatomic, copy) NSArray *facebookPermissions;
@property (nonatomic, retain) ACAccountStore *accountStore;
@property (nonatomic, copy) HIPSocialAuthHandler authHandler;
@property (nonatomic, assign) BOOL facebookAutoLoginInProgress;

- (void)authenticateFacebookAccount;
- (void)authenticateTwitterAccount;

- (void)fetchDetailsForTwitterSession;

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
    
    if (_facebookAppID != nil || _accountStore != nil) {
        return;
    }
    
    _facebookAppID = facebookAppID;
    _facebookPermissions = facebookAppPermissions;
    _facebookSchemeSuffix = facebookSchemeSuffix;
    
    [FBSettings setDefaultAppID:facebookAppID];
    
    _authHandler = nil;
    _accountStore = [[ACAccountStore alloc] init];
    
    if ([self hasAuthenticatedAccountOfType:HIPSocialAccountTypeFacebook]) {
        [self authenticateFacebookAccount];
    }

    if (self.twitterToken != nil && self.twitterTokenSecret != nil && self.twitterUsername != nil) {
        [self authenticateTwitterAccount];
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
            return (_twitterSession != nil);
            
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
    if ([self hasAuthenticatedAccountOfType:HIPSocialAccountTypeFacebook]) {
        if ([[FBSession activeSession] isOpen]) {
            _facebookAutoLoginInProgress = YES;
            
            [self fetchDetailsForFacebookAccountAndRetryOnError:YES];
            
            return;
        } else if ([[FBSession activeSession] state] == FBSessionStateCreatedTokenLoaded) {
            [self openFacebookSession];
            
            return;
        }
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
    
    [[FBSession activeSession]
     openWithBehavior:FBSessionLoginBehaviorUseSystemAccountIfPresent
     completionHandler:^(FBSession *session, FBSessionState status, NSError *error) {
         switch (status) {
             case FBSessionStateClosed:
                 if (_facebookAutoLoginInProgress) {
                     _facebookAutoLoginInProgress = NO;
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
         
         _facebookAutoLoginInProgress = NO;
         
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
    
    [[Twitter sharedInstance] logInWithCompletion:^(TWTRSession *session, NSError *error) {
        if (session) {
            _twitterSession = session;
            
            NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];

            [prefs setObject:_twitterSession.authToken forKey:HIPSocialAuthTwitterTokenKey];
            [prefs setObject:_twitterSession.authTokenSecret forKey:HIPSocialAuthTwitterSecretKey];
            [prefs setObject:_twitterSession.userName forKey:HIPSocialAuthTwitterUsernameKey];
            [prefs synchronize];

            [self fetchDetailsForTwitterSession];
        } else {
            [self completeAuthProcessWithAccount:nil
                                     profileInfo:nil
                                           error:HIPSocialAuthErrorAuthenticationFailed];
        }
    }];
}

- (void)fetchDetailsForTwitterSession {

    [[[Twitter sharedInstance] APIClient]
     loadUserWithID:_twitterSession.userID
     completion:^(TWTRUser *user, NSError *error) {
         if (user) {
             HIPSocialAccount *account = [HIPSocialAccount accountWithType:HIPSocialAccountTypeTwitter
                                                                identifier:user.userID];
             
             NSDictionary *profileInfo = @{@"name": user.name,
                                           @"screen_name": user.screenName,
                                           @"profile_image_url": user.profileImageURL};

             [self completeAuthProcessWithAccount:account
                                      profileInfo:profileInfo
                                            error:HIPSocialAuthErrorNone];

         } else {
             [self removeAccountOfType:HIPSocialAccountTypeTwitter];
             
             [self completeAuthProcessWithAccount:nil
                                      profileInfo:nil
                                            error:HIPSocialAuthErrorAuthenticationFailed];
         }
     }];
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
                break;
            }
            default: {
                _authHandler(account, profileInfo, [NSError errorWithDomain:HIPSocialAuthErrorDomain
                                                                       code:error
                                                                   userInfo:nil]);
                break;
            }
        }
        
        _authHandler = nil;
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
            
            _twitterSession = nil;
            
            [[Twitter sharedInstance] logOut];
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
    
    _twitterSession = nil;
    
    [[Twitter sharedInstance] logOut];
}

@end
