//
//  HIPSocialAccount.h
//
//  Created by Taylan Pince on 2013-07-18.
//  Copyright (c) 2013 Hipo. All rights reserved.
//


typedef enum {
    HIPSocialAccountTypeUnknown,
    HIPSocialAccountTypeFacebook,
    HIPSocialAccountTypeTwitter,
} HIPSocialAccountType;


@interface HIPSocialAccount : NSObject <NSCoding>

@property (nonatomic, retain) NSString *identifier;
@property (nonatomic, assign) HIPSocialAccountType networkType;

+ (HIPSocialAccount *)accountWithInfo:(NSDictionary *)accountInfo;
+ (HIPSocialAccount *)accountWithType:(HIPSocialAccountType)accountType
                           identifier:(NSString *)identifier;

- (id)initWithAccountInfo:(NSDictionary *)accountInfo;
- (id)initWithaccountType:(HIPSocialAccountType)accountType
               identifier:(NSString *)identifier;

- (NSString *)serviceName;

@end
