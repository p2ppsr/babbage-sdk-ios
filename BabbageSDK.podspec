Pod::Spec.new do |s|
    s.name             = 'BabbageSDK'
    s.version          = '0.1.0'
    s.summary          = ' Build Babbage iOS apps in Swift.'
    s.homepage         = 'https://github.com/p2ppsr/babbage-sdk-ios'
    s.license          = { :type => 'OpenBSV', :file => 'LICENSE.md' }
    s.author           = { 'Peer-to-peer Privacy Systems Research, LLC' => 'ty@projectbabbage.com' }
    s.source           = { :git => 'https://github.com/p2ppsr/babbage-sdk-ios.git', :tag => s.version.to_s }
    s.ios.deployment_target = '15.0'
    s.swift_version = '5.0'
    s.source_files = 'Sources/BabbageSDK/**/*'
  end