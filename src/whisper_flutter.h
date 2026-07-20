#pragma once
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
#if defined(_WIN32)
#define WF_API __declspec(dllexport)
#else
#define WF_API __attribute__((visibility("default"))) __attribute__((used))
#endif
WF_API void * wf_context_create(const char * model_path, int use_gpu, int flash_attn, int use_dtw, int dtw_model);
WF_API void wf_context_free(void * context);
WF_API void * wf_job_create(int strategy);
WF_API void wf_job_free(void * job);
WF_API void wf_job_set_int(void * job, const char * key, int64_t value);
WF_API void wf_job_set_double(void * job, const char * key, double value);
WF_API void wf_job_set_string(void * job, const char * key, const char * value);
WF_API void wf_job_cancel(void * job);
WF_API int wf_job_progress(void * job);
WF_API char * wf_run(void * context, void * job, const float * samples, int n_samples);
WF_API void * wf_vad_create(const char * model_path, int use_gpu, int threads);
WF_API void wf_vad_free(void * context);
WF_API int wf_vad_is_speech(void * context, const float * samples, int n_samples, int continuous);
WF_API void wf_vad_reset(void * context);
WF_API char * wf_vad_segments(void * context, const float * samples, int n_samples,
  float threshold, int min_speech_ms, int min_silence_ms, float max_speech_s,
  int speech_pad_ms, float samples_overlap);
WF_API const char * wf_last_error(void);
WF_API void wf_string_free(char * value);
WF_API const char * wf_version(void);
WF_API const char * wf_system_info(void);
WF_API char * wf_model_info(void * context);
WF_API char * wf_tokenize(void * context, const char * text);
WF_API char * wf_benchmark(int threads);
#ifdef __cplusplus
}
#endif
