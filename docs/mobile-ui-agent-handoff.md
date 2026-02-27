# Mobile UI Agent Handoff

Last updated: 2026-02-27
Branch: `feature/mobile-flutter-foundation`
Goal: Full MVP parity from web service to mobile app, then release Android first and iOS second.

## 1) What is already done (do not redo)

### Auth / callback stability
- Mobile Google deep-link callback flow is wired (`smartanalog://auth/google`).
- Backend supports mobile callback state/redirect.
- OAuth pending state is persisted (SQLite store), not in-memory only.

### Contract hardening
- Backend response models for currently used mobile endpoints are explicit.
- Mobile DTO parsing is strict (FormatException on contract drift).
- Regression tests exist for DTO contract and JSON helper.

### Widget data path
- App writes:
  - `widget_snapshot.json`
  - `widget_snapshot_read_v1.json` (read-only widget artifact)
- Atomic file-write behavior is implemented.
- Widget snapshot store tests are in place.

## 2) Pre-UI groundwork completed in this phase

This phase intentionally added non-UI endpoint coverage scaffolding so UI work can focus on screens/interactions.

### Added DTO surfaces (mobile)
- `mobile/flutter_app/lib/integrations/backend_api/dto/settings_response_dto.dart`
- `mobile/flutter_app/lib/integrations/backend_api/dto/provider_auth_response_dto.dart`
- `mobile/flutter_app/lib/integrations/backend_api/dto/create_event_response_dto.dart`
- `mobile/flutter_app/lib/integrations/backend_api/dto/natural_input_response_dto.dart`
- `mobile/flutter_app/lib/integrations/backend_api/dto/briefing_response_dto.dart`
- `mobile/flutter_app/lib/integrations/backend_api/dto/color_rule_dto.dart`
- `mobile/flutter_app/lib/integrations/backend_api/dto/colors_response_dto.dart`

### API client methods added
In `mobile/flutter_app/lib/integrations/backend_api/api_client.dart`:
- Provider: authenticate, logout
- Settings: fetch, update
- Events: create
- Natural input: parse, create-from-natural-input
- Briefing: fetch today, TTS base64, TTS binary
- Colors: palette, schema get/update, apply-all, apply-status

### Repository wrappers added
In `mobile/flutter_app/lib/features/calendar/data/calendar_events_repository.dart`:
- Wrapper methods for all the above client capabilities.

### New tests
- `mobile/flutter_app/test/backend_mvp_parity_dto_contract_test.dart`
  - Covers key payload parse success/failure for new parity DTOs.

## 3) UI agent mission (start here)

Implement UI on top of existing repository/api methods without changing endpoint contracts.

### Target MVP features to implement in UI
1. Settings editor (theme, opacities, briefing toggles, widget pin)
2. Color schema management (palette read, rules read/update, apply-all, status)
3. Event creation form (summary/start/end/all-day)
4. Natural input flow (parse preview + create)
5. Briefing surface (today briefing display + TTS actions)
6. Provider session controls (authenticate/logout)

### Existing web behavior reference
- `web/frontend/src/app/page.tsx`
- `web/frontend/src/app/settings/color-schema/page.tsx`

The mobile UI should mirror feature intent, not pixel-copy web layout.

## 4) Constraints and rules for UI work

- Keep translation/mapping in data/integration layers (already set).
- Do not move contract logic into presentation widgets.
- Keep widget boundary strict: app authenticates; widget reads snapshot artifact only.
- Release order is fixed:
  1. Android stabilization and validation
  2. iOS follow-up stabilization and validation

## 5) Suggested implementation order for UI agent

1. Settings + provider controls (lowest risk)
2. Event create + natural input
3. Briefing + TTS controls
4. Color schema editor + apply status polling
5. End-to-end snapshot refresh hooks after these actions

## 6) Verification checklist after UI implementation

- `flutter analyze`
- `flutter test`
- `flutter build apk --debug`
- Android real-device flow:
  - auth -> settings save -> create event -> natural input -> briefing -> color apply
  - widget artifact refresh remains valid

After Android passes, repeat equivalent validation on iOS.
