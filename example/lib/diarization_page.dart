import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:whisper_cpp_flutter_plus/whisper_cpp_flutter_plus.dart';

TranscribeOptions buildDiarizationOptions() => const TranscribeOptions(
      language: 'en',
      tokenTimestamps: true,
      tinyDiarize: true,
    );

class DiarizationPage extends StatefulWidget {
  const DiarizationPage({super.key});

  @override
  State<DiarizationPage> createState() => _DiarizationPageState();
}

class _DiarizationPageState extends State<DiarizationPage> {
  static const _modelName = 'ggml-small.en-tdrz.bin';
  static final _modelUrl = Uri.parse(
    'https://huggingface.co/akashmjn/tinydiarize-whisper.cpp/'
    'resolve/main/ggml-small.en-tdrz.bin',
  );

  final _modelManager = WhisperModelManager();
  final _recorder = WhisperRecorder();
  final _samples = <double>[];

  WhisperEngine? _engine;
  WhisperTask? _task;
  StreamSubscription<RecordingChunk>? _recordingSubscription;
  StreamSubscription<int>? _progressSubscription;

  String _status = 'Checking for the TinyDiarize model…';
  String? _error;
  List<WhisperSegment> _segments = const [];
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
          _hasModel = false;
          _status = 'Download the TinyDiarize model to begin.';
        });
        return;
      }
      setState(() => _hasModel = true);
      await _loadModel(model.path);
    } catch (error) {
      if (mounted) _showError('Could not check the model directory', error);
    }
  }

  Future<void> _downloadModel() async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = null;
      _error = null;
      _status = 'Downloading the TinyDiarize model (about 465 MB)…';
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
        _downloadProgress = null;
        _hasModel = true;
      });
      await _loadModel(model.path);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _downloadProgress = null;
        _hasModel = false;
      });
      _showError('Model download failed', error);
    }
  }

  Future<void> _loadModel(String path) async {
    setState(() {
      _isLoading = true;
      _error = null;
      _status = 'Loading the TinyDiarize model…';
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
        _status = 'Ready. Record a conversation between two speakers.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError('Could not load the TinyDiarize model', error);
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
        _segments = const [];
        _error = null;
        _status = 'Recording both speakers…';
      });
    } catch (error) {
      if (mounted) _showError('Could not start recording', error);
    }
  }

  Future<void> _stopAndDiarize() async {
    try {
      await _recorder.stop();
      await _recordingSubscription?.cancel();
      _recordingSubscription = null;
      if (!mounted) return;
      setState(() => _isRecording = false);
      if (_samples.isEmpty) {
        throw StateError('No microphone samples were captured.');
      }
      await _diarize(Float32List.fromList(_samples));
    } catch (error) {
      if (mounted) _showError('Could not process the recording', error);
    }
  }

  Future<void> _diarize(Float32List samples) async {
    final engine = _engine;
    if (engine == null) return;
    setState(() {
      _isTranscribing = true;
      _transcriptionProgress = 0;
      _error = null;
      _status = 'Detecting speech and speaker turns on this device…';
    });
    try {
      final task = engine.transcribe(
        samples,
        options: buildDiarizationOptions(),
      );
      _task = task;
      _progressSubscription = task.progress.listen((progress) {
        if (mounted) setState(() => _transcriptionProgress = progress);
      });
      final result = await task.result;
      if (!mounted) return;
      setState(() {
        _segments = result.segments;
        _status = 'Finished locally in '
            '${(result.processingTime.inMilliseconds / 1000).toStringAsFixed(1)}s.';
      });
    } catch (error) {
      if (mounted) _showError('Diarization failed', error);
    } finally {
      await _progressSubscription?.cancel();
      _progressSubscription = null;
      _task = null;
      if (mounted) setState(() => _isTranscribing = false);
    }
  }

  void _cancelDiarization() {
    _task?.cancel();
    setState(() => _status = 'Cancelling diarization…');
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
    _modelManager.close();
    unawaited(_recordingSubscription?.cancel());
    unawaited(_progressSubscription?.cancel());
    if (_isRecording) unawaited(_recorder.stop());
    _task?.cancel();
    if (_isTranscribing && _task != null) {
      unawaited(
        _task!.result.then<void>(
          (_) => engine?.dispose(),
          onError: (_) => engine?.dispose(),
        ),
      );
    } else {
      engine?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Local diarization')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: colors.primaryContainer,
                  child: Icon(
                    Icons.groups,
                    size: 30,
                    color: colors.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Who spoke when?',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 4),
                      const Text('Private, offline speaker-turn detection'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Card(
              color: colors.secondaryContainer,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'TinyDiarize detects changes between two voices. '
                        'Voice labels alternate at each detected turn; they '
                        'are not persistent speaker identities.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
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
                color: colors.errorContainer,
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
                label: const Text('Download diarization model'),
              )
            else if (_engine == null)
              FilledButton.icon(
                onPressed: _isBusy ? null : _findAndLoadModel,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry loading model'),
              )
            else if (_isRecording)
              FilledButton.icon(
                onPressed: _stopAndDiarize,
                icon: const Icon(Icons.stop),
                label: const Text('Stop and detect speakers'),
              )
            else if (_isTranscribing)
              OutlinedButton.icon(
                onPressed: _cancelDiarization,
                icon: const Icon(Icons.cancel),
                label: const Text('Cancel diarization'),
              )
            else
              FilledButton.icon(
                onPressed: _isBusy ? null : _startRecording,
                icon: const Icon(Icons.mic),
                label: const Text('Record a conversation'),
              ),
            const SizedBox(height: 28),
            Row(
              children: [
                Text(
                  'Conversation',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                if (_segments.isNotEmpty)
                  Text(
                    '${_segments.length} segments',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (_segments.isEmpty)
              Container(
                constraints: const BoxConstraints(minHeight: 140),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Text(
                    'Detected speaker turns will appear here.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              ..._buildConversation(),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildConversation() {
    var speaker = 0;
    final cards = <Widget>[];
    for (final segment in _segments) {
      cards.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _SpeakerTurnCard(segment: segment, speaker: speaker),
        ),
      );
      if (segment.speakerTurnNext) speaker = 1 - speaker;
    }
    return cards;
  }
}

class _SpeakerTurnCard extends StatelessWidget {
  const _SpeakerTurnCard({required this.segment, required this.speaker});

  final WhisperSegment segment;
  final int speaker;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isVoiceA = speaker == 0;
    final accent = isVoiceA ? colors.primary : colors.tertiary;
    final background =
        isVoiceA ? colors.primaryContainer : colors.tertiaryContainer;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: background,
              foregroundColor: accent,
              child: Text(isVoiceA ? 'A' : 'B'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        isVoiceA ? 'Voice A' : 'Voice B',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: accent,
                            ),
                      ),
                      const Spacer(),
                      Text(
                        '${_formatTime(segment.start)} – '
                        '${_formatTime(segment.end)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SelectableText(
                    segment.text.trim(),
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(Duration value) {
    final minutes = value.inMinutes.toString().padLeft(2, '0');
    final seconds = (value.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
