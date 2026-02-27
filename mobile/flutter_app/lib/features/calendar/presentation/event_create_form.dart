import 'package:flutter/material.dart';

import '../data/calendar_events_repository.dart';

class EventCreateForm extends StatefulWidget {
  const EventCreateForm({
    super.key,
    required this.repository,
    required this.provider,
    required this.onCreated,
  });

  final CalendarEventsRepository repository;
  final String provider;
  final VoidCallback onCreated;

  @override
  State<EventCreateForm> createState() => _EventCreateFormState();
}

class _EventCreateFormState extends State<EventCreateForm> {
  final TextEditingController _summaryController = TextEditingController();
  final TextEditingController _startController = TextEditingController();
  final TextEditingController _endController = TextEditingController();
  bool _allDay = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final start = now.add(const Duration(minutes: 30));
    final end = start.add(const Duration(hours: 1));
    _startController.text = start.toIso8601String();
    _endController.text = end.toIso8601String();
  }

  @override
  void dispose() {
    _summaryController.dispose();
    _startController.dispose();
    _endController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final summary = _summaryController.text.trim();
    final startTime = _startController.text.trim();
    final endTime = _endController.text.trim();
    if (summary.isEmpty || startTime.isEmpty || endTime.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Summary, start, and end are required.')),
      );
      return;
    }

    final parsedStart = DateTime.tryParse(startTime);
    final parsedEnd = DateTime.tryParse(endTime);
    if (parsedStart == null ||
        parsedEnd == null ||
        parsedEnd.isBefore(parsedStart)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Start/end must be valid ISO datetime and end >= start.',
          ),
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      await widget.repository.createEvent(
        provider: widget.provider,
        summary: summary,
        startTime: startTime,
        endTime: endTime,
        allDay: _allDay,
      );

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Event created.')));
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
        setState(() => _submitting = false);
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
            Text('Create Event', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            TextField(
              controller: _summaryController,
              decoration: const InputDecoration(
                labelText: 'Summary',
                hintText: 'Team sync',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _startController,
              decoration: const InputDecoration(
                labelText: 'Start time (ISO8601)',
                hintText: '2026-02-27T10:00:00+09:00',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _endController,
              decoration: const InputDecoration(
                labelText: 'End time (ISO8601)',
                hintText: '2026-02-27T11:00:00+09:00',
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('All day'),
              value: _allDay,
              onChanged: (value) => setState(() => _allDay = value),
            ),
            FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: const Icon(Icons.add_circle_outline),
              label: Text(_submitting ? 'Creating...' : 'Create Event'),
            ),
          ],
        ),
      ),
    );
  }
}
