import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/localization/app_i18n.dart';
import '../../calendar/data/calendar_events_repository.dart';

class BriefingPanel extends StatefulWidget {
  const BriefingPanel({
    super.key,
    required this.repository,
    required this.provider,
  });

  final CalendarEventsRepository repository;
  final String provider;

  @override
  State<BriefingPanel> createState() => _BriefingPanelState();
}

class _BriefingPanelState extends State<BriefingPanel> {
  bool _loading = false;
  bool _ttsLoading = false;
  String _briefing = '';
  String _generatedAt = '-';
  int _eventCount = 0;
  String _savedAudioPath = '';

  Future<void> _loadBriefing() async {
    final i18n = context.i18n;
    setState(() => _loading = true);
    try {
      final response = await widget.repository.fetchTodayBriefing(
        provider: widget.provider,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _briefing = response.briefing;
        _generatedAt = response.generatedAt.toIso8601String();
        _eventCount = response.eventCount;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(i18n.briefingLoadFailed(error))));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _generateTtsAndSave() async {
    final i18n = context.i18n;
    if (_briefing.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(i18n.loadBriefingFirst)));
      return;
    }

    setState(() => _ttsLoading = true);
    try {
      final tts = await widget.repository.generateBriefingTtsBinary(
        text: _briefing,
        responseFormat: 'wav',
      );
      final dir = await getApplicationDocumentsDirectory();
      final fileName =
          'briefing_${DateTime.now().millisecondsSinceEpoch.toString()}.wav';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(tts.bytes, flush: true);

      if (!mounted) {
        return;
      }
      setState(() => _savedAudioPath = file.path);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(i18n.ttsGenerationComplete)));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(i18n.ttsGenerationFailed(error))));
    } finally {
      if (mounted) {
        setState(() => _ttsLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              i18n.todayBriefingTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(i18n.providerValue(widget.provider)),
            Text(i18n.generatedValue(_generatedAt)),
            Text(i18n.eventCountValue(_eventCount)),
            const SizedBox(height: 8),
            if (_briefing.isEmpty)
              Text(i18n.noBriefingYet)
            else
              Text(_briefing),
            if (_savedAudioPath.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(i18n.savedFileValue(_savedAudioPath)),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _loading ? null : _loadBriefing,
                    icon: const Icon(Icons.article_outlined),
                    label: Text(
                      _loading
                          ? i18n.loadingBriefingLabel
                          : i18n.loadBriefingLabel,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _ttsLoading ? null : _generateTtsAndSave,
                    icon: const Icon(Icons.record_voice_over),
                    label: Text(
                      _ttsLoading
                          ? i18n.generatingTtsLabel
                          : i18n.generateTtsLabel,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
