import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:whisper_cpp_flutter/whisper_cpp_flutter.dart';

void main() {
  runApp(const WhisperExampleApp());
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
  static const _modelName = 'ggml-tiny.en.bin';
  static final _modelUrl = Uri.parse(
    'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/'
    'ggml-tiny.en.bin',
  );

  final _modelManager = WhisperModelManager();
  final _recorder = WhisperRecorder();
  final _samples = <double>[];

  WhisperEngine? _engine;
  WhisperTask? _task;
  StreamSubscription<RecordingChunk>? _recordingSubscription;
  StreamSubscription<int>? _progressSubscription;

  String _status = 'Checking for a downloaded model…';
  String _transcript = '';
  String? _error;
  double? _downloadProgress;
  int _transcriptionProgress = 0;
  bool _isDownloading = false;
  bool _isLoading = false;
  bool _isRecording = false;
  bool _isTranscribing = false;
  bool _hasModel = false;

  bool get _isBusy => _isDownloading || _isLoading || _isTranscribing;

  @override
  void initState() {
    super.initState();
    unawaited(_findAndLoadModel());
  }

  Future<void> _findAndLoadModel() async {
    try {
      final model = await _modelManager.find(_modelName);
      if (!mounted) return;
      if (model == null) {
        setState(() {
          _status = 'Download the tiny English model to begin.';
          _hasModel = false;
        });
        return;
      }
      setState(() => _hasModel = true);
      await _loadModel(model.path);
    } catch (error) {
      _showError('Could not check the model directory', error);
    }
  }

  Future<void> _downloadModel() async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = null;
      _error = null;
      _status = 'Downloading $_modelName…';
    });

    try {
      await for (final progress in _modelManager.download(
        _modelUrl,
        _modelName,
      )) {
        if (!mounted) return;
        setState(() => _downloadProgress = progress.fraction);
      }
      final model = await _modelManager.find(_modelName);
      if (model == null) {
        throw StateError('The downloaded model was not found.');
      }
      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _hasModel = true;
      });
      await _loadModel(model.path);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isDownloading = false);
      _showError('Model download failed', error);
    }
  }

  Future<void> _loadModel(String path) async {
    setState(() {
      _isLoading = true;
      _error = null;
      _status = 'Loading $_modelName…';
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
        _status = 'Model ready. Tap Record and speak English.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
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
        _transcript = '';
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
        options: const TranscribeOptions(
          language: 'en',
          tokenTimestamps: true,
        ),
      );
      _task = task;
      _progressSubscription = task.progress.listen((progress) {
        if (mounted) setState(() => _transcriptionProgress = progress);
      });
      final result = await task.result;
      if (!mounted) return;
      setState(() {
        _transcript = result.text.trim();
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

  void _showError(String message, Object error) {
    if (!mounted) return;
    setState(() {
      _error = '$message: $error';
      _status = message;
    });
  }

  @override
  void dispose() {
    unawaited(_recordingSubscription?.cancel());
    unawaited(_progressSubscription?.cancel());
    if (_isRecording) unawaited(_recorder.stop());
    _task?.cancel();
    if (!_isTranscribing) _engine?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Whisper.cpp Flutter')),
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
              'Download a model once, then record and transcribe without '
              'sending audio to a server.',
              style: Theme.of(context).textTheme.bodyLarge,
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
            if (!_hasModel)
              FilledButton.icon(
                onPressed: _isBusy ? null : _downloadModel,
                icon: const Icon(Icons.download),
                label: const Text('Download tiny English model (~75 MB)'),
              )
            else if (_engine == null)
              FilledButton.icon(
                onPressed: _isBusy ? null : _findAndLoadModel,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry loading model'),
              )
            else if (_isRecording)
              FilledButton.icon(
                onPressed: _stopAndTranscribe,
                icon: const Icon(Icons.stop),
                label: const Text('Stop and transcribe'),
              )
            else if (_isTranscribing)
              OutlinedButton.icon(
                onPressed: _cancelTranscription,
                icon: const Icon(Icons.cancel),
                label: const Text('Cancel transcription'),
              )
            else
              FilledButton.icon(
                onPressed: _startRecording,
                icon: const Icon(Icons.mic),
                label: const Text('Record'),
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
              child: SelectableText(
                _transcript.isEmpty
                    ? 'Your transcription will appear here.'
                    : _transcript,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
