#if defined(__aarch64__) || defined(__arm64__)
#include "../src/ggml-cpu/arch/arm/repack.cpp"
#elif defined(__x86_64__)
#include "../src/ggml-cpu/arch/x86/repack.cpp"
#else
#error "Unsupported iOS architecture"
#endif
