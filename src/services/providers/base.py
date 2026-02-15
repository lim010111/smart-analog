from abc import ABC, abstractmethod
from src.models.event import CalendarEvent


class CalendarProvider(ABC):
    """캘린더 프로바이더의 공통 인터페이스를 정의합니다."""

    @property
    @abstractmethod
    def provider_name(self) -> str:
        """프로바이더의 표시 이름을 반환합니다. (예: 'Google', 'Apple')"""
        ...

    @abstractmethod
    def authenticate(self) -> None:
        """사용자 인증을 수행합니다.

        인증에 실패하면 Exception을 발생시킵니다.
        """
        ...

    @abstractmethod
    def is_authenticated(self) -> bool:
        """현재 유효한 인증 상태인지 확인합니다."""
        ...

    @abstractmethod
    def get_todays_events(self, max_results: int = 20) -> list[CalendarEvent]:
        """오늘의 일정을 가져옵니다.

        인증이 안 되어 있으면 내부적으로 authenticate()를 호출합니다.
        종일 일정은 제외하고, 시작 시간 순으로 정렬하여 반환합니다.
        """
        ...

    @abstractmethod
    def logout(self) -> None:
        """인증 상태를 초기화하고 저장된 자격 증명을 삭제합니다."""
        ...
