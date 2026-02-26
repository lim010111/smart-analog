# AGENTS.md (mobile)

Scope: Mobile platform workspace and boundaries for Flutter app + native iOS/Android surfaces.

## Structure

- `mobile/flutter_app/`: Flutter project root (single mobile app workspace).
- `mobile/flutter_app/lib/`: Dart app code (app/core/features/integrations).
- `mobile/flutter_app/ios/`: iOS app host project and extension targets.
- `mobile/flutter_app/android/`: Android host project and widget/provider targets.

## Workspace Rules

- Keep mobile-specific implementation in `mobile/flutter_app/`; do not couple mobile flow logic into `src/` UI modules.
- Treat widget rendering as native-surface responsibility (iOS WidgetKit / Android AppWidget), while Flutter orchestrates data and user flows.
- Keep generated artifacts out of commits (`build/`, `.dart_tool/`, Gradle caches, Xcode derived data).

## Contract Boundaries

- Mobile event/snapshot DTOs are a contract surface alongside backend Pydantic and frontend TypeScript interfaces.
- When backend payloads change, update:
  - `web/backend/app/main.py` models/endpoints
  - `web/frontend` interfaces
  - `mobile/flutter_app/lib/features/calendar/domain/models/*`

## Commands

- Install deps: `cd mobile/flutter_app && flutter pub get`
- Analyze: `cd mobile/flutter_app && flutter analyze`
- Run app: `cd mobile/flutter_app && flutter run`
- Android debug build: `cd mobile/flutter_app && flutter build apk --debug`

## Verification Expectations

- Always run `flutter analyze` for mobile code changes.
- Validate clock snapshot/model behavior after changing:
  - `lib/features/calendar/application/widget_snapshot_builder.dart`
  - `lib/features/calendar/domain/models/widget_snapshot.dart`
  - `lib/core/time/clock_math.dart`
- For cross-layer API changes, perform payload-shape checks against backend/frontend/mobile in the same change.
