Pod::Spec.new do |s|

  s.name         = "HIPSocialAuth"
  s.version      = "1.2.0"
  s.summary      = "iOS framework for handling Facebook and Twitter authentication"
  s.homepage     = "https://github.com/Hipo/HIPSocialAuth"
  s.license      = { :type => 'Apache 2.0', :file => 'LICENSE' }
  s.authors      = { "Taylan Pince" => "taylan@hipolabs.com" }
  s.source       = { :git => "https://github.com/Hipo/HIPSocialAuth.git", :tag => "1.2.0" }
  s.platform     = :ios, '7.0'
  s.source_files = 'HIPSocialAuth/*.{h,m}'
  s.requires_arc = true
  s.dependency 'Facebook-iOS-SDK', '~> 4.0'

end
