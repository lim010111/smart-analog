import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/localization/app_i18n.dart';
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
      final i18n = context.i18n;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(i18n.colorSchemaLoadFailed(error))),
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
      final i18n = context.i18n;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(i18n.applyStatusFailed(error))));
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
        ColorRuleDto(colorHex: '#3A86FF', label: context.i18n.newRuleLabel),
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
    final i18n = context.i18n;
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
      ).showSnackBar(SnackBar(content: Text(i18n.colorSchemaSaved)));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(i18n.saveFailed(error))));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _applyAll() async {
    final i18n = context.i18n;
    setState(() => _applying = true);
    try {
      await widget.repository.applyColorsToAll(provider: widget.provider);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(i18n.applyStarted)));
      _startPolling();
      await _loadStatus();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(i18n.applyFailed(error))));
    } finally {
      if (mounted) {
        setState(() => _applying = false);
      }
    }
  }

  Color _previewColor(String hexColor) {
    final normalized = hexColor.trim();
    if (normalized.isEmpty) {
      return const Color(0xFF64748B);
    }

    final hex = normalized.startsWith('#')
        ? normalized.substring(1)
        : normalized;
    if (hex.length != 6) {
      return const Color(0xFF64748B);
    }

    final parsed = int.tryParse(hex, radix: 16);
    if (parsed == null) {
      return const Color(0xFF64748B);
    }

    return Color(0xFF000000 | parsed);
  }

  Future<void> _pickColorForRule(int index) async {
    if (_palette.isEmpty || index < 0 || index >= _rules.length) {
      return;
    }

    final currentHex = _rules[index].colorHex;
    final selectedColorHex = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final i18n = context.i18n;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  i18n.selectColorTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _palette.map((hex) {
                    final preview = _previewColor(hex);
                    final selected = hex == currentHex;
                    return InkWell(
                      onTap: () => Navigator.of(context).pop(hex),
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: preview,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: selected
                                ? Theme.of(context).colorScheme.onSurface
                                : Theme.of(context).colorScheme.outlineVariant,
                            width: selected ? 2.5 : 1,
                          ),
                        ),
                        child: selected
                            ? Icon(
                                Icons.check,
                                size: 18,
                                color: Theme.of(context).colorScheme.onSurface,
                              )
                            : null,
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || selectedColorHex == null || selectedColorHex.isEmpty) {
      return;
    }
    _updateRule(index, colorHex: selectedColorHex);
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final status = _lastStatus;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              i18n.colorSchemaTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(i18n.providerValue(widget.provider)),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              const SizedBox(height: 8),
              ...List<Widget>.generate(_rules.length, (index) {
                final rule = _rules[index];
                final preview = _previewColor(rule.colorHex);
                return Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: rule.label,
                        decoration: InputDecoration(
                          labelText: i18n.labelFieldLabel,
                        ),
                        onChanged: (value) => _updateRule(index, label: value),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: i18n.selectColorTooltip,
                      onPressed: _palette.isEmpty
                          ? null
                          : () => _pickColorForRule(index),
                      icon: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: preview,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: i18n.removeRuleTooltip,
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
                    label: Text(i18n.addRuleLabel),
                  ),
                  FilledButton.icon(
                    onPressed: _saving ? null : _saveRules,
                    icon: const Icon(Icons.save),
                    label: Text(
                      _saving ? i18n.savingLabel : i18n.saveRulesLabel,
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _applying ? null : _applyAll,
                    icon: const Icon(Icons.play_arrow),
                    label: Text(
                      _applying ? i18n.applyingLabel : i18n.applyToAllLabel,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (status != null) ...[
                Text(
                  i18n.statusLine(
                    running: status.running,
                    queued: status.queued,
                    processed: status.lastProcessed,
                    updated: status.lastUpdated,
                  ),
                ),
                if (status.lastError.isNotEmpty)
                  Text(i18n.lastErrorLine(status.lastError)),
              ] else if (_applying)
                Text(i18n.statusApplying),
            ],
          ],
        ),
      ),
    );
  }
}
