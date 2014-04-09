//
//  HIPSocialAccount.m
//  Chroma
//
//  Created by Taylan Pince on 2013-07-18.
//  Copyright (c) 2013 Change Theory. All rights reserved.
//

#import "HIPSocialAccount.h"


static NSString * const HIPSocialAccountIdentifierKey = @"identifier";
static NSString * const HIPSocialAccountTypeKey = @"service";
static NSString * const HIPSocialAccountTypeFacebookValue = @"facebook";
static NSString * const HIPSocialAccountTypeTwitterValue = @"twitter";
static NSString * const HIPSocialAccountTypeUnknownValue = @"unknown";


@implementation HIPSocialAccount

+ (HIPSocialAccount *)accountWithInfo:(NSDictionary *)accountInfo {
    return [[HIPSocialAccount alloc] initWithAccountInfo:accountInfo];
}

+ (HIPSocialAccount *)accountWithType:(HIPSocialAccountType)accountType
                           identifier:(NSString *)identifier {
    return [[HIPSocialAccount alloc] initWithaccountType:accountType
                                              identifier:identifier];
}

- (id)initWithAccountInfo:(NSDictionary *)accountInfo {
    self = [super init];
    
    if (self) {
        _identifier = [accountInfo valueForKey:HIPSocialAccountIdentifierKey];
        _networkType = HIPSocialAccountTypeUnknown;
        
        NSString *serviceName = [accountInfo valueForKey:HIPSocialAccountTypeKey];
        
        if ([serviceName isEqualToString:HIPSocialAccountTypeFacebookValue]) {
            _networkType = HIPSocialAccountTypeFacebook;
        } else if ([serviceName isEqualToString:HIPSocialAccountTypeTwitterValue]) {
            _networkType = HIPSocialAccountTypeTwitter;
        }
    }
    
    return self;
}

- (id)initWithaccountType:(HIPSocialAccountType)accountType
               identifier:(NSString *)identifier {
    self = [super init];
    
    if (self) {
        _networkType = accountType;
        _identifier = identifier;
    }
    
    return self;
}

#pragma mark - Storage

- (NSString *)serviceName {
    switch (_networkType) {
        case HIPSocialAccountTypeFacebook:
            return HIPSocialAccountTypeFacebookValue;
            break;
        case HIPSocialAccountTypeTwitter:
            return HIPSocialAccountTypeTwitterValue;
            break;
        default:
            return HIPSocialAccountTypeUnknownValue;
            break;
    }
}

#pragma mark - NSCoding

- (void)encodeWithCoder:(NSCoder *)aCoder {
    [aCoder encodeObject:_identifier forKey:HIPSocialAccountIdentifierKey];
    [aCoder encodeObject:[self serviceName] forKey:HIPSocialAccountTypeKey];
}

- (id)initWithCoder:(NSCoder *)aDecoder {
    NSString *identifier = [aDecoder decodeObjectForKey:HIPSocialAccountIdentifierKey];
    NSString *serviceName = [aDecoder decodeObjectForKey:HIPSocialAccountTypeKey];
    
    return [self initWithAccountInfo:@{HIPSocialAccountIdentifierKey: identifier,
                                       HIPSocialAccountTypeKey: serviceName}];
}

@end
