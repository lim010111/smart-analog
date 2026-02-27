import 'dart:async';

import 'package:flutter/material.dart';

import '../../../integrations/backend_api/dto/color_rule_dto.dart';
import '../../../integrations/backend_api/dto/colors_response_dto.dart';
import '../../calendar/data/calendar_events_repository.dart';

class ColorSchemaEditor extends StatefulWidget {
  const ColorSchemaEditor({
    super.key,
    required this.repository,
    required this.provider,
  });

  final CalendarEventsRepository repository;
  final String provider;

  @override
  State<ColorSchemaEditor> createState() => _ColorSchemaEditorState();
}

class _ColorSchemaEditorState extends State<ColorSchemaEditor> {
  bool _loading = false;
  bool _saving = false;
  bool _applying = false;
  List<String> _palette = const <String>[];
  List<ColorRuleDto> _rules = const <ColorRuleDto>[];
  ApplyColorsStatusResponseDto? _lastStatus;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void didUpdateWidget(covariant ColorSchemaEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.provider != widget.provider) {
      _stopPolling();
      _loadAll();
    }
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final palette = await widget.repository.fetchColorPalette(
        provider: widget.provider,
      );
      final schema = await widget.repository.fetchColorSchema(
        provider: widget.provider,
      );

      if (!mounted) {
        return;
      }
      setState(() {
        _palette = palette.palette;
        _rules = schema.rules;
      });
      await _loadStatus();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Color schema load failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadStatus() async {
    try {
      final status = await widget.repository.fetchApplyColorsStatus(
        provider: widget.provider,
      );
      if (!mounted) {
        return;
      }
      setState(() => _lastStatus = status);
      if (status.running || status.queued) {
        _startPolling();
      } else {
        _stopPolling();
      }
    } on FormatException {
      if (!mounted) {
        return;
      }
      setState(() {
        _applying = true;
      });
      _startPolling();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Apply status failed: $error')));
    }
  }

  void _startPolling() {
    _pollTimer ??= Timer.periodic(const Duration(seconds: 3), (_) {
      _loadStatus();
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void _addRule() {
    setState(() {
      _rules = <ColorRuleDto>[
        ..._rules,
        const ColorRuleDto(colorHex: '#3A86FF', label: 'New Rule'),
      ];
    });
  }

  void _removeRule(int index) {
    setState(() {
      final list = _rules.toList();
      list.removeAt(index);
      _rules = list;
    });
  }

  void _updateRule(int index, {String? label, String? colorHex}) {
    setState(() {
      final list = _rules.toList();
      final current = list[index];
      list[index] = ColorRuleDto(
        colorHex: colorHex ?? current.colorHex,
        label: label ?? current.label,
      );
      _rules = list;
    });
  }

  Future<void> _saveRules() async {
    setState(() => _saving = true);
    try {
      await widget.repository.updateColorSchema(
        provider: widget.provider,
        rules: _rules,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Color schema saved.')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Save failed: $error')));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _applyAll() async {
    setState(() => _applying = true);
    try {
      await widget.repository.applyColorsToAll(provider: widget.provider);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Apply started.')));
      _startPolling();
      await _loadStatus();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Apply failed: $error')));
    } finally {
      if (mounted) {
        setState(() => _applying = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _lastStatus;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Color Schema', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('Provider: ${widget.provider}'),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              Text('Palette: ${_palette.join(', ')}'),
              const SizedBox(height: 8),
              ...List<Widget>.generate(_rules.length, (index) {
                final rule = _rules[index];
                return Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        initialValue: rule.label,
                        decoration: const InputDecoration(labelText: 'Label'),
                        onChanged: (value) => _updateRule(index, label: value),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        initialValue: rule.colorHex,
                        decoration: const InputDecoration(labelText: 'Color'),
                        onChanged: (value) =>
                            _updateRule(index, colorHex: value),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove rule',
                      onPressed: () => _removeRule(index),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                );
              }),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _addRule,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Rule'),
                  ),
                  FilledButton.icon(
                    onPressed: _saving ? null : _saveRules,
                    icon: const Icon(Icons.save),
                    label: Text(_saving ? 'Saving...' : 'Save Rules'),
                  ),
                  FilledButton.icon(
                    onPressed: _applying ? null : _applyAll,
                    icon: const Icon(Icons.play_arrow),
                    label: Text(_applying ? 'Applying...' : 'Apply to All'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (status != null) ...[
                Text(
                  'Status: running=${status.running}, queued=${status.queued}, '
                  'processed=${status.lastProcessed}, updated=${status.lastUpdated}',
                ),
                if (status.lastError.isNotEmpty)
                  Text('Last error: ${status.lastError}'),
              ] else if (_applying)
                const Text('Status: Applying...'),
            ],
          ],
        ),
      ),
    );
  }
}
