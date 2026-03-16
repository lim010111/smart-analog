import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_language.dart';

class AppLanguageController extends ChangeNotifier {
  AppLanguageController._(this._prefs, this._language);

  static const String _prefsKey = 'clock_widget_app_language';

  final SharedPreferences _prefs;
  AppLanguage _language;

  static Future<AppLanguageController> load() async {
    final prefs = await SharedPreferences.getInstance();
    final rawCode = prefs.getString(_prefsKey);
    return AppLanguageController._(prefs, AppLanguageX.fromCode(rawCode));
  }

  AppLanguage get language => _language;

  Future<void> setLanguage(AppLanguage language) async {
    if (_language == language) {
      return;
    }
    _language = language;
    notifyListeners();
    await _prefs.setString(_prefsKey, language.code);
  }
}

class AppLanguageScope extends InheritedNotifier<AppLanguageController> {
  const AppLanguageScope({
    super.key,
    required AppLanguageController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppLanguageController of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<AppLanguageScope>();
    if (scope == null || scope.notifier == null) {
      throw StateError('AppLanguageScope is missing in widget tree.');
    }
    return scope.notifier!;
  }
}

class AppI18n {
  const AppI18n(this.language);

  final AppLanguage language;

  bool get _isKorean => language == AppLanguage.korean;

  String _t(String korean, String english) => _isKorean ? korean : english;

  String get appTitle => _t('스마트 아날로그 모바일', 'Smart Analog Mobile');

  String get languageLabel => _t('언어', 'Language');
  String get englishLabel => _t('영어', 'English');
  String get koreanLabel => _t('한국어', 'Korean');

  String get settingsTitle => _t('설정', 'Settings');
  String get themeLabel => _t('앱 테마', 'Theme');
  String get systemLabel => _t('시스템', 'System');
  String get lightLabel => _t('라이트', 'Light');
  String get darkLabel => _t('다크', 'Dark');
  String get widgetThemeLabel => _t('위젯 테마', 'Widget Theme');
  String get whiteLabel => _t('화이트', 'White');
  String eventOpacityLabel(int percent) =>
      _t('일정 투명도: $percent%', 'Event Opacity: $percent%');
  String clockOpacityLabel(int percent) =>
      _t('시계 투명도: $percent%', 'Clock Opacity: $percent%');
  String get briefingEnabledLabel => _t('브리핑 사용', 'Briefing Enabled');
  String get briefingTtsEnabledLabel =>
      _t('브리핑 TTS 사용', 'Briefing TTS Enabled');
  String get labsTitle => _t('실험실', 'Labs');
  String get labsDescription => _t(
    '실험실은 실험 기능을 사용하려는 사용자를 위한 선택 영역입니다. 기본값은 꺼짐이며, 안정성은 보장되지 않을 수 있습니다.',
    'Labs is an opt-in area for users who want experimental features. Defaults stay off, and stability is not guaranteed.',
  );
  String get labsEventDetailBottomSheetLabel =>
      _t('시계 일정 상세 하단 팝업 (실험실)', 'Clock event detail bottom popup (Labs)');
  String get labsEventDetailBottomSheetHint => _t(
    '시계 일정(종일 포함)을 탭하면 하단 상세 팝업을 엽니다. 기본값: 꺼짐',
    'Open a bottom detail popup when tapping clock events (including all-day). Default: off',
  );
  String get saveSettingsLabel => _t('설정 저장', 'Save Settings');
  String get savingLabel => _t('저장 중...', 'Saving...');
  String get settingsSaved => _t('설정을 저장했습니다.', 'Settings saved');
  String failedToLoadSettings(Object error) =>
      _t('설정을 불러오지 못했습니다: $error', 'Failed to load settings: $error');
  String failedToSaveSettings(Object error) =>
      _t('설정 저장에 실패했습니다: $error', 'Failed to save settings: $error');

  String get providerAuthPageTitle => _t('로그인 및 연동', 'Login & Linking');
  String get eventToolsPageTitle => _t('AI 일정 생성', 'AI Event Creation');
  String get briefingPageTitle => _t('브리핑', 'Briefing');

  String get providerAuthControlsTitle =>
      _t('로그인 및 연동 제어', 'Login & Linking Controls');
  String get providerLabel => _t('제공자', 'Provider');
  String get authUnknown => _t('확인 중', 'unknown');
  String get authAuthenticated => _t('인증됨', 'authenticated');
  String get authNotAuthenticated => _t('미인증', 'not authenticated');
  String authStateLabel(String state) =>
      _t('로그인 상태: $state', 'Sign-in status: $state');
  String get accountUnknown => _t('확인 불가', 'unavailable');
  String signedInAccountLabel(String account) =>
      _t('로그인 계정: $account', 'Signed-in account: $account');
  String get startGoogleSignIn => _t('Google 로그인 시작', 'Start Google Sign-in');
  String get startingGoogleSignIn =>
      _t('Google 로그인 준비 중...', 'Starting Google sign-in...');
  String get signInWithAnotherGoogleAccount =>
      _t('다른 Google 계정으로 로그인', 'Sign in with another Google account');
  String get logoutProviderLabel => _t('로그아웃', 'Log out');
  String get loggingOutProviderLabel => _t('로그아웃 중...', 'Logging out...');
  String get googleSignInHint => _t(
    '외부 브라우저에서 로그인한 뒤 앱으로 돌아오세요. 앱 복귀 시 인증 상태를 자동 갱신합니다.',
    'Use external browser sign-in, then return to app. Auth status refreshes automatically on resume.',
  );
  String get appleCredentialsTitle =>
      _t('Apple 자격증명 (앱 전용 비밀번호)', 'Apple credentials (app-specific password)');
  String get appleIdLabel => 'Apple ID';
  String get appleIdHint => 'name@example.com';
  String get appSpecificPasswordLabel =>
      _t('앱 전용 비밀번호', 'App-specific password');
  String get saveAppleCredentialsLabel =>
      _t('Apple 자격증명 저장', 'Save Apple credentials');
  String get savingAppleCredentialsLabel =>
      _t('Apple 자격증명 저장 중...', 'Saving Apple credentials...');
  String get applePasswordGuide => _t(
    'iCloud 로그인 비밀번호가 아닌 Apple 앱 전용 비밀번호를 사용하세요.',
    'Use an Apple app-specific password (not your iCloud login password).',
  );
  String redirectUriLabel(String uri) =>
      _t('리다이렉트 URI: $uri', 'Redirect URI: $uri');
  String get refreshAuthStatusLabel =>
      _t('로그인 상태 새로고침', 'Refresh sign-in status');
  String activeProviderLabel(String provider) =>
      _t('활성 연동 제공자: $provider', 'Active linked provider: $provider');
  String providerLoggedOut(String provider) =>
      _t('$provider 로그아웃 완료', '$provider logged out');
  String providerLogoutFailed(Object error) =>
      _t('로그아웃 실패: $error', 'Logout failed: $error');

  String get createEventTitle => _t('일정 만들기', 'Create Event');
  String get summaryLabel => _t('제목', 'Summary');
  String get summaryHint => _t('팀 동기화', 'Team sync');
  String get startTimeIsoLabel => _t('시작 시간 (ISO8601)', 'Start time (ISO8601)');
  String get endTimeIsoLabel => _t('종료 시간 (ISO8601)', 'End time (ISO8601)');
  String get allDayLabel => _t('종일', 'All day');
  String get createEventLabel => _t('일정 생성', 'Create Event');
  String get creatingEventLabel => _t('생성 중...', 'Creating...');
  String get eventCreated => _t('일정을 생성했습니다.', 'Event created.');
  String createFailed(Object error) =>
      _t('생성에 실패했습니다: $error', 'Create failed: $error');
  String get eventCreateRequiredFields =>
      _t('제목, 시작, 종료 시간을 모두 입력하세요.', 'Summary, start, and end are required.');
  String get invalidEventTimeRange => _t(
    '시작/종료 시간은 올바른 ISO datetime 형식이어야 하고 종료가 시작보다 빠를 수 없습니다.',
    'Start/end must be valid ISO datetime and end >= start.',
  );

  String get naturalInputTitle => _t('AI 일정 생성', 'AI Event Creation');
  String get naturalInputLabel => _t('자연어로 일정 설명', 'Describe event naturally');
  String get naturalInputHint =>
      _t('내일 오후 2시에 1시간 동안 디자인 싱크', 'Tomorrow 2pm design sync for 1 hour');
  String get aiExampleLabel => _t('예시', 'Examples');
  String get aiExampleOne =>
      _t('오늘 저녁 7시에 운동 1시간', 'Workout today at 7 PM for 1 hour');
  String get aiExampleTwo =>
      _t('내일 오전 10시에 팀 미팅', 'Team meeting tomorrow at 10 AM');
  String get aiExampleThree =>
      _t('다음 주 월요일 하루 종일 연차', 'All-day PTO next Monday');
  String get parseLabel => _t('해석', 'Parse');
  String get parsingLabel => _t('해석 중...', 'Parsing...');
  String get createLabel => _t('생성', 'Create');
  String get creatingLabel => _t('생성 중...', 'Creating...');
  String get enterNaturalInputText =>
      _t('자연어 입력 내용을 적어주세요.', 'Enter natural input text.');
  String get naturalInputTooLong => _t(
    '자연어 입력은 500자 이하로 작성해 주세요.',
    'Natural input must be 500 chars or less.',
  );
  String get naturalParseUnresolved =>
      _t('자연어 해석이 입력을 확정하지 못했습니다.', 'Natural parsing could not resolve input.');
  String parseFailed(Object error) =>
      _t('해석에 실패했습니다: $error', 'Parse failed: $error');
  String get parseFirstReady => _t(
    '먼저 해석을 실행해 결과가 준비된 상태인지 확인해 주세요.',
    'Parse first and ensure result is ready.',
  );
  String get eventCreatedFromNatural =>
      _t('자연어 입력으로 일정을 생성했습니다.', 'Event created from natural input.');
  String get naturalCreateFlowHint => _t(
    '생성을 누르면 AI 해석과 일정 생성을 한 번에 처리합니다.',
    'Create runs AI parsing and event creation in one step.',
  );
  String naturalCreateNoEvent(String intent) => _t(
    '일정을 생성하지 못했습니다. 해석 의도: $intent',
    'Event was not created. Parsed intent: $intent',
  );
  String naturalCreateNotCompleted(String reason) =>
      _t('일정 생성에 실패했습니다: $reason', 'Event creation failed: $reason');
  String readyLabel(bool ready) => _t('준비됨: $ready', 'Ready: $ready');
  String reasonLabel(String reason) => _t('사유: $reason', 'Reason: $reason');
  String intentLabel(String value) => _t('의도: $value', 'Intent: $value');
  String titleLabel(String value) => _t('제목: $value', 'Title: $value');
  String startLabel(String value) => _t('시작: $value', 'Start: $value');
  String endLabel(String value) => _t('종료: $value', 'End: $value');
  String allDayValueLabel(bool value) => _t('종일: $value', 'All day: $value');
  String confidenceLabel(double value) => _t(
    '신뢰도: ${value.toStringAsFixed(2)}',
    'Confidence: ${value.toStringAsFixed(2)}',
  );

  String get todayBriefingTitle => _t('오늘 브리핑', 'Today Briefing');
  String providerValue(String provider) =>
      _t('제공자: $provider', 'Provider: $provider');
  String generatedValue(String generatedAt) =>
      _t('생성 시각: $generatedAt', 'Generated: $generatedAt');
  String eventCountValue(int count) =>
      _t('일정 수: $count', 'Event count: $count');
  String get noBriefingYet => _t('아직 브리핑이 없습니다.', 'No briefing loaded yet.');
  String savedFileValue(String path) => _t('저장 파일: $path', 'Saved file: $path');
  String get loadBriefingLabel => _t('브리핑 불러오기', 'Load Briefing');
  String get loadingBriefingLabel => _t('불러오는 중...', 'Loading...');
  String get generateTtsLabel => _t('TTS 생성', 'Generate TTS');
  String get generatingTtsLabel => _t('생성 중...', 'Generating...');
  String get loadBriefingFirst => _t('먼저 브리핑을 불러오세요.', 'Load briefing first.');
  String get ttsGenerationComplete => _t(
    '생성이 완료되었습니다. 음성 파일을 앱 저장소에 저장했습니다.',
    'Generation Complete. Audio saved in app storage.',
  );
  String briefingLoadFailed(Object error) =>
      _t('브리핑을 불러오지 못했습니다: $error', 'Briefing load failed: $error');
  String ttsGenerationFailed(Object error) =>
      _t('TTS 생성에 실패했습니다: $error', 'TTS generation failed: $error');

  String get colorSchemaTitle => _t('색상 스키마', 'Color Schema');
  String colorSchemaLoadFailed(Object error) =>
      _t('색상 스키마를 불러오지 못했습니다: $error', 'Color schema load failed: $error');
  String applyStatusFailed(Object error) =>
      _t('적용 상태를 불러오지 못했습니다: $error', 'Apply status failed: $error');
  String get newRuleLabel => _t('새 규칙', 'New Rule');
  String get colorSchemaSaved => _t('색상 스키마를 저장했습니다.', 'Color schema saved.');
  String saveFailed(Object error) => _t('저장 실패: $error', 'Save failed: $error');
  String get applyStarted => _t('전체 적용을 시작했습니다.', 'Apply started.');
  String applyFailed(Object error) =>
      _t('적용 실패: $error', 'Apply failed: $error');
  String get selectColorTitle => _t('색상 선택', 'Select Color');
  String get labelFieldLabel => _t('라벨', 'Label');
  String get selectColorTooltip => _t('색상 선택', 'Select color');
  String get removeRuleTooltip => _t('규칙 삭제', 'Remove rule');
  String get addRuleLabel => _t('규칙 추가', 'Add Rule');
  String get saveRulesLabel => _t('규칙 저장', 'Save Rules');
  String get applyToAllLabel => _t('전체 적용', 'Apply to All');
  String get applyingLabel => _t('적용 중...', 'Applying...');
  String get statusApplying => _t('상태: 적용 중...', 'Status: Applying...');
  String statusLine({
    required bool running,
    required bool queued,
    required int processed,
    required int updated,
  }) {
    return _t(
      '상태: 실행=$running, 대기=$queued, 처리=$processed, 변경=$updated',
      'Status: running=$running, queued=$queued, processed=$processed, updated=$updated',
    );
  }

  String lastErrorLine(String error) =>
      _t('최근 오류: $error', 'Last error: $error');

  String get quickActionsTitle => _t('빠른 작업', 'Quick Actions');
  String get clockTabLabel => _t('시계', 'Clock');
  String get lockScreenAutoModeCardTitle => _t('잠금 자동 표시', 'Lock Auto Mode');
  String get lockScreenAutoModeCardDescription => _t(
    '앱 밖에서 화면을 켜면 가능한 한 빠르게 화면 보호기 시계로 진입합니다.',
    'When the screen wakes outside the app, enters the screen saver clock as quickly as possible.',
  );
  String get screenSaverSettingsCardTitle => _t('화면 보호기', 'Screen Saver');
  String get screenSaverSettingsCardDescription => _t(
    '화면 보호기 모드에서 표시할 UI 옵션을 관리합니다.',
    'Manage UI options shown in screen saver mode.',
  );
  String get screenSaverBottomPanelToggleLabel =>
      _t('하단 일정/시간 컨테이너 표시', 'Show bottom schedule/time container');
  String get screenSaverBottomPanelToggleHint => _t(
    '끄면 화면 보호기에서 시계만 표시됩니다.',
    'When off, only the clock is shown in screen saver mode.',
  );
  String get lockScreenAutoModeQuickAccessHint => _t(
    '백그라운드 잠금화면 기능은 Settings에서 관리합니다.',
    'Manage the background lock-screen feature in Settings.',
  );
  String get lockScreenAutoModeGoToSettingsAction =>
      _t('Settings에서 관리', 'Manage in Settings');
  String get lockScreenAutoModeBlockedByPermission => _t(
    '알림 권한이 없어 잠금 자동 표시가 차단되었습니다. 권한을 허용해 주세요.',
    'Lock auto mode is blocked because notification permission is missing. Please grant it.',
  );
  String get lockScreenAutoModeBlockedByPermissionShort =>
      _t('권한 필요', 'Permission needed');
  String get lockScreenAutoModeEnableAction =>
      _t('잠금 자동 표시 켜기', 'Enable Lock Auto Mode');
  String get lockScreenAutoModeDisableAction =>
      _t('잠금 자동 표시 끄기', 'Disable Lock Auto Mode');
  String get lockScreenAutoModeEnabled =>
      _t('잠금 자동 표시 모드를 활성화했습니다.', 'Lock auto mode enabled.');
  String get lockScreenAutoModeDisabled =>
      _t('잠금 자동 표시 모드를 비활성화했습니다.', 'Lock auto mode disabled.');
  String get lockScreenAutoModeSyncFailed => _t(
    '잠금 자동 표시 모드 동기화에 실패했습니다. Android 권한/정책을 확인해 주세요.',
    'Failed to sync lock auto mode. Check Android permissions/policies.',
  );
  String get lockScreenNotificationPermissionRequired => _t(
    '잠금 자동 표시 모드에는 알림 권한이 필요합니다.',
    'Notification permission is required for lock auto mode.',
  );
  String get lockScreenBatteryOptimizationHint => _t(
    '잠금 자동 표시 안정성을 높이려면 배터리 최적화 예외를 권장합니다.',
    'For better lock auto reliability, battery optimization exemption is recommended.',
  );
  String get lockScreenFullScreenIntentHint => _t(
    '앱 밖 화면에서 자동 표시 안정화를 위해 전체 화면 알림 권한을 권장합니다.',
    'For reliable auto-launch outside the app, full-screen notification access is recommended.',
  );
  String get lockScreenOverlayPermissionHint => _t(
    '다른 앱 위에 표시 권한을 허용하면 자동 진입 fallback이 강화됩니다.',
    'Allowing Draw over other apps improves auto-launch fallback behavior.',
  );
  String get openSettingsAction => _t('설정 열기', 'Open Settings');
  String get permissionStatusCardTitle => _t('권한 상태', 'Permission Status');
  String get permissionStatusCardDescription => _t(
    '잠금 자동 표시 관련 권한 상태를 확인하고 설정으로 바로 이동합니다.',
    'Check lock auto mode permission states and open related settings directly.',
  );
  String get permissionStatusDialogTitle =>
      _t('권한 상태 창', 'Permission Status Window');
  String get permissionStatusDialogDescription => _t(
    '현재 권한 상태를 확인하고 필요한 설정으로 이동하세요.',
    'Review current permission state and jump to required settings.',
  );
  String get permissionStatusAutoModeLabel =>
      _t('잠금 자동 표시 모드', 'Lock Auto Mode');
  String get permissionStatusNotificationLabel =>
      _t('알림 권한', 'Notification Permission');
  String get permissionStatusBatteryOptimizationLabel =>
      _t('배터리 최적화 예외', 'Battery Optimization Exemption');
  String get permissionStatusFullScreenIntentLabel =>
      _t('전체 화면 알림 권한', 'Full-screen Notification Access');
  String get permissionStatusOverlayPermissionLabel =>
      _t('다른 앱 위에 표시', 'Draw over other apps');
  String get permissionStatusValueEnabled => _t('활성화', 'Enabled');
  String get permissionStatusValueDisabled => _t('비활성화', 'Disabled');
  String get permissionStatusValueGranted => _t('허용됨', 'Granted');
  String get permissionStatusValueNotGranted => _t('허용 안 됨', 'Not granted');
  String get permissionStatusValueExempted => _t('예외 적용됨', 'Exempted');
  String get permissionStatusValueNotExempted => _t('최적화 대상', 'Not exempted');
  String get permissionStatusValueAllowed => _t('허용됨', 'Allowed');
  String get permissionStatusValueBlocked => _t('차단됨', 'Blocked');
  String get permissionStatusValueNotRequired => _t('요청 불필요', 'Not required');
  String get permissionStatusValueUnknown => _t('확인 불가', 'Unknown');
  String get permissionStatusRefreshAction => _t('상태 새로고침', 'Refresh Status');
  String get permissionStatusOpenNotificationSettingsAction =>
      _t('알림 설정 열기', 'Open Notification Settings');
  String get permissionStatusOpenBatterySettingsAction =>
      _t('배터리 설정 열기', 'Open Battery Settings');
  String get permissionStatusOpenFullScreenIntentSettingsAction =>
      _t('전체 화면 알림 설정 열기', 'Open Full-screen Notification Settings');
  String get permissionStatusOpenOverlaySettingsAction =>
      _t('오버레이 권한 설정 열기', 'Open Overlay Permission Settings');
  String get permissionStatusOpenAppPermissionSettingsAction =>
      _t('앱 권한 설정 열기', 'Open App Permission Settings');
  String permissionStatusOpenSettingsFailed(String target) =>
      _t('$target 설정을 열지 못했습니다.', 'Failed to open $target settings.');
  String get closeAction => _t('닫기', 'Close');
  String get screenSaverTitle => _t('화면 보호기 모드', 'Screen Saver Mode');
  String get screenSaverExitLabel => _t('화면 보호기 종료', 'Exit screen saver');
  String get providerAuthAction => _t('로그인/연동', 'Login/Linking');
  String get eventToolsAction => _t('AI 일정 생성', 'AI Event Creation');
  String get briefingAction => _t('브리핑', 'Briefing');
  String get settingsAction => _t('설정', 'Settings');
  String get loginLinkingOnboardingTitle =>
      _t('로그인 및 연동 온보딩', 'Login & Linking Onboarding');
  String get loginLinkingOnboardingDescription => _t(
    '앱 시작 전에 캘린더 제공자 로그인 및 연동을 완료해 주세요. 완료되면 다시 보지 않습니다.',
    'Before using the app, complete provider sign-in and linking. You only need to do this once.',
  );
  String get loginLinkingOnboardingPendingHint => _t(
    '로그인 및 연동이 완료되면 자동으로 메인 화면으로 이동합니다.',
    'After sign-in and linking are completed, you will be moved to the main screen automatically.',
  );
  String get onboardingLanguageStepTitle =>
      _t('1. 언어 선택', '1. Choose language');
  String get onboardingProviderStepTitle =>
      _t('2. 캘린더 선택', '2. Choose calendar');
  String get onboardingLoginStepTitle =>
      _t('3. 로그인 및 연동', '3. Login & Linking');
  String get onboardingContinueToProviderLabel =>
      _t('다음: 캘린더 선택', 'Next: Calendar');
  String get onboardingContinueToLoginLabel =>
      _t('다음: 로그인 및 연동', 'Next: Login & Linking');
  String get onboardingBackLabel => _t('이전', 'Back');
  String onboardingSelectedProviderLabel(String provider) =>
      _t('선택된 캘린더: $provider', 'Selected calendar: $provider');
  String get loginLinkingSettingsTitle => _t('로그인 및 연동', 'Login & Linking');
  String get openLoginLinkingLabel => _t('로그인 및 연동 열기', 'Open Login & Linking');
  String get manageLoginLinkingLabel =>
      _t('로그인 및 연동 관리', 'Manage Login & Linking');
  String get todayAtGlanceTitle => _t('오늘 요약', 'Today at a glance');
  String authenticatedSummary(bool? authenticated) {
    final value = authenticated == true
        ? _t('예', 'yes')
        : authenticated == false
        ? _t('아니오', 'no')
        : _t('알 수 없음', 'unknown');
    return _t('인증됨: $value', 'Authenticated: $value');
  }

  String accountSummary(String? accountLabel) {
    final value = (accountLabel == null || accountLabel.trim().isEmpty)
        ? accountUnknown
        : accountLabel.trim();
    return _t('계정: $value', 'Account: $value');
  }

  String eventsSummary(int count) => _t('일정: $count', 'Events: $count');
  String segmentsSummary(int count) => _t('세그먼트: $count', 'Segments: $count');
  String sourceSummary(String source) => _t('소스 $source', 'source $source');
  String get googleAuthCompleted =>
      _t('Google 인증이 완료되었습니다.', 'Google authentication completed.');
  String get googleAuthFailed =>
      _t('Google 인증에 실패했습니다.', 'Google authentication failed.');
  String get invalidGoogleAuthUrl =>
      _t('Google 인증 URL이 올바르지 않습니다.', 'Invalid Google auth url');
  String get unableToOpenBrowser =>
      _t('브라우저를 자동으로 열지 못했습니다.', 'Unable to open browser automatically.');
  String get completeSignInThenRefresh => _t(
    '브라우저에서 로그인을 완료한 뒤 인증 상태 새로고침을 눌러 주세요.',
    'Complete sign-in in browser, then tap Refresh auth status.',
  );
  String googleAuthStartFailed(String detail) =>
      _t('Google 인증 시작 실패: $detail', 'Google auth start failed: $detail');
  String googleAuthBackendUnreachable(
    String baseUrl, {
    required bool localBackend,
    required bool emulatorHint,
  }) {
    if (!localBackend) {
      return _t(
        'Google 인증 시작 실패: 백엔드에 연결할 수 없습니다 ($baseUrl). 네트워크 연결과 서버 상태를 확인해 주세요.',
        'Google auth start failed: backend unreachable ($baseUrl). Check your network connection and server availability.',
      );
    }

    final hint = emulatorHint
        ? _t(
            ' BACKEND_BASE_URL을 확인하세요. 에뮬레이터 별칭은 10.0.2.2 입니다.',
            ' Check BACKEND_BASE_URL; for Android emulator alias use 10.0.2.2.',
          )
        : '';

    return _t(
      'Google 인증 시작 실패: 백엔드에 연결할 수 없습니다 ($baseUrl). 실기기에서는 adb reverse tcp:8000 tcp:8000 또는 --dart-define=BACKEND_BASE_URL 설정을 확인하세요.$hint',
      'Google auth start failed: backend unreachable ($baseUrl). For physical Android, run adb reverse tcp:8000 tcp:8000 or set --dart-define=BACKEND_BASE_URL.$hint',
    );
  }

  String refreshFailed(String detail) =>
      _t('새로고침 실패: $detail', 'Refresh failed: $detail');
  String refreshBackendUnreachable(
    String baseUrl, {
    required bool localBackend,
    required bool emulatorHint,
  }) {
    if (!localBackend) {
      return _t(
        '새로고침 실패: 백엔드에 연결할 수 없습니다 ($baseUrl). 네트워크 연결과 서버 상태를 확인해 주세요.',
        'Refresh failed: backend unreachable ($baseUrl). Check your network connection and server availability.',
      );
    }

    final hint = emulatorHint
        ? _t(
            ' BACKEND_BASE_URL을 확인하세요. 에뮬레이터 별칭은 10.0.2.2 입니다.',
            ' Check BACKEND_BASE_URL; for Android emulator alias use 10.0.2.2.',
          )
        : '';
    return _t(
      '새로고침 실패: 백엔드에 연결할 수 없습니다 ($baseUrl). 실기기에서는 cw-adb reverse tcp:8000 tcp:8000 를 실행하세요.$hint',
      'Refresh failed: backend unreachable ($baseUrl). For physical Android, run cw-adb reverse tcp:8000 tcp:8000.$hint',
    );
  }

  String get enterAppleCredentials => _t(
    'Apple ID와 앱 전용 비밀번호를 입력하세요.',
    'Enter Apple ID and app-specific password.',
  );
  String get appleCredentialsSavedAndAuthenticated => _t(
    'Apple 자격증명을 저장했고 인증도 완료되었습니다.',
    'Apple credentials saved and authenticated.',
  );
  String get appleCredentialsSavedVerify => _t(
    'Apple 자격증명을 저장했습니다. 인증 상태를 확인해 주세요.',
    'Apple credentials saved. Verify auth status.',
  );
  String appleCredentialSaveFailed(Object error) =>
      _t('Apple 자격증명 저장 실패: $error', 'Apple credential save failed: $error');

  String get refreshClockSnapshotTooltip =>
      _t('시계 스냅샷 새로고침', 'Refresh clock snapshot');
  String get previousDateTooltip => _t('이전 날짜', 'Previous date');
  String get nextDateTooltip => _t('다음 날짜', 'Next date');
  String get todayButton => _t('오늘', 'Today');

  String weekdayAbbreviation(int weekday) {
    if (weekday < 1 || weekday > 7) {
      return '-';
    }
    const korean = <String>['월', '화', '수', '목', '금', '토', '일'];
    const english = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return _isKorean ? korean[weekday - 1] : english[weekday - 1];
  }
}

extension AppI18nBuildContext on BuildContext {
  AppI18n get i18n => AppI18n(AppLanguageScope.of(this).language);

  AppLanguageController get languageController => AppLanguageScope.of(this);
}
