# Mobile UI Agent Handoff

Status: Historical snapshot (2026-03-06)

Last updated: 2026-03-06
Scope: Android-first mobile completion, then iOS validation

## 1) Goal

- Keep app clock and widget clock behavior coherent with web intent.
- Complete Android hardening first, then finish iOS widget verification.
- Latest delivered feature: native widget "Today mini event list" (Android + iOS) while preserving analog clock.

## 2) Current Product State

- Android app + home widget flow is implemented and build-verified.
- iOS widget code is implemented but still requires macOS/Xcode runtime validation.
- Auth persistence issue from repeated relogin was fixed by stable credential file path resolution.
- Refresh/date navigation reliability was improved (request flow + timeout/fallback handling).
- `widget_pinned` was removed end-to-end because it had no meaningful runtime function.

## 3) What Was Completed

### Auth and provider persistence

- `src/services/providers/google_provider.py`
- `src/services/providers/apple_provider.py`
- Stable resolved paths prevent re-auth churn from changing run directories.

### Refresh/date navigation hardening

- `mobile/flutter_app/lib/integrations/backend_api/api_client.dart`
- `mobile/flutter_app/lib/features/calendar/data/calendar_events_repository.dart`
- `mobile/flutter_app/lib/features/calendar/presentation/mobile_home_screen.dart`
- Fixed endpoint misuse (`max_results=250` -> backend limit is `<=200`) and improved timeout/fallback behavior.

### Clock/touch and UI parity work

- `mobile/flutter_app/lib/features/calendar/presentation/analog_clock_card.dart`
- Better event hit behavior for overlap scenarios and app clock rendering parity.

### Android widget updates

- `mobile/flutter_app/android/app/src/main/res/layout/smart_analog_appwidget.xml`
- `mobile/flutter_app/android/app/src/main/kotlin/com/smartanalog/flutter_app/SmartAnalogAppWidgetProvider.kt`
- `mobile/flutter_app/android/app/src/main/res/xml/smart_analog_appwidget_info.xml`
- `mobile/flutter_app/android/app/src/main/AndroidManifest.xml`
- `mobile/flutter_app/android/app/src/main/kotlin/com/smartanalog/flutter_app/MainActivity.kt`
- Added mini-list block: title + up to 3 event rows with time/all-day formatting.

### iOS widget updates

- `mobile/flutter_app/ios/WidgetExtension/SmartAnalogWidget.swift`
- Added parsed event preview model and family-aware row rendering:
  - small: up to 1 event
  - medium: up to 2 events
  - large: up to 3 events

### Contract cleanup (`widget_pinned` removal)

- Backend: `web/backend/app/main.py`
- Web: `web/frontend/src/app/page.tsx`, `web/frontend/src/app/globals.css`
- Mobile DTO/UI/tests: `mobile/flutter_app/lib/integrations/backend_api/dto/settings_response_dto.dart`, `mobile/flutter_app/lib/features/settings/presentation/settings_panel.dart`, `mobile/flutter_app/test/backend_mvp_parity_dto_contract_test.dart`
- QA script: `scripts/android-final-qa.sh`

## 4) Verification Evidence (already run)

From `mobile/flutter_app`:

- `flutter analyze` -> PASS
- `flutter test` -> PASS
- `flutter build apk --debug` -> PASS

Notes:

- Kotlin/Swift LSP diagnostics are unavailable in this Linux environment (`kotlin-lsp`, `sourcekit-lsp` not present).
- iOS WidgetExtension build/runtime verification remains pending on macOS/Xcode.

## 5) Remaining Next Steps (Execute in Order)

1. Android real-device visual QA for mini-list density
   - Validate readability and clipping for common widget sizes.
   - Confirm events update after manual refresh and time progression.

2. Android widget behavior sanity on lock/home hosts
   - Confirm expected launcher behavior (whole-widget tap opens app).
   - Re-confirm that per-event taps are not implemented by design.

3. iOS WidgetExtension validation on macOS/Xcode
   - Build WidgetExtension target.
   - Add widget in simulator/device.
   - Verify family row counts, truncation, and snapshot refresh behavior.

4. If UI clipping appears, tune list formatting only (no contract changes)
   - Shorten time text and spacing.
   - Keep snapshot schema unchanged.

## 6) Explicit Constraints to Keep

- Commit rule: title in English, body in Korean.
- Delivery order: Android first, then iOS.
- Keep model/contract translation in data/integration layers.
- Keep platform widget implementation in native host targets (`android/`, `ios/`).
- Do not rename backend fields or invent parallel DTO field names.

## 7) Quick Resume Commands

```bash
cd /home/shine/projects/clock_widget/mobile/flutter_app
flutter analyze
flutter test
flutter build apk --debug
```

Android with local backend in this repo setup:

```bash
cd /home/shine/projects/clock_widget
uv run uvicorn web.backend.app.main:app --host 0.0.0.0 --port 8000
source ~/.zshrc
cw-adb reverse tcp:8000 tcp:8000
cw-flutter-run
```

Notes:

- `cw-adb` and `cw-flutter-run` follow `CW_ANDROID_ADB_SOCKET` from `~/.zshrc` (default `5037`).
- If you temporarily move to `5038` for conflict recovery, set both `ADB_SERVER_SOCKET` and `CW_ANDROID_ADB_SOCKET` to `tcp:127.0.0.1:5038` in the same shell.

## 8) Optional Follow-up (Not Implemented)

- Per-item deep links from mini-list rows to a filtered event detail screen.
- Additional typography/spacing pass for extra-small launchers.
