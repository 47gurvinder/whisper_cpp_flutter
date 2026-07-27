// The declarations in this file are implementation details rather than part of
// the package's supported Dart API.
// ignore_for_file: public_member_api_docs

import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

typedef NativeContext = Pointer<Void>;
typedef NativeJob = Pointer<Void>;

final class NativeBindings {
  NativeBindings._()
      : lib = Platform.isAndroid
            ? DynamicLibrary.open('libwhisper_flutter.so')
            : DynamicLibrary.process() {
    contextCreate = lib.lookupFunction<
        NativeContext Function(Pointer<Utf8>, Int32, Int32, Int32, Int32),
        NativeContext Function(
            Pointer<Utf8>, int, int, int, int)>('wf_context_create');
    contextFree = lib.lookupFunction<Void Function(NativeContext),
        void Function(NativeContext)>('wf_context_free');
    jobCreate =
        lib.lookupFunction<NativeJob Function(Int32), NativeJob Function(int)>(
            'wf_job_create');
    jobFree =
        lib.lookupFunction<Void Function(NativeJob), void Function(NativeJob)>(
            'wf_job_free');
    setInt = lib.lookupFunction<Void Function(NativeJob, Pointer<Utf8>, Int64),
        void Function(NativeJob, Pointer<Utf8>, int)>('wf_job_set_int');
    setDouble = lib.lookupFunction<
        Void Function(NativeJob, Pointer<Utf8>, Double),
        void Function(NativeJob, Pointer<Utf8>, double)>('wf_job_set_double');
    setString = lib.lookupFunction<
        Void Function(NativeJob, Pointer<Utf8>, Pointer<Utf8>),
        void Function(
            NativeJob, Pointer<Utf8>, Pointer<Utf8>)>('wf_job_set_string');
    run = lib.lookupFunction<
        Pointer<Utf8> Function(NativeContext, NativeJob, Pointer<Float>, Int32),
        Pointer<Utf8> Function(
            NativeContext, NativeJob, Pointer<Float>, int)>('wf_run');
    cancel =
        lib.lookupFunction<Void Function(NativeJob), void Function(NativeJob)>(
            'wf_job_cancel');
    progress =
        lib.lookupFunction<Int32 Function(NativeJob), int Function(NativeJob)>(
            'wf_job_progress');
    stringFree = lib.lookupFunction<Void Function(Pointer<Utf8>),
        void Function(Pointer<Utf8>)>('wf_string_free');
    lastError =
        lib.lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
            'wf_last_error');
    vadCreate = lib.lookupFunction<
        Pointer<Void> Function(Pointer<Utf8>, Int32, Int32),
        Pointer<Void> Function(Pointer<Utf8>, int, int)>('wf_vad_create');
    vadFree = lib.lookupFunction<Void Function(Pointer<Void>),
        void Function(Pointer<Void>)>('wf_vad_free');
    vadIsSpeech = lib.lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Float>, Int32, Int32),
        int Function(
            Pointer<Void>, Pointer<Float>, int, int)>('wf_vad_is_speech');
    vadReset = lib.lookupFunction<Void Function(Pointer<Void>),
        void Function(Pointer<Void>)>('wf_vad_reset');
    vadSegments = lib.lookupFunction<
        Pointer<Utf8> Function(Pointer<Void>, Pointer<Float>, Int32, Float,
            Int32, Int32, Float, Int32, Float),
        Pointer<Utf8> Function(Pointer<Void>, Pointer<Float>, int, double, int,
            int, double, int, double)>('wf_vad_segments');
    version =
        lib.lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
            'wf_version');
    systemInfo =
        lib.lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
            'wf_system_info');
    modelInfo = lib.lookupFunction<Pointer<Utf8> Function(Pointer<Void>),
        Pointer<Utf8> Function(Pointer<Void>)>('wf_model_info');
    tokenize = lib.lookupFunction<
        Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>),
        Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>)>('wf_tokenize');
    benchmark = lib.lookupFunction<Pointer<Utf8> Function(Int32),
        Pointer<Utf8> Function(int)>('wf_benchmark');
  }
  static final instance = NativeBindings._();
  final DynamicLibrary lib;
  late final NativeContext Function(Pointer<Utf8>, int, int, int, int)
      contextCreate;
  late final void Function(NativeContext) contextFree;
  late final NativeJob Function(int) jobCreate;
  late final void Function(NativeJob) jobFree;
  late final void Function(NativeJob, Pointer<Utf8>, int) setInt;
  late final void Function(NativeJob, Pointer<Utf8>, double) setDouble;
  late final void Function(NativeJob, Pointer<Utf8>, Pointer<Utf8>) setString;
  late final Pointer<Utf8> Function(
      NativeContext, NativeJob, Pointer<Float>, int) run;
  late final void Function(NativeJob) cancel;
  late final int Function(NativeJob) progress;
  late final void Function(Pointer<Utf8>) stringFree;
  late final Pointer<Utf8> Function() lastError;
  late final Pointer<Void> Function(Pointer<Utf8>, int, int) vadCreate;
  late final void Function(Pointer<Void>) vadFree;
  late final int Function(Pointer<Void>, Pointer<Float>, int, int) vadIsSpeech;
  late final void Function(Pointer<Void>) vadReset;
  late final Pointer<Utf8> Function(Pointer<Void>, Pointer<Float>, int, double,
      int, int, double, int, double) vadSegments;
  late final Pointer<Utf8> Function() version, systemInfo;
  late final Pointer<Utf8> Function(Pointer<Void>) modelInfo;
  late final Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>) tokenize;
  late final Pointer<Utf8> Function(int) benchmark;
}
