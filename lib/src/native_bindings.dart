import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

typedef _Ctx = Pointer<Void>;
typedef _Job = Pointer<Void>;

final class NativeBindings {
  NativeBindings._() : lib = Platform.isAndroid
      ? DynamicLibrary.open('libwhisper_flutter.so')
      : DynamicLibrary.process() {
    contextCreate = lib.lookupFunction<_Ctx Function(Pointer<Utf8>, Int32, Int32, Int32, Int32), _Ctx Function(Pointer<Utf8>, int, int, int, int)>('wf_context_create');
    contextFree = lib.lookupFunction<Void Function(_Ctx), void Function(_Ctx)>('wf_context_free');
    jobCreate = lib.lookupFunction<_Job Function(Int32), _Job Function(int)>('wf_job_create');
    jobFree = lib.lookupFunction<Void Function(_Job), void Function(_Job)>('wf_job_free');
    setInt = lib.lookupFunction<Void Function(_Job, Pointer<Utf8>, Int64), void Function(_Job, Pointer<Utf8>, int)>('wf_job_set_int');
    setDouble = lib.lookupFunction<Void Function(_Job, Pointer<Utf8>, Double), void Function(_Job, Pointer<Utf8>, double)>('wf_job_set_double');
    setString = lib.lookupFunction<Void Function(_Job, Pointer<Utf8>, Pointer<Utf8>), void Function(_Job, Pointer<Utf8>, Pointer<Utf8>)>('wf_job_set_string');
    run = lib.lookupFunction<Pointer<Utf8> Function(_Ctx, _Job, Pointer<Float>, Int32), Pointer<Utf8> Function(_Ctx, _Job, Pointer<Float>, int)>('wf_run');
    cancel = lib.lookupFunction<Void Function(_Job), void Function(_Job)>('wf_job_cancel');
    progress = lib.lookupFunction<Int32 Function(_Job), int Function(_Job)>('wf_job_progress');
    stringFree = lib.lookupFunction<Void Function(Pointer<Utf8>), void Function(Pointer<Utf8>)>('wf_string_free');
    lastError = lib.lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>('wf_last_error');
    vadCreate = lib.lookupFunction<Pointer<Void> Function(Pointer<Utf8>,Int32,Int32),Pointer<Void> Function(Pointer<Utf8>,int,int)>('wf_vad_create');
    vadFree = lib.lookupFunction<Void Function(Pointer<Void>),void Function(Pointer<Void>)>('wf_vad_free');
    vadIsSpeech = lib.lookupFunction<Int32 Function(Pointer<Void>,Pointer<Float>,Int32,Int32),int Function(Pointer<Void>,Pointer<Float>,int,int)>('wf_vad_is_speech');
    vadReset = lib.lookupFunction<Void Function(Pointer<Void>),void Function(Pointer<Void>)>('wf_vad_reset');
    vadSegments = lib.lookupFunction<Pointer<Utf8> Function(Pointer<Void>,Pointer<Float>,Int32,Float,Int32,Int32,Float,Int32,Float),Pointer<Utf8> Function(Pointer<Void>,Pointer<Float>,int,double,int,int,double,int,double)>('wf_vad_segments');
    version = lib.lookupFunction<Pointer<Utf8> Function(),Pointer<Utf8> Function()>('wf_version');
    systemInfo = lib.lookupFunction<Pointer<Utf8> Function(),Pointer<Utf8> Function()>('wf_system_info');
    modelInfo = lib.lookupFunction<Pointer<Utf8> Function(Pointer<Void>),Pointer<Utf8> Function(Pointer<Void>)>('wf_model_info');
    tokenize = lib.lookupFunction<Pointer<Utf8> Function(Pointer<Void>,Pointer<Utf8>),Pointer<Utf8> Function(Pointer<Void>,Pointer<Utf8>)>('wf_tokenize');
    benchmark = lib.lookupFunction<Pointer<Utf8> Function(Int32),Pointer<Utf8> Function(int)>('wf_benchmark');
  }
  static final instance = NativeBindings._();
  final DynamicLibrary lib;
  late final _Ctx Function(Pointer<Utf8>, int, int, int, int) contextCreate;
  late final void Function(_Ctx) contextFree;
  late final _Job Function(int) jobCreate;
  late final void Function(_Job) jobFree;
  late final void Function(_Job, Pointer<Utf8>, int) setInt;
  late final void Function(_Job, Pointer<Utf8>, double) setDouble;
  late final void Function(_Job, Pointer<Utf8>, Pointer<Utf8>) setString;
  late final Pointer<Utf8> Function(_Ctx, _Job, Pointer<Float>, int) run;
  late final void Function(_Job) cancel;
  late final int Function(_Job) progress;
  late final void Function(Pointer<Utf8>) stringFree;
  late final Pointer<Utf8> Function() lastError;
  late final Pointer<Void> Function(Pointer<Utf8>,int,int) vadCreate;
  late final void Function(Pointer<Void>) vadFree;
  late final int Function(Pointer<Void>,Pointer<Float>,int,int) vadIsSpeech;
  late final void Function(Pointer<Void>) vadReset;
  late final Pointer<Utf8> Function(Pointer<Void>,Pointer<Float>,int,double,int,int,double,int,double) vadSegments;
  late final Pointer<Utf8> Function() version, systemInfo;
  late final Pointer<Utf8> Function(Pointer<Void>) modelInfo;
  late final Pointer<Utf8> Function(Pointer<Void>,Pointer<Utf8>) tokenize;
  late final Pointer<Utf8> Function(int) benchmark;
}
