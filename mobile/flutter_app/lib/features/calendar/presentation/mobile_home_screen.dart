import 'package:flutter/material.dart';

import '../application/widget_snapshot_builder.dart';
import '../domain/models/calendar_event.dart';

class MobileHomeScreen extends StatelessWidget {
  const MobileHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    final sampleEvents = <CalendarEvent>[
      CalendarEvent(
        id: 'sample-1',
        title: 'Daily Standup',
        description: 'Mobile foundation kickoff',
        startTime: now.add(const Duration(minutes: 15)),
        endTime: now.add(const Duration(minutes: 45)),
        allDay: false,
        colorHex: '#3A86FF',
        provider: 'local',
      ),
    ];

    final snapshot = const WidgetSnapshotBuilder().build(
      now: now,
      timezone: now.timeZoneName.isEmpty ? 'UTC' : now.timeZoneName,
      events: sampleEvents,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Smart Analog Mobile')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Phase 1 foundation initialized',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          Text('Date: ${snapshot.date}'),
          Text('Timezone: ${snapshot.timezone}'),
          Text('Events loaded: ${snapshot.events.length}'),
          Text('Clock segments: ${snapshot.segments.length}'),
          const SizedBox(height: 20),
          const Text(
            'Next: integrate native calendar adapters and '
            'bridge snapshot storage into iOS/Android home widgets.',
          ),
        ],
      ),
    );
  }
}
