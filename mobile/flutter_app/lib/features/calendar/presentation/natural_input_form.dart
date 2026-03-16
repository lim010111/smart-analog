import 'package:flutter/material.dart';

import '../../../core/localization/app_i18n.dart';
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
  final ValueChanged<DateTime> onCreated;

  @override
  State<NaturalInputForm> createState() => _NaturalInputFormState();
}

class _NaturalInputFormState extends State<NaturalInputForm> {
  final TextEditingController _textController = TextEditingController();
  bool _creating = false;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _createFromNatural() async {
    final i18n = context.i18n;
    final text = _textController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(i18n.enterNaturalInputText)));
      return;
    }
    if (text.length > 500) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(i18n.naturalInputTooLong)));
      return;
    }

    setState(() => _creating = true);
    try {
      final response = await widget.repository.createEventFromNaturalInput(
        provider: widget.provider,
        text: text,
      );
      if (!mounted) {
        return;
      }
      if (response.created == null) {
        final note = response.parsed.note?.trim();
        final message = (note != null && note.isNotEmpty)
            ? i18n.naturalCreateNotCompleted(note)
            : i18n.naturalCreateNoEvent(response.parsed.intent);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(i18n.eventCreatedFromNatural)));
      widget.onCreated(response.created!.startTime.toLocal());
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(i18n.createFailed(error))));
    } finally {
      if (mounted) {
        setState(() => _creating = false);
      }
    }
  }

  void _applyExample(String value) {
    _textController
      ..text = value
      ..selection = TextSelection.fromPosition(
        TextPosition(offset: value.length),
      );
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
              i18n.naturalInputTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _textController,
              maxLength: 500,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: i18n.naturalInputLabel,
                hintText: i18n.naturalInputHint,
              ),
            ),
            Text(
              i18n.aiExampleLabel,
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.auto_awesome, size: 16),
                  label: Text(i18n.aiExampleOne),
                  onPressed: () => _applyExample(i18n.aiExampleOne),
                ),
                ActionChip(
                  avatar: const Icon(Icons.auto_awesome, size: 16),
                  label: Text(i18n.aiExampleTwo),
                  onPressed: () => _applyExample(i18n.aiExampleTwo),
                ),
                ActionChip(
                  avatar: const Icon(Icons.auto_awesome, size: 16),
                  label: Text(i18n.aiExampleThree),
                  onPressed: () => _applyExample(i18n.aiExampleThree),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _creating ? null : _createFromNatural,
              icon: const Icon(Icons.event_available),
              label: Text(_creating ? i18n.creatingLabel : i18n.createLabel),
            ),
            const SizedBox(height: 6),
            Text(
              i18n.naturalCreateFlowHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
