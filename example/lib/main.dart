import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:whisper_cpp_flutter_plus/whisper_cpp_flutter_plus.dart';

import 'diarization_page.dart';
import 'benchmark_page.dart';

void main() {
  runApp(const WhisperExampleApp());
}

TranscribeOptions buildExampleTranscribeOptions({
  required bool enableVad,
  required String? vadModelPath,
  bool tokenTimestamps = false,
  WhisperPerformanceMode? performanceMode,
}) {
  if (enableVad && vadModelPath == null) {
    throw StateError('The VAD model is not available.');
  }
  final options = TranscribeOptions(
    language: 'en',
    tokenTimestamps: tokenTimestamps,
    enableVad: enableVad,
    vadModelPath: enableVad ? vadModelPath : null,
  );
  return performanceMode == null
      ? options
      : options.withPerformanceMode(performanceMode);
}

class WhisperExampleApp extends StatelessWidget {
  const WhisperExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Whisper.cpp Flutter',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const TranscriptionPage(),
    );
  }
}

class TranscriptionPage extends StatefulWidget {
  const TranscriptionPage({super.key});

  @override
  State<TranscriptionPage> createState() => _TranscriptionPageState();
}

class _TranscriptionPageState extends State<TranscriptionPage> {
  static const _whisperModelName = 'ggml-tiny.en.bin';
  static final _whisperModelUrl = Uri.parse(
    'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/'
    'ggml-tiny.en.bin',
  );
  static const _vadModelName = 'ggml-silero-v6.2.0.bin';
  static final _vadModelUrl = Uri.parse(
    'https://huggingface.co/ggml-org/whisper-vad/resolve/main/'
    'ggml-silero-v6.2.0.bin',
  );

  final _modelManager = WhisperModelManager();
  final _recorder = WhisperRecorder();
  final _samples = <double>[];

  WhisperEngine? _engine;
  WhisperTask? _task;
  WhisperStreamTask? _streamTask;
  StreamSubscription<RecordingChunk>? _recordingSubscription;
  StreamSubscription<int>? _progressSubscription;
  StreamSubscription<WhisperStreamUpdate>? _streamSubscription;

  String _status = 'Checking for downloaded models…';
  String _confirmedTranscript = '';
  String _partialTranscript = '';
  String? _error;
  String? _vadModelPath;
  double? _downloadProgress;
  int _transcriptionProgress = 0;
  bool _isDownloading = false;
  bool _isLoading = false;
  bool _isRecording = false;
  bool _isTranscribing = false;
  bool _isStartingLive = false;
  bool _isLiveTranscribing = false;
  bool _hasModels = false;
  bool _enableVad = true;
  WhisperPerformanceMode _performanceMode = WhisperPerformanceMode.balanced;

  bool get _isBusy =>
      _isDownloading || _isLoading || _isTranscribing || _isStartingLive;

  @override
  void initState() {
    super.initState();
    unawaited(_findAndLoadModels());
  }

  Future<void> _findAndLoadModels() async {
    try {
      final whisperModel = await _modelManager.find(_whisperModelName);
      final vadModel = await _modelManager.find(_vadModelName);
      if (!mounted) return;
      if (whisperModel == null || vadModel == null) {
        final missing = whisperModel == null && vadModel == null
            ? 'the Whisper and Silero VAD models'
            : whisperModel == null
                ? 'the tiny English Whisper model'
                : 'the Silero VAD model';
        setState(() {
          _status = 'Download $missing to begin.';
          _hasModels = false;
          _vadModelPath = null;
        });
        return;
      }
      setState(() {
        _hasModels = true;
        _vadModelPath = vadModel.path;
      });
      await _loadModel(whisperModel.path);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _hasModels = false;
        _vadModelPath = null;
      });
      _showError('Could not check the model directory', error);
    }
  }

  Future<void> _downloadModels() async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = null;
      _error = null;
      _status = 'Checking required models…';
    });

    try {
      if (await _modelManager.find(_whisperModelName) == null) {
        await _downloadModel(_whisperModelUrl, _whisperModelName);
        if (!mounted) return;
      }
      if (await _modelManager.find(_vadModelName) == null) {
        await _downloadModel(_vadModelUrl, _vadModelName);
        if (!mounted) return;
      }
      final whisperModel = await _modelManager.find(_whisperModelName);
      final vadModel = await _modelManager.find(_vadModelName);
      if (whisperModel == null || vadModel == null) {
        throw StateError('One or more downloaded models were not found.');
      }
      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _downloadProgress = null;
        _hasModels = true;
        _vadModelPath = vadModel.path;
      });
      await _loadModel(whisperModel.path);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _downloadProgress = null;
        _hasModels = false;
        _vadModelPath = null;
      });
      _showError('Model download failed', error);
    }
  }

  Future<void> _downloadModel(Uri url, String name) async {
    if (mounted) {
      setState(() {
        _downloadProgress = null;
        _status = 'Downloading $name…';
      });
    }
    await for (final progress in _modelManager.download(url, name)) {
      if (!mounted) return;
      setState(() => _downloadProgress = progress.fraction);
    }
  }

  Future<void> _loadModel(String path) async {
    setState(() {
      _isLoading = true;
      _error = null;
      _status = 'Loading $_whisperModelName…';
    });
    try {
      final engine = await WhisperEngine.load(path);
      if (!mounted) {
        engine.dispose();
        return;
      }
      _engine?.dispose();
      setState(() {
        _engine = engine;
        _isLoading = false;
        _status = 'Models ready. Tap Record and speak English.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _vadModelPath = null;
      });
      _showError('Could not load the model', error);
    }
  }

  Future<void> _startRecording() async {
    if (_engine == null) return;
    try {
      final granted = await _recorder.requestPermission();
      if (!granted) {
        throw StateError('Microphone permission was not granted.');
      }
      _samples.clear();
      final stream = await _recorder.start();
      _recordingSubscription = stream.listen(
        (chunk) => _samples.addAll(chunk.samples),
        onError: (Object error) {
          if (mounted) _showError('Recording failed', error);
        },
      );
      if (!mounted) return;
      setState(() {
        _isRecording = true;
        _confirmedTranscript = '';
        _partialTranscript = '';
        _error = null;
        _status = 'Recording… tap Stop when you finish speaking.';
      });
    } catch (error) {
      _showError('Could not start recording', error);
    }
  }

  Future<void> _stopAndTranscribe() async {
    try {
      await _recorder.stop();
      await _recordingSubscription?.cancel();
      _recordingSubscription = null;
      if (!mounted) return;
      setState(() => _isRecording = false);

      if (_samples.isEmpty) {
        throw StateError('No microphone samples were captured.');
      }
      await _transcribe(Float32List.fromList(_samples));
    } catch (error) {
      if (mounted) _showError('Could not transcribe the recording', error);
    }
  }

  Future<void> _transcribe(Float32List samples) async {
    final engine = _engine;
    if (engine == null) return;
    setState(() {
      _isTranscribing = true;
      _transcriptionProgress = 0;
      _error = null;
      _status = 'Transcribing locally on this device…';
    });

    try {
      final task = engine.transcribe(
        samples,
        options: buildExampleTranscribeOptions(
          enableVad: _enableVad,
          vadModelPath: _vadModelPath,
          performanceMode: _performanceMode,
        ),
      );
      _task = task;
      _progressSubscription = task.progress.listen((progress) {
        if (mounted) setState(() => _transcriptionProgress = progress);
      });
      final result = await task.result;
      if (!mounted) return;
      setState(() {
        _confirmedTranscript = result.text.trim();
        _partialTranscript = '';
        _status = 'Finished in '
            '${(result.processingTime.inMilliseconds / 1000).toStringAsFixed(1)}s.';
      });
    } catch (error) {
      if (mounted) _showError('Transcription failed', error);
    } finally {
      await _progressSubscription?.cancel();
      _progressSubscription = null;
      _task = null;
      if (mounted) setState(() => _isTranscribing = false);
    }
  }

  void _cancelTranscription() {
    _task?.cancel();
    setState(() => _status = 'Cancelling transcription…');
  }

  Future<void> _startLiveTranscription() async {
    final engine = _engine;
    if (engine == null) return;
    setState(() {
      _isStartingLive = true;
      _confirmedTranscript = '';
      _partialTranscript = '';
      _error = null;
      _status = 'Requesting microphone access…';
    });
    try {
      final task = await engine.transcribeMicrophone(
        options: buildExampleTranscribeOptions(
          enableVad: _enableVad,
          vadModelPath: _vadModelPath,
        ),
      );
      if (!mounted) {
        await task.cancel();
        engine.dispose();
        return;
      }
      _streamTask = task;
      _streamSubscription = task.updates.listen(
        (update) {
          if (!mounted) return;
          setState(() {
            _confirmedTranscript = update.confirmedText.trimLeft();
            _partialTranscript = update.partialText;
            _status = update.isFinal
                ? 'Live transcription finished.'
                : 'Listening and transcribing locally…';
          });
        },
        onError: (Object error) {
          if (!mounted) return;
          setState(() {
            _isLiveTranscribing = false;
            _streamTask = null;
          });
          _showError('Live transcription failed', error);
        },
      );
      setState(() {
        _isStartingLive = false;
        _isLiveTranscribing = true;
        _status = 'Listening… live text will appear as you speak.';
      });
    } catch (error) {
      if (!mounted) {
        engine.dispose();
        return;
      }
      setState(() => _isStartingLive = false);
      _showError('Could not start live transcription', error);
    }
  }

  Future<void> _stopLiveTranscription() async {
    final task = _streamTask;
    if (task == null) return;
    setState(() => _status = 'Finishing the live transcript…');
    try {
      final complete = await task.stop();
      if (!mounted) return;
      setState(() {
        _confirmedTranscript = complete.confirmedText.trim();
        _partialTranscript = '';
        _isLiveTranscribing = false;
        _streamTask = null;
        _status = 'Live transcription finished.';
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _isLiveTranscribing = false;
          _streamTask = null;
        });
        _showError('Could not finish live transcription', error);
      }
    } finally {
      await _streamSubscription?.cancel();
      _streamSubscription = null;
    }
  }

  Future<void> _openBenchmark() async {
    if (_isBusy || _isRecording || _isLiveTranscribing) return;
    _engine?.dispose();
    setState(() {
      _engine = null;
      _status = 'Benchmark opened; the transcription model was unloaded.';
    });
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const BenchmarkPage()),
    );
    if (mounted) unawaited(_findAndLoadModels());
  }

  void _showError(String message, Object error) {
    if (!mounted) return;
    setState(() {
      _error = '$message: $error';
      _status = message;
    });
  }

  @override
  void dispose() {
    final engine = _engine;
    final streamTask = _streamTask;
    _modelManager.close();
    unawaited(_recordingSubscription?.cancel());
    unawaited(_progressSubscription?.cancel());
    unawaited(_streamSubscription?.cancel());
    if (_isRecording) unawaited(_recorder.stop());
    _task?.cancel();
    if (streamTask != null) {
      unawaited(streamTask.cancel().whenComplete(() => engine?.dispose()));
    } else if (_isStartingLive) {
      // The pending start path observes !mounted and disposes the engine.
    } else if (!_isTranscribing) {
      engine?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Whisper.cpp Flutter'),
        actions: [
          TextButton.icon(
            onPressed: _isBusy || _isRecording || _isLiveTranscribing
                ? null
                : _openBenchmark,
            icon: const Icon(Icons.speed),
            label: const Text('Benchmark'),
          ),
          TextButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const DiarizationPage(),
              ),
            ),
            icon: const Icon(Icons.record_voice_over),
            label: const Text('Diarization'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Offline speech to text',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Download a model once, then transcribe a complete recording '
              'or watch live text appear while you speak. Silero voice '
              'activity detection can filter silence before transcription.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const DiarizationPage(),
                  ),
                ),
                icon: const Icon(Icons.groups),
                label: const Text('Try local diarization'),
              ),
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(_status),
                    if (_isDownloading) ...[
                      const SizedBox(height: 12),
                      LinearProgressIndicator(value: _downloadProgress),
                      const SizedBox(height: 8),
                      Text(
                        _downloadProgress == null
                            ? 'Starting download…'
                            : '${(_downloadProgress! * 100).toStringAsFixed(0)}%',
                      ),
                    ],
                    if (_isLoading) ...[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(),
                    ],
                    if (_isTranscribing) ...[
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        value: _transcriptionProgress / 100,
                      ),
                      const SizedBox(height: 8),
                      Text('$_transcriptionProgress%'),
                    ],
                  ],
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_error!),
                ),
              ),
            ],
            const SizedBox(height: 20),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Voice activity detection'),
              subtitle: const Text('Filter silence with the Silero VAD model.'),
              value: _enableVad,
              onChanged: _isBusy || _isRecording || _isLiveTranscribing
                  ? null
                  : (value) => setState(() => _enableVad = value),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<WhisperPerformanceMode>(
              initialValue: _performanceMode,
              decoration: const InputDecoration(
                labelText: 'Offline performance mode',
                helperText: 'Applies to completed recordings, not live text.',
                border: OutlineInputBorder(),
              ),
              items: WhisperPerformanceMode.values
                  .map(
                    (mode) => DropdownMenuItem(
                      value: mode,
                      child: Text(_performanceModeLabel(mode)),
                    ),
                  )
                  .toList(growable: false),
              onChanged: _isBusy || _isRecording || _isLiveTranscribing
                  ? null
                  : (mode) {
                      if (mode != null) {
                        setState(() => _performanceMode = mode);
                      }
                    },
            ),
            const SizedBox(height: 12),
            if (!_hasModels)
              FilledButton.icon(
                onPressed: _isBusy ? null : _downloadModels,
                icon: const Icon(Icons.download),
                label: const Text('Download required models'),
              )
            else if (_engine == null)
              FilledButton.icon(
                onPressed: _isBusy ? null : _findAndLoadModels,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry loading model'),
              )
            else if (_isRecording)
              FilledButton.icon(
                onPressed: _stopAndTranscribe,
                icon: const Icon(Icons.stop),
                label: const Text('Stop and transcribe'),
              )
            else if (_isLiveTranscribing)
              FilledButton.icon(
                onPressed: _stopLiveTranscription,
                icon: const Icon(Icons.stop_circle),
                label: const Text('Stop live transcription'),
              )
            else if (_isTranscribing)
              OutlinedButton.icon(
                onPressed: _cancelTranscription,
                icon: const Icon(Icons.cancel),
                label: const Text('Cancel transcription'),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    onPressed: _isBusy ? null : _startRecording,
                    icon: const Icon(Icons.mic),
                    label: const Text('Record, then transcribe'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _isBusy ? null : _startLiveTranscription,
                    icon: const Icon(Icons.graphic_eq),
                    label: const Text('Transcribe live'),
                  ),
                ],
              ),
            const SizedBox(height: 28),
            Text('Transcript', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(minHeight: 160),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(12),
              ),
              child: _confirmedTranscript.isEmpty && _partialTranscript.isEmpty
                  ? const SelectableText('Your transcription will appear here.')
                  : SelectableText.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: _confirmedTranscript),
                          TextSpan(
                            text: _partialTranscript,
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

String _performanceModeLabel(WhisperPerformanceMode mode) => switch (mode) {
      WhisperPerformanceMode.responsive => 'Responsive',
      WhisperPerformanceMode.balanced => 'Balanced',
      WhisperPerformanceMode.efficient => 'Efficient',
    };
