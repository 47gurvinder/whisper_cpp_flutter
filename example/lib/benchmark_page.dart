import 'dart:async';
import 'dart:io';

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
  bool _running = false;
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
  }

  Future<void> _run() async {
    if (_running) return;
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
      final directory = Directory(
        '${(await WhisperModelManager().directory).path}/benchmarks',
      );
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
                'tiny.en · JFK 11-second WAV · English · 4 threads · '
                'greedy best-of 5 · token timestamps · 1 warm-up + 5 runs',
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
                Text('Summary', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                _Summary(report: report),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _copyJson,
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy results as JSON'),
                ),
                const SizedBox(height: 20),
                Text('Measured runs',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                _Iterations(report: report),
                const SizedBox(height: 20),
                Text('Transcript',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                SelectableText(report.iterations.first.transcript),
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

class _Summary extends StatelessWidget {
  const _Summary({required this.report});

  final WhisperBenchmarkReport report;

  @override
  Widget build(BuildContext context) {
    final wall = report.statistics['wall_us']!;
    final native = report.statistics['native_us']!;
    final overhead = report.statistics['overhead_us']!;
    final rtf = report.statistics['real_time_factor']!;
    final wer =
        (report.accuracy['maximum_observed_word_error_rate'] as num).toDouble();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 28,
          runSpacing: 16,
          children: [
            _Metric('Model load', _seconds(report.modelLoadMicroseconds)),
            _Metric('Median wall', _seconds(wall.median)),
            _Metric('Median native', _seconds(native.median)),
            _Metric('Median overhead', _seconds(overhead.median)),
            _Metric('Median RTF', rtf.median.toStringAsFixed(3)),
            _Metric('Run drift',
                '${wall.firstToLastDriftPercent.toStringAsFixed(1)}%'),
            _Metric('Word error', '${(wer * 100).toStringAsFixed(1)}%'),
          ],
        ),
      ),
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

class _Iterations extends StatelessWidget {
  const _Iterations({required this.report});
  final WhisperBenchmarkReport report;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
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
          rows: report.iterations
              .map(
                (run) => DataRow(cells: [
                  DataCell(Text('${run.index}')),
                  DataCell(Text(_seconds(run.wallMicroseconds))),
                  DataCell(Text(_seconds(run.nativeMicroseconds))),
                  DataCell(Text(_seconds(run.overheadMicroseconds))),
                  DataCell(Text(run.realTimeFactor.toStringAsFixed(3))),
                  DataCell(
                      Text('${(run.wordErrorRate * 100).toStringAsFixed(1)}%')),
                ]),
              )
              .toList(growable: false),
        ),
      );
}

String _seconds(num microseconds) =>
    '${(microseconds / Duration.microsecondsPerSecond).toStringAsFixed(3)}s';
