Pod::Spec.new do |s|
  s.name         = "HIPSocialAuth"
  s.version      = "1.0.0"
  s.license      = 'Apache 2.0'
  s.summary      = "iOS7 framework for handling Facebook and Twitter authentication, with reverse-auth support."
  s.homepage     = "https://github.com/Hipo/HIPSocialAuth"
  s.license      = { :type => 'MIT', :file => 'LICENSE' }
  s.authors      = { "Taylan Pince" => "taylan@hipolabs.com" }
  s.source       = { :git => "https://github.com/Hipo/HIPSocialAuth.git", :tag => "1.0.0" }
  s.platform     = :ios, '7.0'
  s.source_files = 'HIPSocialAuth/*.{h,m}', 'Dependencies/TWAPIManager/*.{h,m}'
  s.requires_arc = true

  s.subspec 'no-arc' do |sp|
      sp.source_files = 'Dependencies/ABOAuthCore/*.{h,m}'
      sp.requires_arc = false
  end

  s.dependency 'Facebook-iOS-SDK', '~> 3.10.0'
end
