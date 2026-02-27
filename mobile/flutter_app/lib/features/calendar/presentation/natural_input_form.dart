import 'package:flutter/material.dart';

import '../../../integrations/backend_api/dto/natural_input_response_dto.dart';
import '../data/calendar_events_repository.dart';

class NaturalInputForm extends StatefulWidget {
  const NaturalInputForm({
    super.key,
    required this.repository,
    required this.provider,
    required this.onCreated,
  });

  final CalendarEventsRepository repository;
  final String provider;
  final VoidCallback onCreated;

  @override
  State<NaturalInputForm> createState() => _NaturalInputFormState();
}

class _NaturalInputFormState extends State<NaturalInputForm> {
  final TextEditingController _textController = TextEditingController();
  bool _parsing = false;
  bool _creating = false;
  NaturalParseResponseDto? _lastParse;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _parse() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter natural input text.')),
      );
      return;
    }
    if (text.length > 500) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Natural input must be 500 chars or less.'),
        ),
      );
      return;
    }

    setState(() => _parsing = true);
    try {
      final parsed = await widget.repository.parseNaturalInput(
        provider: widget.provider,
        text: text,
      );
      if (!mounted) {
        return;
      }
      setState(() => _lastParse = parsed);
      if (!parsed.ready) {
        final reason =
            parsed.reason ?? 'Natural parsing could not resolve input.';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(reason)));
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Parse failed: $error')));
    } finally {
      if (mounted) {
        setState(() => _parsing = false);
      }
    }
  }

  Future<void> _createFromNatural() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      return;
    }

    final parse = _lastParse;
    if (parse == null || !parse.ready) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Parse first and ensure result is ready.'),
        ),
      );
      return;
    }

    setState(() => _creating = true);
    try {
      await widget.repository.createEventFromNaturalInput(
        provider: widget.provider,
        text: text,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Event created from natural input.')),
      );
      widget.onCreated();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Create failed: $error')));
    } finally {
      if (mounted) {
        setState(() => _creating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final parse = _lastParse;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Natural Input',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _textController,
              maxLength: 500,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Describe event naturally',
                hintText: 'Tomorrow 2pm design sync for 1 hour',
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _parsing ? null : _parse,
                    icon: const Icon(Icons.psychology_outlined),
                    label: Text(_parsing ? 'Parsing...' : 'Parse'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _creating ? null : _createFromNatural,
                    icon: const Icon(Icons.event_available),
                    label: Text(_creating ? 'Creating...' : 'Create'),
                  ),
                ),
              ],
            ),
            if (parse != null) ...[
              const SizedBox(height: 10),
              Text('Ready: ${parse.ready}'),
              if (parse.reason != null && parse.reason!.isNotEmpty)
                Text('Reason: ${parse.reason}'),
              if (parse.result != null) ...[
                Text('Intent: ${parse.result!.intent}'),
                Text('Title: ${parse.result!.title ?? '-'}'),
                Text('Start: ${parse.result!.startTime ?? '-'}'),
                Text('End: ${parse.result!.endTime ?? '-'}'),
                Text('All day: ${parse.result!.allDay}'),
                Text(
                  'Confidence: ${parse.result!.confidence.toStringAsFixed(2)}',
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
