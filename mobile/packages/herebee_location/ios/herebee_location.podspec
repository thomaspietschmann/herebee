Pod::Spec.new do |s|
  s.name             = 'herebee_location'
  s.version          = '0.1.0'
  s.summary          = 'Foreground and background location for HereBee.'
  s.description      = <<-DESC
CoreLocation only. No third-party SDKs, no analytics; the plugin never touches
the network, so no coordinate exists in native code in a form it could send.
                       DESC
  s.homepage         = 'https://herebee.app'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'HereBee' => 'noreply@herebee.app' }
  s.source           = { :path => '.' }
  s.source_files = 'herebee_location/Sources/herebee_location/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '16.0'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
  s.resource_bundles = {'herebee_location_privacy' => ['herebee_location/Sources/herebee_location/PrivacyInfo.xcprivacy']}
end
