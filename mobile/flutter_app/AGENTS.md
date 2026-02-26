# AGENTS.md (mobile/flutter_app)

Scope: Flutter app architecture, data contracts, and native-widget integration boundaries.

## Entry Points

- Dart runtime entry: `lib/main.dart`
- App bootstrap: `lib/app/app.dart`
- Initial UI surface: `lib/features/calendar/presentation/mobile_home_screen.dart`

## Key Modules

- Domain models:
  - `lib/features/calendar/domain/models/calendar_event.dart`
  - `lib/features/calendar/domain/models/widget_snapshot.dart`
- Snapshot orchestration:
  - `lib/features/calendar/application/widget_snapshot_builder.dart`
- Clock math:
  - `lib/core/time/clock_math.dart`
- Snapshot storage boundary:
  - `lib/core/storage/widget_snapshot_store.dart`

## Integration Boundaries

- Keep model/contract translation inside data/integration layers; presentation widgets should consume already-mapped models.
- Avoid embedding platform-channel/storage details directly into feature presentation widgets.
- Native widget targets are platform-host concerns under `ios/` and `android/`; keep shared snapshot schema stable for both.

## Widget Notes

- Current tree includes standard Flutter hosts:
  - iOS host: `ios/Runner*`
  - Android host: `android/app/*`
- If WidgetKit/AppWidget targets are added, document their target dirs and snapshot bridge keys here.

## Commands

- `flutter pub get`
- `flutter analyze`
- `flutter run`
- `flutter build apk --debug`

## Verification

- Run `flutter analyze` before commit.
- Validate snapshot generation after modifying builder/model/math files.
- Ensure date/time serialization and color fields stay aligned with backend/web contracts.

## Anti-Patterns

- Do not store secrets/tokens in plain-text shared preferences without secure storage strategy.
- Do not duplicate backend contract fields under ad-hoc names; keep DTO field names consistent.
- Do not mix UI-only concerns with snapshot serialization logic in the same class.
