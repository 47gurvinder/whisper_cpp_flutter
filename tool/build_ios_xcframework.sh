#!/bin/bash

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
core_root="${project_root}/ios/whisper_cpp_flutter_plus/Sources/WhisperCppCore"
framework_root="${project_root}/ios/whisper_cpp_flutter_plus/Frameworks"
artifact="${core_root}/build-apple/whisper.xcframework"
destination="${framework_root}/whisper.xcframework"

(
    cd "${core_root}"
    IOS_ONLY=ON BUILD_STATIC_XCFRAMEWORK=ON ./build-xcframework.sh
)

rm -rf "${destination}"
mkdir -p "${framework_root}"
cp -R "${artifact}" "${destination}"

device_binary="${destination}/ios-arm64/whisper.framework/whisper"
if ! /usr/bin/nm -gU "${device_binary}" | grep '_ggml_metallib_start' > /dev/null; then
    echo "Embedded Metal library start symbol is missing" >&2
    exit 1
fi
if ! /usr/bin/nm -gU "${device_binary}" | grep '_ggml_metallib_end' > /dev/null; then
    echo "Embedded Metal library end symbol is missing" >&2
    exit 1
fi

echo "Created ${destination} with embedded Metal kernels."
