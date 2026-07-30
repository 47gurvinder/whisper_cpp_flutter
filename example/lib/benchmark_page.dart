import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:whisper_cpp_flutter_plus/whisper_cpp_flutter_plus.dart';
// Benchmark report models are intentionally internal to the repository tooling.
// ignore: implementation_imports
import 'package:whisper_cpp_flutter_plus/src/benchmark_report.dart';

import 'benchmark/benchmark_runner.dart';

class BenchmarkPage extends StatefulWidget {
  const BenchmarkPage({super.key, this.initialReport});

  final WhisperBenchmarkReport? initialReport;

  @override
  State<BenchmarkPage> createState() => _BenchmarkPageState();
}

class _BenchmarkPageState extends State<BenchmarkPage> {
  final _runner = const WhisperBenchmarkRunner();
  final _audioPlayer = AudioPlayer();
  late final StreamSubscription<PlayerState> _playerStateSubscription;
  bool _running = false;
  bool _isPlayingAudio = false;
  String _status = 'Ready to run the canonical benchmark.';
  double? _progress;
  String? _error;
  String? _savedPath;
  WhisperBenchmarkReport? _report;
  BenchmarkRunController? _controller;

  @override
  void initState() {
    super.initState();
    _report = widget.initialReport;
    _playerStateSubscription =
        _audioPlayer.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() => _isPlayingAudio = state == PlayerState.playing);
    });
  }

  Future<void> _run() async {
    if (_running) return;
    await _stopAudio();
    setState(() {
      _running = true;
      _error = null;
      _savedPath = null;
      _report = null;
      _progress = null;
      _controller = BenchmarkRunController();
    });
    try {
      final model = await _runner.resolveCanonicalModel(
        controller: _controller!,
        onProgress: _update,
      );
      final report = await _runner.run(
        modelFile: model,
        controller: _controller!,
        onProgress: _update,
      );
      final modelManager = WhisperModelManager();
      late final Directory modelDirectory;
      try {
        modelDirectory = await modelManager.directory;
      } finally {
        modelManager.close();
      }
      final directory = Directory('${modelDirectory.path}/benchmarks');
      await directory.create(recursive: true);
      final safeTime = report.createdAtUtc
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final file = File('${directory.path}/manual-$safeTime.json');
      await file.writeAsString(report.encode(pretty: true), flush: true);
      if (!mounted) return;
      setState(() {
        _report = report;
        _savedPath = file.path;
        _status = 'Benchmark complete.';
        _progress = 1;
      });
    } on BenchmarkCancelledException {
      if (!mounted) return;
      setState(() {
        _error = null;
        _status = 'Benchmark cancelled.';
        _progress = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _status = 'Benchmark failed.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
          _controller = null;
        });
      }
    }
  }

  void _cancel() {
    final controller = _controller;
    if (controller == null || controller.isCancelled) return;
    controller.cancel();
    setState(() {
      _status = 'Cancelling benchmark…';
      _progress = null;
    });
  }

  Future<void> _toggleAudio() async {
    try {
      if (_isPlayingAudio) {
        await _stopAudio();
      } else {
        await _audioPlayer.play(
          AssetSource('benchmark/jfk.wav', mimeType: 'audio/wav'),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not play benchmark WAV: $error')),
      );
    }
  }

  Future<void> _stopAudio() async {
    if (_audioPlayer.state != PlayerState.stopped) {
      await _audioPlayer.stop();
    }
  }

  void _update(String message, double? fraction) {
    if (!mounted || _controller?.isCancelled == true) return;
    setState(() {
      _status = message;
      _progress = fraction;
    });
  }

  Future<void> _copyJson() async {
    final report = _report;
    if (report == null) return;
    await Clipboard.setData(ClipboardData(text: report.encode(pretty: true)));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Benchmark JSON copied.')),
    );
  }

  @override
  void dispose() {
    unawaited(_playerStateSubscription.cancel());
    unawaited(_audioPlayer.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return PopScope(
      canPop: !_running,
      child: Scaffold(
        appBar: AppBar(title: const Text('Performance benchmark')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Canonical workload',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'tiny.en · JFK 11-second WAV · English · Responsive, '
                'Balanced, and Efficient · 1 warm-up + 3 runs per mode',
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _running ? null : _toggleAudio,
                  icon: Icon(_isPlayingAudio ? Icons.stop : Icons.play_arrow),
                  label: Text(
                    _isPlayingAudio
                        ? 'Stop benchmark audio'
                        : 'Play benchmark WAV',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (!kReleaseMode)
                Card(
                  color: Theme.of(context).colorScheme.tertiaryContainer,
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'This is not a release build. Keep debug/profile results '
                      'separate from release baselines.',
                    ),
                  ),
                ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(_status),
                      if (_running) ...[
                        const SizedBox(height: 12),
                        LinearProgressIndicator(value: _progress),
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
                    child: SelectableText(_error!),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              if (_running)
                OutlinedButton.icon(
                  onPressed: _controller?.isCancelled == true ? null : _cancel,
                  icon: const Icon(Icons.cancel),
                  label: const Text('Cancel benchmark'),
                )
              else
                FilledButton.icon(
                  onPressed: _run,
                  icon: const Icon(Icons.speed),
                  label: Text(report == null ? 'Run benchmark' : 'Run again'),
                ),
              if (report != null) ...[
                const SizedBox(height: 24),
                Text('Comparison',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                _Comparison(report: report),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _copyJson,
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy results as JSON'),
                ),
                const SizedBox(height: 20),
                Text('Mode details',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                _ModeDetails(report: report),
                if (_savedPath != null) ...[
                  const SizedBox(height: 8),
                  SelectableText('Saved to $_savedPath'),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Comparison extends StatelessWidget {
  const _Comparison({required this.report});

  final WhisperBenchmarkReport report;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 28,
              runSpacing: 16,
              children: [
                _Metric(
                  'WAV duration',
                  _seconds(report.audio['duration_us'] as num),
                ),
                _Metric(
                  'WAV size',
                  _fileSize(report.audio['bytes'] as int),
                ),
                _Metric(
                  'Model load',
                  _seconds(report.modelLoadMicroseconds),
                ),
              ],
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Mode')),
              DataColumn(label: Text('Wall')),
              DataColumn(label: Text('Native')),
              DataColumn(label: Text('Overhead')),
              DataColumn(label: Text('RTF')),
              DataColumn(label: Text('Drift')),
              DataColumn(label: Text('WER')),
              DataColumn(label: Text('Threads')),
              DataColumn(label: Text('Best-of')),
              DataColumn(label: Text('Timestamps')),
            ],
            rows: report.modes.map((mode) {
              final transcription = (mode.configuration['transcription'] as Map)
                  .cast<String, dynamic>();
              final wall = mode.statistics['wall_us']!;
              final wer =
                  (mode.accuracy['maximum_observed_word_error_rate'] as num)
                      .toDouble();
              return DataRow(cells: [
                DataCell(Text(_modeLabel(mode.mode))),
                DataCell(Text(_seconds(wall.median))),
                DataCell(Text(_seconds(mode.statistics['native_us']!.median))),
                DataCell(
                    Text(_seconds(mode.statistics['overhead_us']!.median))),
                DataCell(Text(mode.statistics['real_time_factor']!.median
                    .toStringAsFixed(3))),
                DataCell(Text(
                    '${wall.firstToLastDriftPercent.toStringAsFixed(1)}%')),
                DataCell(Text('${(wer * 100).toStringAsFixed(1)}%')),
                DataCell(Text('${transcription['threads']}')),
                DataCell(Text('${transcription['greedy_best_of']}')),
                DataCell(Text(
                    transcription['no_timestamps'] == true ? 'Off' : 'On')),
              ]);
            }).toList(growable: false),
          ),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 130,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            Text(value, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      );
}

class _ModeDetails extends StatelessWidget {
  const _ModeDetails({required this.report});
  final WhisperBenchmarkReport report;

  @override
  Widget build(BuildContext context) => Column(
        children: report.modes
            .map((mode) => Card(
                  child: ExpansionTile(
                    key: ValueKey('benchmark-${mode.mode}'),
                    title: Text(_modeLabel(mode.mode)),
                    subtitle: Text(
                      '${mode.iterations.length} measured runs · '
                      'median ${_seconds(mode.statistics['wall_us']!.median)}',
                    ),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('Run')),
                            DataColumn(label: Text('Wall')),
                            DataColumn(label: Text('Native')),
                            DataColumn(label: Text('Overhead')),
                            DataColumn(label: Text('RTF')),
                            DataColumn(label: Text('WER')),
                          ],
                          rows: mode.iterations
                              .map((run) => DataRow(cells: [
                                    DataCell(Text('${run.index}')),
                                    DataCell(
                                        Text(_seconds(run.wallMicroseconds))),
                                    DataCell(
                                        Text(_seconds(run.nativeMicroseconds))),
                                    DataCell(Text(
                                        _seconds(run.overheadMicroseconds))),
                                    DataCell(Text(
                                        run.realTimeFactor.toStringAsFixed(3))),
                                    DataCell(Text(
                                        '${(run.wordErrorRate * 100).toStringAsFixed(1)}%')),
                                  ]))
                              .toList(growable: false),
                        ),
                      ),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Transcript'),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SelectableText(
                          mode.iterations.first.transcript,
                        ),
                      ),
                    ],
                  ),
                ))
            .toList(growable: false),
      );
}

String _seconds(num microseconds) =>
    '${(microseconds / Duration.microsecondsPerSecond).toStringAsFixed(3)}s';

String _fileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kibibytes = bytes / 1024;
  if (kibibytes < 1024) return '${kibibytes.toStringAsFixed(1)} KiB';
  return '${(kibibytes / 1024).toStringAsFixed(2)} MiB';
}

String _modeLabel(String mode) =>
    mode.isEmpty ? mode : '${mode[0].toUpperCase()}${mode.substring(1)}';
