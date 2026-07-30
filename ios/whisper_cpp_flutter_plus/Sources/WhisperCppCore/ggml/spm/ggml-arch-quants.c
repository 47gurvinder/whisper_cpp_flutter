#if defined(__aarch64__) || defined(__arm64__)
#include "../src/ggml-cpu/arch/arm/quants.c"
#elif defined(__x86_64__)
#include "../src/ggml-cpu/arch/x86/quants.c"
#else
#error "Unsupported iOS architecture"
#endif
