#include "whisper_flutter.h"
#include "whisper.h"
#include <atomic>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <iomanip>
#include <sstream>
#include <string>
#include <vector>

namespace {
thread_local std::string error;
struct Job {
  whisper_full_params p;
  std::string language = "auto", prompt, suppress_regex, vad_model;
  std::atomic<bool> cancelled{false};
  std::atomic<int> progress{0};
  explicit Job(int strategy) : p(whisper_full_default_params(
      strategy == 1 ? WHISPER_SAMPLING_BEAM_SEARCH : WHISPER_SAMPLING_GREEDY)) {}
};
bool abort_cb(void * data) { return static_cast<Job *>(data)->cancelled.load(); }
void progress_cb(whisper_context *, whisper_state *, int progress, void * data) { static_cast<Job *>(data)->progress=progress; }
std::string esc(const char * s) {
  std::ostringstream o;
  for (; s && *s; ++s) switch (*s) {
    case '"': o << "\\\""; break; case '\\': o << "\\\\"; break;
    case '\n': o << "\\n"; break; case '\r': o << "\\r"; break;
    case '\t': o << "\\t"; break;
    default: if (static_cast<unsigned char>(*s) < 0x20) o << "\\u" << std::hex << std::setw(4) << std::setfill('0') << int(*s); else o << *s;
  }
  return o.str();
}
char * copy(const std::string & s) { auto *p=static_cast<char *>(std::malloc(s.size()+1)); if(p) std::memcpy(p,s.c_str(),s.size()+1); return p; }
}

void * wf_context_create(const char * path, int gpu, int flash, int dtw, int dtw_model) {
  auto p=whisper_context_default_params(); p.use_gpu=gpu!=0; p.flash_attn=flash!=0;
  p.dtw_token_timestamps=dtw!=0; p.dtw_aheads_preset=static_cast<whisper_alignment_heads_preset>(dtw_model);
  auto *ctx=whisper_init_from_file_with_params(path,p);
  if(!ctx) error="Unable to load whisper model: "+std::string(path?path:"");
  return ctx;
}
void wf_context_free(void *p){ if(p) whisper_free(static_cast<whisper_context *>(p)); }
void * wf_job_create(int strategy){ try{return new Job(strategy);}catch(...){error="Unable to allocate transcription job";return nullptr;} }
void wf_job_free(void *p){delete static_cast<Job *>(p);}
void wf_job_cancel(void *p){if(p) static_cast<Job *>(p)->cancelled=true;}
int wf_job_progress(void *p){return p?static_cast<Job *>(p)->progress.load():0;}

void wf_job_set_int(void * ptr,const char *k,int64_t v){auto &p=static_cast<Job *>(ptr)->p; std::string s(k);
  if(s=="threads")p.n_threads=v; else if(s=="translate")p.translate=v; else if(s=="detect_language")p.detect_language=v;
  else if(s=="offset_ms")p.offset_ms=v; else if(s=="duration_ms")p.duration_ms=v; else if(s=="max_text_ctx")p.n_max_text_ctx=v;
  else if(s=="max_len")p.max_len=v; else if(s=="max_tokens")p.max_tokens=v; else if(s=="audio_ctx")p.audio_ctx=v;
  else if(s=="token_timestamps")p.token_timestamps=v; else if(s=="split_on_word")p.split_on_word=v;
  else if(s=="suppress_blank")p.suppress_blank=v; else if(s=="suppress_nst")p.suppress_nst=v;
  else if(s=="single_segment")p.single_segment=v; else if(s=="no_context")p.no_context=v; else if(s=="no_timestamps")p.no_timestamps=v;
  else if(s=="print_special")p.print_special=v; else if(s=="greedy_best_of")p.greedy.best_of=v;
  else if(s=="tdrz")p.tdrz_enable=v; else if(s=="debug_mode")p.debug_mode=v; else if(s=="carry_initial_prompt")p.carry_initial_prompt=v;
  else if(s=="beam_size")p.beam_search.beam_size=v; else if(s=="vad")p.vad=v;
  else if(s=="vad_min_speech_ms")p.vad_params.min_speech_duration_ms=v; else if(s=="vad_min_silence_ms")p.vad_params.min_silence_duration_ms=v;
  else if(s=="vad_speech_pad_ms")p.vad_params.speech_pad_ms=v;
}
void wf_job_set_double(void *ptr,const char*k,double v){auto&p=static_cast<Job *>(ptr)->p;std::string s(k);
  if(s=="temperature")p.temperature=v; else if(s=="temperature_inc")p.temperature_inc=v; else if(s=="entropy_thold")p.entropy_thold=v;
  else if(s=="thold_pt")p.thold_pt=v; else if(s=="thold_ptsum")p.thold_ptsum=v; else if(s=="max_initial_ts")p.max_initial_ts=v; else if(s=="length_penalty")p.length_penalty=v;
  else if(s=="logprob_thold")p.logprob_thold=v; else if(s=="no_speech_thold")p.no_speech_thold=v;
  else if(s=="beam_patience")p.beam_search.patience=v; else if(s=="vad_threshold")p.vad_params.threshold=v;
  else if(s=="vad_max_speech_s")p.vad_params.max_speech_duration_s=v; else if(s=="vad_samples_overlap")p.vad_params.samples_overlap=v;
}
void wf_job_set_string(void *ptr,const char*k,const char*v){auto*j=static_cast<Job *>(ptr);std::string s(k);
  if(s=="language")j->language=v?v:"auto"; else if(s=="initial_prompt")j->prompt=v?v:"";
  else if(s=="suppress_regex")j->suppress_regex=v?v:""; else if(s=="vad_model_path")j->vad_model=v?v:"";
}

char * wf_run(void *c,void *jp,const float *samples,int n){auto*ctx=static_cast<whisper_context *>(c);auto*j=static_cast<Job *>(jp);
  if(!ctx||!j||!samples||n<=0){error="Invalid transcription arguments";return nullptr;}
  j->cancelled=false; j->progress=0; j->p.language=j->language.c_str(); j->p.initial_prompt=j->prompt.empty()?nullptr:j->prompt.c_str();
  j->p.suppress_regex=j->suppress_regex.empty()?nullptr:j->suppress_regex.c_str(); j->p.vad_model_path=j->vad_model.empty()?nullptr:j->vad_model.c_str();
  j->p.abort_callback=abort_cb; j->p.abort_callback_user_data=j;
  j->p.progress_callback=progress_cb; j->p.progress_callback_user_data=j;
  auto start=std::chrono::steady_clock::now(); int rc=whisper_full(ctx,j->p,samples,n);
  if(rc!=0){error=j->cancelled?"Transcription cancelled":"whisper_full failed with code "+std::to_string(rc);return nullptr;}
  int lang=whisper_full_lang_id(ctx); const char *lang_name=lang>=0?whisper_lang_str(lang):"unknown";
  std::ostringstream o; o<<"{\"language\":\""<<esc(lang_name)<<"\",\"language_probability\":-1,\"system_info\":\""<<esc(whisper_print_system_info())<<"\",\"segments\":[";
  std::string full; int ns=whisper_full_n_segments(ctx);
  for(int i=0;i<ns;i++){if(i)o<<',';const char*text=whisper_full_get_segment_text(ctx,i);full+=text;
    o<<"{\"text\":\""<<esc(text)<<"\",\"t0\":"<<whisper_full_get_segment_t0(ctx,i)*10<<",\"t1\":"<<whisper_full_get_segment_t1(ctx,i)*10
     <<",\"no_speech_p\":"<<whisper_full_get_segment_no_speech_prob(ctx,i)<<",\"speaker_turn_next\":"<<(whisper_full_get_segment_speaker_turn_next(ctx,i)?"true":"false")<<",\"tokens\":[";
    int nt=whisper_full_n_tokens(ctx,i);for(int t=0;t<nt;t++){if(t)o<<',';auto d=whisper_full_get_token_data(ctx,i,t);
      o<<"{\"id\":"<<d.id<<",\"text\":\""<<esc(whisper_full_get_token_text(ctx,i,t))<<"\",\"t0\":"<<whisper_full_get_token_t0(ctx,i,t)*10<<",\"t1\":"<<whisper_full_get_token_t1(ctx,i,t)*10<<",\"p\":"<<d.p<<",\"plog\":"<<d.plog<<",\"pt\":"<<d.pt<<",\"ptsum\":"<<d.ptsum<<",\"t_dtw\":"<<d.t_dtw*10<<",\"vlen\":"<<d.vlen<<'}';} o<<"]}";
  }
  auto us=std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now()-start).count();
  o<<"],\"text\":\""<<esc(full.c_str())<<"\",\"processing_us\":"<<us<<'}'; return copy(o.str());
}
void *wf_vad_create(const char *path,int gpu,int threads){auto p=whisper_vad_default_context_params();p.use_gpu=gpu;p.n_threads=threads;auto*c=whisper_vad_init_from_file_with_params(path,p);if(!c)error="Unable to load VAD model";return c;}
void wf_vad_free(void*p){if(p)whisper_vad_free(static_cast<whisper_vad_context *>(p));}
int wf_vad_is_speech(void*p,const float*s,int n,int continuous){if(!p||!s)return 0;auto*c=static_cast<whisper_vad_context *>(p);return continuous?whisper_vad_detect_speech_no_reset(c,s,n):whisper_vad_detect_speech(c,s,n);}
void wf_vad_reset(void*p){if(p)whisper_vad_reset_state(static_cast<whisper_vad_context *>(p));}
char *wf_vad_segments(void*p,const float*s,int n,float threshold,int minSpeech,int minSilence,float maxSpeech,int pad,float overlap){
  if(!p||!s){error="Invalid VAD arguments";return nullptr;}auto params=whisper_vad_default_params();params.threshold=threshold;params.min_speech_duration_ms=minSpeech;params.min_silence_duration_ms=minSilence;params.max_speech_duration_s=maxSpeech;params.speech_pad_ms=pad;params.samples_overlap=overlap;
  auto*segments=whisper_vad_segments_from_samples(static_cast<whisper_vad_context *>(p),params,s,n);if(!segments){error="VAD processing failed";return nullptr;}std::ostringstream o;o<<'[';int count=whisper_vad_segments_n_segments(segments);for(int i=0;i<count;i++){if(i)o<<',';o<<"{\"t0\":"<<whisper_vad_segments_get_segment_t0(segments,i)<<",\"t1\":"<<whisper_vad_segments_get_segment_t1(segments,i)<<'}';}o<<']';whisper_vad_free_segments(segments);return copy(o.str());
}
const char *wf_last_error(){return error.c_str();} void wf_string_free(char*p){std::free(p);}
const char *wf_version(){return whisper_version();} const char *wf_system_info(){return whisper_print_system_info();}
char *wf_model_info(void*p){if(!p)return nullptr;auto*c=static_cast<whisper_context *>(p);std::ostringstream o;o<<"{\"type\":\""<<esc(whisper_model_type_readable(c))<<"\",\"vocab\":"<<whisper_model_n_vocab(c)<<",\"audio_context\":"<<whisper_model_n_audio_ctx(c)<<",\"audio_state\":"<<whisper_model_n_audio_state(c)<<",\"audio_heads\":"<<whisper_model_n_audio_head(c)<<",\"audio_layers\":"<<whisper_model_n_audio_layer(c)<<",\"text_context\":"<<whisper_model_n_text_ctx(c)<<",\"text_state\":"<<whisper_model_n_text_state(c)<<",\"text_heads\":"<<whisper_model_n_text_head(c)<<",\"text_layers\":"<<whisper_model_n_text_layer(c)<<",\"mels\":"<<whisper_model_n_mels(c)<<",\"ftype\":"<<whisper_model_ftype(c)<<'}';return copy(o.str());}
char *wf_tokenize(void*p,const char*text){if(!p||!text)return nullptr;auto*c=static_cast<whisper_context *>(p);int n=whisper_tokenize(c,text,nullptr,0);if(n<0)n=-n;std::vector<whisper_token> tokens(n);int actual=whisper_tokenize(c,text,tokens.data(),n);if(actual<0){error="Tokenization failed";return nullptr;}std::ostringstream o;o<<'[';for(int i=0;i<actual;i++){if(i)o<<',';o<<tokens[i];}o<<']';return copy(o.str());}
char *wf_benchmark(int threads){std::ostringstream o;o<<"{\"memcpy\":\""<<esc(whisper_bench_memcpy_str(threads))<<"\",\"matrix_multiply\":\""<<esc(whisper_bench_ggml_mul_mat_str(threads))<<"\"}";return copy(o.str());}
