#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#
Pod::Spec.new do |s|
  s.name             = 'vorzela_audio_ios'
  s.version          = '0.1.0'
  s.summary          = 'AVPlayer audio backend for vorzela_audio'
  s.description      = 'Low-memory AVPlayer audio-only plugin'
  s.homepage         = 'https://github.com/vorzela/vorzela_audio'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Vorzela' => 'dev@vorzela.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
