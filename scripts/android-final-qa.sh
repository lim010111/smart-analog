#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/mobile/flutter_app"

BACKEND_URL="${CW_QA_BACKEND_URL:-http://127.0.0.1:8000}"
ADB_SOCKET="${CW_QA_ADB_SOCKET:-tcp:127.0.0.1:5037}"
DEVICE_ID="${CW_QA_DEVICE_ID:-R3CR10HFD7R}"
APP_PACKAGE="${CW_QA_APP_PACKAGE:-com.smartanalog.flutter_app}"

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
LOG_DIR="${CW_QA_LOG_DIR:-/tmp/clock_widget_android_final_qa_${TIMESTAMP}}"
mkdir -p "$LOG_DIR"

pass() {
  printf '[PASS] %s\n' "$1"
}

fail() {
  printf '[FAIL] %s\n' "$1"
  exit 1
}

run_cmd_log() {
  local name="$1"
  shift
  local log_file="$LOG_DIR/${name}.log"
  if "$@" >"$log_file" 2>&1; then
    pass "$name"
  else
    fail "$name (see $log_file)"
  fi
}

printf '[INFO] Android final QA start\n'
printf '[INFO] ROOT_DIR=%s\n' "$ROOT_DIR"
printf '[INFO] BACKEND_URL=%s\n' "$BACKEND_URL"
printf '[INFO] DEVICE_ID=%s\n' "$DEVICE_ID"
printf '[INFO] LOG_DIR=%s\n' "$LOG_DIR"

HEALTH_CODE="$(curl --max-time 8 -sS -o "$LOG_DIR/backend_health_body.json" -w "%{http_code}" "$BACKEND_URL/health")" || fail "backend_health_request"
if [[ "$HEALTH_CODE" != "200" ]]; then
  fail "backend_health_expected_200_got_${HEALTH_CODE}"
fi
pass "backend_health_200"

run_cmd_log adb_devices env ADB_SERVER_SOCKET="$ADB_SOCKET" adb devices -l
if ! grep -qE "^${DEVICE_ID}[[:space:]]+device" "$LOG_DIR/adb_devices.log"; then
  fail "device_not_ready (see $LOG_DIR/adb_devices.log)"
fi
pass "device_ready"

run_cmd_log adb_reverse env ADB_SERVER_SOCKET="$ADB_SOCKET" adb -s "$DEVICE_ID" reverse tcp:8000 tcp:8000
run_cmd_log adb_reverse_list env ADB_SERVER_SOCKET="$ADB_SOCKET" adb -s "$DEVICE_ID" reverse --list
if ! grep -q "tcp:8000" "$LOG_DIR/adb_reverse_list.log"; then
  fail "adb_reverse_mapping_missing"
fi
pass "adb_reverse_ok"

run_cmd_log flutter_analyze bash -lc "cd \"$APP_DIR\" && flutter analyze"
run_cmd_log flutter_test bash -lc "cd \"$APP_DIR\" && flutter test"
run_cmd_log flutter_build_debug bash -lc "cd \"$APP_DIR\" && flutter build apk --debug"

run_cmd_log flutter_run_release bash -lc "cd \"$APP_DIR\" && ADB_SERVER_SOCKET=\"$ADB_SOCKET\" flutter run -d \"$DEVICE_ID\" --release --no-resident --target lib/main.dart"
run_cmd_log app_pid env ADB_SERVER_SOCKET="$ADB_SOCKET" adb -s "$DEVICE_ID" shell pidof "$APP_PACKAGE"

if [[ ! -s "$LOG_DIR/app_pid.log" ]]; then
  fail "app_pid_missing"
fi
pass "app_process_running"

QA_JSON_LOG="$LOG_DIR/backend_e2e_summary.json"

python3 - <<'PY' >"$QA_JSON_LOG"
import datetime as dt
import json
import os
from urllib import parse, request
from urllib.error import HTTPError

base = os.environ.get('CW_QA_BACKEND_URL', 'http://127.0.0.1:8000')

def get(url):
    with request.urlopen(url, timeout=30) as resp:
        return resp.status, json.loads(resp.read().decode())

def get_raw(url):
    with request.urlopen(url, timeout=30) as resp:
        return resp.status, resp.read().decode()

def post_json(url, payload):
    req = request.Request(url, data=json.dumps(payload).encode(), headers={'Content-Type': 'application/json'}, method='POST')
    try:
        with request.urlopen(req, timeout=60) as resp:
            return resp.status, json.loads(resp.read().decode())
    except HTTPError as err:
        body = err.read().decode()
        try:
            parsed = json.loads(body)
        except Exception:
            parsed = {'raw': body}
        return err.code, parsed

def put_json(url, payload):
    req = request.Request(url, data=json.dumps(payload).encode(), headers={'Content-Type': 'application/json'}, method='PUT')
    with request.urlopen(req, timeout=30) as resp:
        return resp.status, json.loads(resp.read().decode())

result = {}

# Settings round-trip
s_code, settings_before = get(f'{base}/api/settings')
patched = dict(settings_before)
patched['clock_opacity'] = max(0, min(100, int(patched.get('clock_opacity', 100)) - 1))
u_code, settings_patched = put_json(f'{base}/api/settings', patched)
sa_code, settings_after = get(f'{base}/api/settings')
_ = put_json(f'{base}/api/settings', settings_before)
result['settings_roundtrip'] = {
    'get_before': s_code,
    'put_patch': u_code,
    'get_after': sa_code,
    'patched_clock_opacity': settings_patched.get('clock_opacity'),
}

# Providers/Auth
p_code, providers = get(f'{base}/api/providers')
ps_code, provider_status = get(f"{base}/api/providers/status?{parse.urlencode({'provider': 'google'})}")
ga_code, google_auth = post_json(f"{base}/api/providers/google/auth-url?{parse.urlencode({'mobile_callback': 'smartanalog://auth/google'})}", {})
result['providers_auth'] = {
    'providers_status': p_code,
    'provider_status_status': ps_code,
    'google_auth_url_status': ga_code,
    'authenticated': provider_status.get('authenticated') if isinstance(provider_status, dict) else None,
    'has_auth_url': isinstance(google_auth, dict) and bool(google_auth.get('auth_url')),
}

# Events/Natural Input
np_code, np = post_json(f"{base}/api/events/natural-input/parse?{parse.urlencode({'provider': 'google'})}", {'text': '내일 오후 2시에 1시간 회의 일정 추가해줘'})
nc_code, nc = post_json(f"{base}/api/events/natural-input/create?{parse.urlencode({'provider': 'google'})}", {'text': '내일 오후 2시에 30분 회의 일정 추가해줘'})
now = dt.datetime.now(dt.timezone.utc).astimezone()
start = (now + dt.timedelta(hours=2)).replace(microsecond=0)
end = (start + dt.timedelta(minutes=30)).replace(microsecond=0)
ec_code, ec = post_json(f"{base}/api/events/create?{parse.urlencode({'provider': 'google'})}", {
    'summary': 'ClockWidget Android Final QA Event',
    'start_time': start.isoformat(),
    'end_time': end.isoformat(),
    'all_day': False,
})
result['events_natural'] = {
    'natural_parse_status': np_code,
    'natural_parse_ready': np.get('ready') if isinstance(np, dict) else None,
    'natural_create_status': nc_code,
    'natural_create_has_created': bool(isinstance(nc, dict) and nc.get('created')),
    'event_create_status': ec_code,
    'event_create_has_event': bool(isinstance(ec, dict) and ec.get('event')),
}

# Natural low-confidence failure-like path
nf_code, nf = post_json(f"{base}/api/events/natural-input/create?{parse.urlencode({'provider': 'google'})}", {'text': 'a'})
result['natural_low_confidence'] = {
    'status': nf_code,
    'parsed_intent': nf.get('parsed', {}).get('intent') if isinstance(nf, dict) else None,
    'created_is_null': isinstance(nf, dict) and nf.get('created') is None,
}

# Briefing/TTS
b_code, briefing = get(f"{base}/api/briefing/today?{parse.urlencode({'provider': 'google', 'force': 'true'})}")
t0_code, t0 = post_json(f"{base}/api/briefing/tts/base64", {'text': 'Final QA TTS check', 'response_format': 'wav'})
original = settings_before
patched_tts = dict(original)
patched_tts['briefing_tts_enabled'] = True
_ = put_json(f'{base}/api/settings', patched_tts)
t1_code, t1 = post_json(f"{base}/api/briefing/tts/base64", {'text': 'Final QA TTS check', 'response_format': 'wav'})
_ = put_json(f'{base}/api/settings', original)
result['briefing_tts'] = {
    'briefing_status': b_code,
    'briefing_event_count': briefing.get('event_count') if isinstance(briefing, dict) else None,
    'tts_disabled_status': t0_code,
    'tts_enabled_status': t1_code,
    'tts_enabled_format': t1.get('format') if isinstance(t1, dict) else None,
    'tts_audio_len': len(t1.get('audio_base64', '')) if isinstance(t1, dict) else 0,
}

# Colors apply/status
cp_code, cp = get(f"{base}/api/colors/palette?{parse.urlencode({'provider': 'google'})}")
cs_code, cs = get(f"{base}/api/colors/schema?{parse.urlencode({'provider': 'google'})}")
rules = cs.get('rules', []) if isinstance(cs, dict) else []
cu_code, cu = put_json(f"{base}/api/colors/schema?{parse.urlencode({'provider': 'google'})}", {'rules': rules})
ca_code, ca = post_json(f"{base}/api/colors/apply-all?{parse.urlencode({'provider': 'google', 'page_size': '250'})}", {})
st_code, st = get(f"{base}/api/colors/apply-status?{parse.urlencode({'provider': 'google'})}")
result['colors_apply'] = {
    'palette_status': cp_code,
    'schema_get_status': cs_code,
    'schema_put_status': cu_code,
    'apply_all_status': ca_code,
    'apply_status_status': st_code,
    'running': st.get('running') if isinstance(st, dict) else None,
    'queued': st.get('queued') if isinstance(st, dict) else None,
    'last_started_at_type': type(st.get('last_started_at')).__name__ if isinstance(st, dict) else None,
    'last_finished_at_type': type(st.get('last_finished_at')).__name__ if isinstance(st, dict) else None,
}

assert result['settings_roundtrip']['get_before'] == 200
assert result['settings_roundtrip']['put_patch'] == 200
assert result['settings_roundtrip']['get_after'] == 200

assert result['providers_auth']['providers_status'] == 200
assert result['providers_auth']['provider_status_status'] == 200
assert result['providers_auth']['google_auth_url_status'] == 200
assert result['providers_auth']['has_auth_url']

assert result['events_natural']['natural_parse_status'] == 200
assert result['events_natural']['natural_create_status'] == 200
assert result['events_natural']['event_create_status'] == 200

assert result['briefing_tts']['briefing_status'] == 200
assert result['briefing_tts']['tts_disabled_status'] == 400
assert result['briefing_tts']['tts_enabled_status'] == 200
assert result['briefing_tts']['tts_audio_len'] > 0

assert result['colors_apply']['palette_status'] == 200
assert result['colors_apply']['schema_get_status'] == 200
assert result['colors_apply']['schema_put_status'] == 200
assert result['colors_apply']['apply_all_status'] == 200
assert result['colors_apply']['apply_status_status'] == 200

print(json.dumps(result, ensure_ascii=False, indent=2))
PY

pass "backend_e2e_checks"

run_cmd_log deep_link_intent env ADB_SERVER_SOCKET="$ADB_SOCKET" adb -s "$DEVICE_ID" shell am start -W -a android.intent.action.VIEW -d "smartanalog://auth/google?status=success&provider=google&message=qa"
if ! grep -q "$APP_PACKAGE/.MainActivity" "$LOG_DIR/deep_link_intent.log"; then
  fail "deep_link_not_routed_to_app"
fi
pass "deep_link_routing"

printf '[INFO] Android final QA completed successfully\n'
printf '[INFO] Logs: %s\n' "$LOG_DIR"
