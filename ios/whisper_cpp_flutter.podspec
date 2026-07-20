Pod::Spec.new do |s|
  s.name             = 'whisper_cpp_flutter'
  s.version          = '0.1.0'
  s.summary          = 'Flutter bindings for whisper.cpp.'
  s.description      = 'Offline Whisper transcription, translation, VAD and streaming audio capture.'
  s.homepage         = 'https://github.com/47gurvinder/whisper_cpp_flutter'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'Gurwinder Singh' => 'contact@gurwinderdevx.com' }
  s.source           = { :path => '.' }
  s.source_files = [
    'Classes/**/*.{h,m,mm,swift}', '../src/*.{h,cpp}',
    '../third_party/whisper.cpp/src/whisper.cpp',
    '../third_party/whisper.cpp/src/coreml/*.{h,m,mm}',
    '../third_party/whisper.cpp/ggml/src/{ggml.c,ggml.cpp,ggml-alloc.c,ggml-backend.cpp,ggml-backend-reg.cpp,ggml-opt.cpp,ggml-quants.c,ggml-threading.cpp,gguf.cpp}',
    '../third_party/whisper.cpp/ggml/src/ggml-cpu/**/*.{c,cpp}',
    '../third_party/whisper.cpp/ggml/src/ggml-blas/ggml-blas.cpp',
    '../third_party/whisper.cpp/ggml/src/ggml-metal/*.{m,cpp}'
  ]
  s.resources = [
    '../third_party/whisper.cpp/ggml/src/ggml-metal/ggml-metal.metal',
    '../third_party/whisper.cpp/ggml/src/ggml-metal/ggml-metal-impl.h',
    '../third_party/whisper.cpp/ggml/src/ggml-common.h'
  ]
  s.public_header_files = '../src/whisper_flutter.h'
  s.dependency 'Flutter'
  s.platform = :ios, '14.0'
  s.frameworks = 'AVFoundation', 'Accelerate', 'Metal', 'MetalKit', 'Foundation', 'CoreML'
  s.libraries = 'c++'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) GGML_USE_CPU GGML_USE_BLAS GGML_USE_METAL WHISPER_USE_COREML WHISPER_COREML_ALLOW_FALLBACK ACCELERATE_NEW_LAPACK',
    'HEADER_SEARCH_PATHS' => '$(inherited) "${PODS_TARGET_SRCROOT}/../third_party/whisper.cpp/include" "${PODS_TARGET_SRCROOT}/../third_party/whisper.cpp/ggml/include" "${PODS_TARGET_SRCROOT}/../third_party/whisper.cpp/ggml/src" "${PODS_TARGET_SRCROOT}/../third_party/whisper.cpp/ggml/src/ggml-cpu" "${PODS_TARGET_SRCROOT}/../third_party/whisper.cpp/ggml/src/ggml-metal"'
  }
  s.swift_version = '5.0'
end
