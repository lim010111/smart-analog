import sys
import os

# Windows 전용 라이브러리 (조건부 임포트)
if sys.platform == 'win32':
    import winreg
else:
    winreg = None

APP_NAME = "ClockWidget"
REG_PATH = r"Software\Microsoft\Windows\CurrentVersion\Run"

def get_executable_path():
    """현재 실행 파일 또는 스크립트의 절대 경로를 반환합니다."""
    if getattr(sys, 'frozen', False):
        # PyInstaller로 빌드된 경우
        return sys.executable
    else:
        # 스크립트로 실행되는 경우 (uv run src/main.py 등)
        # 실제 배포 시에는 빌드된 .exe 경로가 등록되어야 함
        return os.path.abspath(sys.argv[0])

def is_startup_enabled():
    """레지스트리에 시작 프로그램으로 등록되어 있는지 확인합니다."""
    if winreg is None:
        return False
        
    try:
        key = winreg.OpenKey(winreg.HKEY_CURRENT_USER, REG_PATH, 0, winreg.KEY_READ)
        try:
            winreg.QueryValueEx(key, APP_NAME)
            return True
        except FileNotFoundError:
            return False
        finally:
            winreg.CloseKey(key)
    except Exception:
        return False

def set_startup(enabled: bool):
    """시작 프로그램 등록 또는 해제를 수행합니다."""
    if winreg is None:
        return False
        
    try:
        key = winreg.OpenKey(winreg.HKEY_CURRENT_USER, REG_PATH, 0, winreg.KEY_WRITE | winreg.KEY_READ)
        if enabled:
            # 실행 경로 등록
            path = get_executable_path()
            winreg.SetValueEx(key, APP_NAME, 0, winreg.REG_SZ, path)
        else:
            # 등록 삭제
            try:
                winreg.DeleteValue(key, APP_NAME)
            except FileNotFoundError:
                pass
        winreg.CloseKey(key)
        return True
    except Exception as e:
        print(f"Failed to update startup registry: {e}")
        return False
