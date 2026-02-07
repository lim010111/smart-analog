import os
import datetime
import pickle
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build
from src.models.event import CalendarEvent
from PySide6.QtGui import QColor

# 읽기 권한 설정
SCOPES = ['https://www.googleapis.com/auth/calendar.readonly']

# Google 캘린더 표준 이벤트 색상 맵핑
GOOGLE_COLORS = {
    "1": "#a4bdfc",  # Lavender
    "2": "#7ae148",  # Sage
    "3": "#bdadff",  # Grape
    "4": "#ff887c",  # Flamingo
    "5": "#fbd75b",  # Banana
    "6": "#ffb878",  # Tangerine
    "7": "#46d6db",  # Peacock
    "8": "#e1e1e1",  # Graphite
    "9": "#5484ed",  # Blueberry
    "10": "#51b749", # Basil
    "11": "#dc2127"  # Tomato
}

class CalendarService:
    def __init__(self, credentials_path='credentials.json', token_path='token.json'):
        self.credentials_path = credentials_path
        self.token_path = token_path
        self.creds = None
        self.service = None

    def authenticate(self):
        """사용자 인증을 처리하고 API 서비스를 초기화합니다."""
        if os.path.exists(self.token_path):
            with open(self.token_path, 'rb') as token:
                self.creds = pickle.load(token)
        
        # 유효한 자격 증명이 없으면 로그인을 시도합니다.
        if not self.creds or not self.creds.valid:
            if self.creds and self.creds.expired and self.creds.refresh_token:
                self.creds.refresh(Request())
            else:
                if not os.path.exists(self.credentials_path):
                    raise FileNotFoundError(f"'{self.credentials_path}' 파일이 필요합니다. Google Cloud Console에서 다운로드해 주세요.")
                
                flow = InstalledAppFlow.from_client_secrets_file(
                    self.credentials_path, SCOPES)
                self.creds = flow.run_local_server(port=0)
            
            # 자격 증명을 저장합니다.
            with open(self.token_path, 'wb') as token:
                pickle.dump(self.creds, token)

        self.service = build('calendar', 'v3', credentials=self.creds)

    def get_upcoming_events(self, max_results=10):
        """현재 시간 이후의 일정을 가져옵니다."""
        if not self.service:
            self.authenticate()

        # 오늘 날짜의 시작(00:00:00)과 끝(23:59:59) 계산
        now_local = datetime.datetime.now()
        start_of_day = now_local.replace(hour=0, minute=0, second=0, microsecond=0)
        end_of_day = now_local.replace(hour=23, minute=59, second=59, microsecond=0)
        
        # Google API를 위한 UTC ISO 포맷 변환
        time_min = start_of_day.astimezone(datetime.timezone.utc).isoformat().replace('+00:00', 'Z')
        time_max = end_of_day.astimezone(datetime.timezone.utc).isoformat().replace('+00:00', 'Z')

        events_result = self.service.events().list(
            calendarId='primary', 
            timeMin=time_min,
            timeMax=time_max,
            maxResults=max_results, 
            singleEvents=True,
            orderBy='startTime'
        ).execute()
        
        items = events_result.get('items', [])
        calendar_events = []
        
        for item in items:
            start_data = item['start']
            end_data = item['end']
            
            # dateTime이 없으면 종일 일정이므로 제외 (사용자 요청)
            if 'dateTime' not in start_data:
                continue
                
            start_str = start_data['dateTime']
            end_str = end_data['dateTime']
            
            # ISO 8601 형식 파싱
            # 종일 일정(2026-01-01 형식)은 파싱 후 타임존 정보가 없으므로 UTC를 부여하여 Aware 상태로 만듦
            start_time = datetime.datetime.fromisoformat(start_str.replace('Z', '+00:00'))
            if start_time.tzinfo is None:
                start_time = start_time.replace(tzinfo=datetime.timezone.utc)
                
            end_time = datetime.datetime.fromisoformat(end_str.replace('Z', '+00:00'))
            if end_time.tzinfo is None:
                end_time = end_time.replace(tzinfo=datetime.timezone.utc)
            
            # 색상 설정 (colorId가 있으면 맵핑 사용, 없으면 기본값)
            color_id = item.get('colorId')
            event_color = None
            if color_id in GOOGLE_COLORS:
                event_color = QColor(GOOGLE_COLORS[color_id])
                # 투명도 조절 (기본 180 설정)
                event_color.setAlpha(180)
            
            # CalendarEvent 생성 시 색상을 전달 (있을 경우만)
            event_args = {
                "id": item['id'],
                "summary": item.get('summary', '(제목 없음)'),
                "start_time": start_time,
                "end_time": end_time
            }
            if event_color:
                event_args["color"] = event_color
                
            event = CalendarEvent(**event_args)
            calendar_events.append(event)
            
        return calendar_events
