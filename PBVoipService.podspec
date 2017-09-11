Pod::Spec.new do |s|

  s.name         = "PBVoipService"
  s.version      = "1.0.0"
  s.summary      = "voip call module for iOS development."
  s.description  = "voip call module for FLK.Inc iOS Developers, such as sign in/sign up etc."

  s.homepage     = "https://github.com/iFindTA"
  s.license      = "MIT (LICENSE)"
  s.author             = { "nanhujiaju" => "hujiaju@hzflk.com" }

  s.platform     = :ios, "8.0"
  s.source       = { :git => "https://github.com/iFindTA/PBVoipService.git", :tag => "#{s.version}" }
  s.source_files  = "PBVoipService/Pod/Classes/**/*.{h,m}"
  s.public_header_files = "PBVoipService/Pod/Classes/*.h","PBVoipService/Pod/Classes/Cores/*.h"
  s.preserve_paths  = 'PBVoipService/Pod/Classes/**/*'

  s.resources    = "PBVoipService/Pod/Assets/*.*"

  #s.libraries    = "CommonCrypto"
  s.frameworks  = "UIKit","Foundation","CoreTelephony","SystemConfiguration"
  # s.frameworks = "SomeFramework", "AnotherFramework"

  s.requires_arc = true

  header_search_paths   =['"$(SDKROOT)/usr/include"',
                          '"$(PODS_ROOT)/Headers/Public/PBVoipService/Cores"',
                          '"$(PODS_ROOT)/Headers/Public/PBPJSip/pjlib"',
                          '"$(PODS_ROOT)/Headers/Public/PBPJSip/pjlib-util"',
                          '"$(PODS_ROOT)/Headers/Public/PBPJSip/pjmedia"',
                          '"$(PODS_ROOT)/Headers/Public/PBPJSip/pjnath"',
                          '"$(PODS_ROOT)/Headers/Public/PBPJSip/pjsip"']

  s.xcconfig = {
    "HEADER_SEARCH_PATHS" => header_search_paths.join(' '),
    'GCC_PREPROCESSOR_DEFINITIONS' => 'PJ_AUTOCONF=1'
  }
  s.frameworks          = 'CFNetwork', 'AudioToolbox', 'AVFoundation', 'CoreMedia'
  s.libraries           = 'stdc++'
  s.header_mappings_dir  = 'PBVoipService/Pod/Classes'

  #s.dependency "JSONKit", "~> 1.4"
  s.dependency  'PBKits'
  s.dependency  'Masonry'
  s.dependency  'PBPJSip'
  s.dependency  'AFNetworking/Reachability'
end