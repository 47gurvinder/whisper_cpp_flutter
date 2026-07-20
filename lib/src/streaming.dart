import 'dart:async';
import 'dart:typed_data';
import 'models.dart';
import 'whisper_engine.dart';

final class WhisperStreamSession {
  WhisperStreamSession(this.engine,{this.options=const TranscribeOptions(singleSegment:true,noContext:false),this.step=const Duration(seconds:2),this.window=const Duration(seconds:30)});
  final WhisperEngine engine;
  final TranscribeOptions options;
  final Duration step,window;
  final _samples=<double>[];
  final _results=StreamController<WhisperResult>.broadcast();
  bool _running=false,_closed=false;
  int _sinceRun=0;
  Stream<WhisperResult> get results=>_results.stream;
  void add(Float32List samples){if(_closed)throw StateError('Stream is closed');_samples.addAll(samples);_sinceRun+=samples.length;if(!_running&&_sinceRun>=step.inMilliseconds*16){_sinceRun=0;_process();}}
  Future<void> _process() async {_running=true;final max=window.inMilliseconds*16;if(_samples.length>max)_samples.removeRange(0,_samples.length-max);try{_results.add(await engine.transcribe(Float32List.fromList(_samples),options:options).result);}catch(e,s){_results.addError(e,s);}finally{_running=false;if(!_closed&&_sinceRun>=step.inMilliseconds*16){_sinceRun=0;_process();}}}
  Future<WhisperResult?> close() async {_closed=true;while(_running){await Future<void>.delayed(const Duration(milliseconds:50));}WhisperResult? finalResult;if(_samples.isNotEmpty)finalResult=await engine.transcribe(Float32List.fromList(_samples),options:options).result;await _results.close();return finalResult;}
}
