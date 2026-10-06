Pod::Spec.new do |s|
  s.name             = 'whisper_cpp_flutter_plus'
  s.version          = '0.5.0'
  s.summary          = 'Flutter bindings for whisper.cpp.'
  s.description      = 'Offline Whisper transcription, translation, VAD and streaming audio capture.'
  s.homepage         = 'https://github.com/47gurvinder/whisper_cpp_flutter'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'Gurwinder Singh' => 'contact@gurwinderdevx.com' }
  s.source           = { :path => '.' }
  s.source_files = [
    'whisper_cpp_flutter_plus/Sources/whisper_cpp_flutter_plus/**/*.{h,m,mm,swift}',
    'whisper_cpp_flutter_plus/Sources/WhisperCppFlutterBridge/*.{h,cpp}'
  ]
  s.vendored_frameworks = 'whisper_cpp_flutter_plus/Frameworks/whisper.xcframework'
  s.public_header_files = 'whisper_cpp_flutter_plus/Sources/WhisperCppFlutterBridge/whisper_flutter.h'
  s.dependency 'Flutter'
  s.platform = :ios, '14.0'
  s.frameworks = 'AVFoundation', 'Accelerate', 'Metal', 'MetalKit', 'Foundation', 'CoreML'
  s.libraries = 'c++'
  s.requires_arc = [
    'whisper_cpp_flutter_plus/Sources/whisper_cpp_flutter_plus/**/*.swift'
  ]
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'SWIFT_ENABLE_EXPLICIT_MODULES' => 'NO'
  }
  s.swift_version = '5.0'
end
