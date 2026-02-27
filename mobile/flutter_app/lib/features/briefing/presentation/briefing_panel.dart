import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

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
      ).showSnackBar(SnackBar(content: Text('Briefing load failed: $error')));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _generateTtsAndSave() async {
    if (_briefing.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Load briefing first.')));
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Generation Complete. Audio saved in app storage.'),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('TTS generation failed: $error')));
    } finally {
      if (mounted) {
        setState(() => _ttsLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Today Briefing',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text('Provider: ${widget.provider}'),
            Text('Generated: $_generatedAt'),
            Text('Event count: $_eventCount'),
            const SizedBox(height: 8),
            if (_briefing.isEmpty)
              const Text('No briefing loaded yet.')
            else
              Text(_briefing),
            if (_savedAudioPath.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Saved file: $_savedAudioPath'),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _loading ? null : _loadBriefing,
                    icon: const Icon(Icons.article_outlined),
                    label: Text(_loading ? 'Loading...' : 'Load Briefing'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _ttsLoading ? null : _generateTtsAndSave,
                    icon: const Icon(Icons.record_voice_over),
                    label: Text(_ttsLoading ? 'Generating...' : 'Generate TTS'),
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
