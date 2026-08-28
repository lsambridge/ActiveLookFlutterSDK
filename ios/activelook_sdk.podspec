#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint activelook_sdk.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'activelook_sdk'
  s.version          = '0.0.1'
  s.summary          = 'Flutter plugin wrapper for ActiveLook smart glasses.'
  s.description      = <<-DESC
Flutter bridge to ActiveLook's official iOS SDK (ActiveLook/ios-sdk).
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'activelook_sdk/Sources/activelook_sdk/**/*'
  s.dependency 'Flutter'
  # Per docs/plan-race-mode-activelook-glasses.md §7.4/§13.3: ActiveLook's official iOS SDK.
  # NOTE: ActiveLookSDK is not published to the public CocoaPods trunk (confirmed by reading
  # ActiveLook/ios-sdk's own ActiveLookSDK.podspec: it's a git-tag-sourced pod, never `pod push`ed).
  # Consuming apps must add this to their own Podfile for `pod install` to resolve this dependency:
  #   pod 'ActiveLookSDK', :git => 'https://github.com/ActiveLook/ios-sdk.git', :tag => '4.5.5'
  # See README.md "iOS setup" for the full Podfile snippet.
  s.dependency 'ActiveLookSDK'
  s.platform = :ios, '15.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'activelook_sdk_privacy' => ['activelook_sdk/Sources/activelook_sdk/PrivacyInfo.xcprivacy']}
end
