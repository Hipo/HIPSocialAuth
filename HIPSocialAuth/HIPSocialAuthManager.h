//
//  HIPSocialAuthManager.h
//
//  Created by Taylan Pince on 2013-07-18.
//  Copyright (c) 2013 Hipo. All rights reserved.
//

#import <Accounts/Accounts.h>
#import <FacebookSDK/FacebookSDK.h>
#import <Twitter/Twitter.h>

#import "HIPSocialAccount.h"


typedef void (^HIPSocialAuthHandler)(HIPSocialAccount *account, NSDictionary *profileInfo, NSError *error);

typedef enum {
    HIPSocialAuthErrorNone = 0,
    HIPSocialAuthErrorUnknownServiceType = 101,
    HIPSocialAuthErrorAuthenticationInProcess = 102,
    HIPSocialAuthErrorAuthenticationFailed = 103,
    HIPSocialAuthErrorNoAccountFound = 104,
    HIPSocialAuthErrorCancelled = 105,
    HIPSocialAuthErrorAccessNotGranted = 106,
} HIPSocialAuthError;


@interface HIPSocialAuthManager : NSObject

@property (nonatomic, retain, readonly) ACAccount *twitterAccount;
@property (nonatomic, copy, readonly) NSString *facebookSchemeSuffix;

+ (HIPSocialAuthManager *)sharedManager;

- (void)setupWithFacebookAppID:(NSString *)facebookAppID
        facebookAppPermissions:(NSArray *)facebookAppPermissions
          facebookSchemeSuffix:(NSString *)facebookSchemeSuffix
            twitterConsumerKey:(NSString *)twitterConsumerKey
         twitterConsumerSecret:(NSString *)twitterConsumerSecret;

- (BOOL)hasAuthenticatedAccountOfType:(HIPSocialAccountType)accountType;

- (void)authenticateAccountOfType:(HIPSocialAccountType)accountType
                      withHandler:(HIPSocialAuthHandler)handler;

- (BOOL)handleOpenURL:(NSURL *)url;

- (void)resetCachedTokens;
- (void)removeAccountOfType:(HIPSocialAccountType)accountType;

- (NSString *)twitterUsername;
- (NSString *)twitterToken;
- (NSString *)twitterTokenSecret;
- (NSString *)facebookToken;

@end
