HIPSocialAuth
=============

iOS7 framework for handling authentication with Facebook and Twitter with 
reverse-auth support.

Thanks to native support for Facebook and Twitter accounts in iOS, it's much 
easier to implement one-tap login and registration to your apps now. However 
there are a few pain points in this process:

* iOS-supported Twitter login uses a "global" Twitter app rather than your own, 
    so tokens cannot be used anywhere else
* A custom "reverse-auth" process needs to be implemented to obtain Twitter
    tokens that can be stored on server side
* Facebook no longer supports "offline access" permission, so your app needs to 
    reauthenticate at every launch, renewing its access token

HIPSocialAuth aims to ease the integration process by adding native support for all of these scenarios, and giving you a single interface that you 
can use to authenticate a user with one or more social networks.


Usage
-----

Basic usage is like this:

    [[HIPSocialAuthManager sharedManager] setupWithFacebookAppID:@"Facebook App Identifier"
                                              facebookAppPermissions:@[@"email"]
                                                facebookSchemeSuffix:nil
                                                  twitterConsumerKey:nil
                                               twitterConsumerSecret:nil];

    [[HIPSocialAuthManager sharedManager]
         authenticateAccountOfType:HIPSocialAccountTypeFacebook
         withHandler:^(HIPSocialAccount *account, NSDictionary *profileInfo, NSError *error) {
             if (nil == error) {
                 // Do your own thing here
             }
         }
     }];

And that's it! Completion block is called with an `HIPSocialAccount` instance that contains the identifier and account type, and a `profileInfo` dictionary that contains the raw profile data received from Twitter or Facebook.


Installation
------------

Copy and include the `HIPSocialAuth` directory in your own project. There are some other dependencies as well, you can see their details below.


Dependencies
------------

Project depends on the official Facebook and Twitter SDKs to work properly. You 
can download and include them in your project from these links:

* https://developers.facebook.com/ios/
* https://dev.twitter.com/twitter-kit/ios

If you find any issues, please open an issue here on GitHub, and feel free to send in pull requests with improvements and fixes. You can also get in touch
by emailing us at hello@hipolabs.com.


Credits
-------

HIPSocialAuth is brought to you by 
[Taylan Pince](http://taylanpince.com) and the [Hipo Team](http://hipolabs.com).


License
-------

HIPSocialAuth is licensed under the terms of the Apache License, version 2.0. Please see the LICENSE file for full details.
