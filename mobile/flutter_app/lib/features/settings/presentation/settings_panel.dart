import 'package:flutter/material.dart';
import '../../calendar/data/calendar_events_repository.dart';

class SettingsPanel extends StatefulWidget {
  const SettingsPanel({super.key, required this.repository});
  
  final CalendarEventsRepository repository;

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel> {
  bool _loading = true;
  bool _saving = false;
  
  String _theme = 'system';
  double _eventOpacity = 100;
  double _clockOpacity = 100;
  bool _briefingEnabled = true;
  bool _briefingTtsEnabled = false;
  bool _widgetPinned = false;
  
  @override
  void initState() {
    super.initState();
    _loadSettings();
  }
  
  Future<void> _loadSettings() async {
    try {
      final settings = await widget.repository.fetchSettings();
      if (mounted) {
        setState(() {
          _theme = settings.theme;
          _eventOpacity = settings.eventOpacity.toDouble().clamp(0.0, 100.0);
          _clockOpacity = settings.clockOpacity.toDouble().clamp(0.0, 100.0);
          _briefingEnabled = settings.briefingEnabled;
          _briefingTtsEnabled = settings.briefingTtsEnabled;
          _widgetPinned = settings.widgetPinned;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load settings: $e')));
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _saving = true);
    try {
      await widget.repository.updateSettings(
        theme: _theme,
        eventOpacity: _eventOpacity.toInt(),
        clockOpacity: _clockOpacity.toInt(),
        briefingEnabled: _briefingEnabled,
        briefingTtsEnabled: _briefingTtsEnabled,
        widgetPinned: _widgetPinned,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save settings: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Card(
        margin: EdgeInsets.symmetric(vertical: 8),
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Settings', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            InputDecorator(
              decoration: const InputDecoration(labelText: 'Theme'),
              child: DropdownButton<String>(
                value: _theme,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 'system', child: Text('System')),
                  DropdownMenuItem(value: 'light', child: Text('Light')),
                  DropdownMenuItem(value: 'dark', child: Text('Dark')),
                ],
                onChanged: (v) => setState(() => _theme = v ?? 'system'),
              ),
            ),
            const SizedBox(height: 16),
            Text('Event Opacity: ${_eventOpacity.toInt()}%'),
            Slider(
              value: _eventOpacity,
              min: 0,
              max: 100,
              divisions: 100,
              onChanged: (v) => setState(() => _eventOpacity = v),
            ),
            Text('Clock Opacity: ${_clockOpacity.toInt()}%'),
            Slider(
              value: _clockOpacity,
              min: 0,
              max: 100,
              divisions: 100,
              onChanged: (v) => setState(() => _clockOpacity = v),
            ),
            SwitchListTile(
              title: const Text('Briefing Enabled'),
              value: _briefingEnabled,
              onChanged: (v) => setState(() => _briefingEnabled = v),
            ),
            SwitchListTile(
              title: const Text('Briefing TTS Enabled'),
              value: _briefingTtsEnabled,
              onChanged: (v) => setState(() => _briefingTtsEnabled = v),
            ),
            SwitchListTile(
              title: const Text('Widget Pinned'),
              value: _widgetPinned,
              onChanged: (v) => setState(() => _widgetPinned = v),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _saving ? null : _saveSettings,
              icon: const Icon(Icons.save),
              label: Text(_saving ? 'Saving...' : 'Save Settings'),
            ),
          ],
        ),
      ),
    );
  }
}
