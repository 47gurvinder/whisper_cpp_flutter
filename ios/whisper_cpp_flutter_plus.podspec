Pod::Spec.new do |s|
  s.name             = 'whisper_cpp_flutter_plus'
  s.version          = '0.4.1'
  s.summary          = 'Flutter bindings for whisper.cpp.'
  s.description      = 'Offline Whisper transcription, translation, VAD and streaming audio capture.'
  s.homepage         = 'https://github.com/47gurvinder/whisper_cpp_flutter'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'Gurwinder Singh' => 'contact@gurwinderdevx.com' }
  s.source           = { :path => '.' }
  s.source_files = [
    'whisper_cpp_flutter_plus/Sources/whisper_cpp_flutter_plus/**/*.{h,m,mm,swift}',
    'whisper_cpp_flutter_plus/Sources/WhisperCppFlutterBridge/*.{h,cpp}',
    'whisper_cpp_flutter_plus/Sources/WhisperCppCore/src/whisper.cpp',
    'whisper_cpp_flutter_plus/Sources/WhisperCppCore/src/coreml/*.{h,m,mm}',
    'whisper_cpp_flutter_plus/Sources/WhisperCppCore/ggml/src/{ggml.c,ggml.cpp,ggml-alloc.c,ggml-backend.cpp,ggml-backend-dl.cpp,ggml-backend-meta.cpp,ggml-backend-reg.cpp,ggml-opt.cpp,ggml-quants.c,ggml-threading.cpp,gguf.cpp}',
    'whisper_cpp_flutter_plus/Sources/WhisperCppCore/ggml/src/ggml-cpu/{ggml-cpu.c,ggml-cpu.cpp,repack.cpp,hbm.cpp,quants.c,traits.cpp,binary-ops.cpp,unary-ops.cpp,vec.cpp,ops.cpp}',
    'whisper_cpp_flutter_plus/Sources/WhisperCppCore/ggml/src/ggml-cpu/amx/{amx.cpp,mmq.cpp}',
    'whisper_cpp_flutter_plus/Sources/WhisperCppCore/ggml/spm/*.{c,cpp}',
    'whisper_cpp_flutter_plus/Sources/WhisperCppCore/ggml/src/ggml-blas/ggml-blas.cpp',
    'whisper_cpp_flutter_plus/Sources/WhisperCppCore/ggml/src/ggml-metal/*.{m,cpp}'
  ]
  s.resources = [
    'whisper_cpp_flutter_plus/Sources/WhisperCppCore/ggml/Resources/ggml-metal.txt',
    'whisper_cpp_flutter_plus/Sources/WhisperCppCore/ggml/src/ggml-metal/ggml-metal-impl.h',
    'whisper_cpp_flutter_plus/Sources/WhisperCppCore/ggml/src/ggml-common.h'
  ]
  s.public_header_files = 'whisper_cpp_flutter_plus/Sources/WhisperCppFlutterBridge/whisper_flutter.h'
  s.dependency 'Flutter'
  s.platform = :ios, '14.0'
  s.frameworks = 'AVFoundation', 'Accelerate', 'Metal', 'MetalKit', 'Foundation', 'CoreML'
  s.libraries = 'c++'
  s.requires_arc = [
    'whisper_cpp_flutter_plus/Sources/whisper_cpp_flutter_plus/**/*.swift',
    'whisper_cpp_flutter_plus/Sources/WhisperCppCore/src/coreml/*.{m,mm}'
  ]
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'SWIFT_ENABLE_EXPLICIT_MODULES' => 'NO',
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) GGML_USE_CPU GGML_USE_BLAS GGML_BLAS_USE_ACCELERATE GGML_USE_ACCELERATE GGML_USE_METAL WHISPER_USE_COREML WHISPER_COREML_ALLOW_FALLBACK ACCELERATE_NEW_LAPACK ACCELERATE_LAPACK_ILP64 WHISPER_VERSION=\"1.9.2\" GGML_VERSION=\"0.18.1\" GGML_COMMIT=\"unknown\"',
    'HEADER_SEARCH_PATHS' => '$(inherited) "${PODS_TARGET_SRCROOT}/whisper_cpp_flutter_plus/Sources/WhisperCppCore/include" "${PODS_TARGET_SRCROOT}/whisper_cpp_flutter_plus/Sources/WhisperCppCore/ggml/include" "${PODS_TARGET_SRCROOT}/whisper_cpp_flutter_plus/Sources/WhisperCppCore/ggml/src" "${PODS_TARGET_SRCROOT}/whisper_cpp_flutter_plus/Sources/WhisperCppCore/ggml/src/ggml-cpu" "${PODS_TARGET_SRCROOT}/whisper_cpp_flutter_plus/Sources/WhisperCppCore/ggml/src/ggml-metal"'
  }
  s.swift_version = '5.0'
end
