#include "restriction_window.h"
#include "windows_apps.h"

#include <algorithm>
#include <cwctype>
#include <iterator>
#include <vector>

namespace {
bool MatchesApp(DWORD pid, const std::string& source) {
  if (source.rfind("windows:", 0) != 0 || pid == 0 || pid == GetCurrentProcessId()) return false;
  DWORD own_session = 0, target_session = 0;
  if (!ProcessIdToSessionId(GetCurrentProcessId(), &own_session) ||
      !ProcessIdToSessionId(pid, &target_session) || own_session != target_session) return false;
  const HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (!process) return false;
  std::vector<wchar_t> buffer(32768);
  DWORD length = static_cast<DWORD>(buffer.size());
  const bool queried = QueryFullProcessImageNameW(process, 0, buffer.data(), &length) != FALSE;
  CloseHandle(process);
  if (!queried) return false;
  std::wstring executable(buffer.data(), length);
  executable = executable.substr(executable.find_last_of(L"\\/") + 1);
  std::transform(executable.begin(), executable.end(), executable.begin(), towlower);
  if (IsProtectedWindowsApp(executable)) return false;
  const std::string expected_utf8 = source.substr(8);
  const int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, expected_utf8.data(), static_cast<int>(expected_utf8.size()), nullptr, 0);
  if (size <= 0) return false;
  std::wstring expected(size, L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, expected_utf8.data(), static_cast<int>(expected_utf8.size()), expected.data(), size);
  std::transform(expected.begin(), expected.end(), expected.begin(), towlower);
  return CompareStringOrdinal(expected.c_str(), -1, executable.c_str(), -1, TRUE) == CSTR_EQUAL;
}

bool FocusOwned(HWND window) {
  const DWORD current = GetCurrentThreadId();
  const DWORD foreground = GetWindowThreadProcessId(GetForegroundWindow(), nullptr);
  const bool attached = foreground && foreground != current && AttachThreadInput(current, foreground, TRUE);
  BringWindowToTop(window);
  SetForegroundWindow(window);
  if (attached) AttachThreadInput(current, foreground, FALSE);
  return GetForegroundWindow() == window;
}
}  // namespace

RestrictionWindow::~RestrictionWindow() { Dismiss(); }

std::string RestrictionWindow::Present(DWORD pid, const std::string& source) {
  HWND foreground = GetForegroundWindow();
  DWORD actual = 0;
  GetWindowThreadProcessId(foreground, &actual);
  if (actual != pid || !MatchesApp(pid, source)) return "stale";
  const HWND target = GetAncestor(foreground, GA_ROOT);
  MONITORINFO display{sizeof(MONITORINFO)};
  if (!GetMonitorInfoW(MonitorFromWindow(target, MONITOR_DEFAULTTONEAREST), &display)) return "refused";
  DWORD_PTR ignored = 0;
  if (!SendMessageTimeoutW(target, WM_SYSCOMMAND, SC_MINIMIZE, 0,
                          SMTO_ABORTIFHUNG | SMTO_BLOCK, 200, &ignored) || !IsIconic(target)) return "refused";
  target_ = target;
  if (!active_) {
    was_visible_ = IsWindowVisible(window_) != FALSE;
    was_minimized_ = IsIconic(window_) != FALSE;
    if (was_minimized_) ShowWindow(window_, SW_RESTORE);
    GetWindowPlacement(window_, &placement_);
    style_ = GetWindowLongPtrW(window_, GWL_STYLE);
    ex_style_ = GetWindowLongPtrW(window_, GWL_EXSTYLE);
    GetWindowRect(window_, &bounds_);
  }
  monitor_ = display.rcMonitor;
  active_ = true;
  SetWindowLongPtrW(window_, GWL_STYLE,
      (style_ & ~(WS_OVERLAPPEDWINDOW | WS_MINIMIZE | WS_MAXIMIZE)) | WS_POPUP);
  CoverMonitor();
  RECT covered{};
  const bool covers_monitor = GetWindowRect(window_, &covered) && EqualRect(&covered, &monitor_);
  if (!covers_monitor || !FocusOwned(window_)) {
    // The app is still minimized, but do not obscure an allowed app if Windows
    // refuses focus. A later attempt can present the full-screen explanation.
    Dismiss();
    return "minimized";
  }
  return "shown";
}

void RestrictionWindow::CoverMonitor() {
  if (!active_ || positioning_) return;
  positioning_ = true;
  SetWindowPos(window_, HWND_TOPMOST, monitor_.left, monitor_.top,
               monitor_.right - monitor_.left, monitor_.bottom - monitor_.top,
               SWP_FRAMECHANGED | SWP_SHOWWINDOW);
  positioning_ = false;
}

void RestrictionWindow::Dismiss() {
  if (!active_) return;
  active_ = false;
  auto placement = placement_;
  placement.showCmd = SW_SHOWNOACTIVATE;
  SetWindowPlacement(window_, &placement);
  SetWindowLongPtrW(window_, GWL_STYLE, style_);
  SetWindowLongPtrW(window_, GWL_EXSTYLE, ex_style_);
  if (!MonitorFromRect(&bounds_, MONITOR_DEFAULTTONULL)) {
    MONITORINFO display{sizeof(MONITORINFO)};
    if (GetMonitorInfoW(MonitorFromRect(&bounds_, MONITOR_DEFAULTTONEAREST), &display)) {
      OffsetRect(&bounds_, display.rcWork.left - bounds_.left, display.rcWork.top - bounds_.top);
    }
  }
  SetWindowPos(window_, (ex_style_ & WS_EX_TOPMOST) ? HWND_TOPMOST : HWND_NOTOPMOST,
               bounds_.left, bounds_.top, bounds_.right - bounds_.left,
               bounds_.bottom - bounds_.top, SWP_FRAMECHANGED | SWP_NOACTIVATE);
  if (!was_visible_) ShowWindow(window_, SW_HIDE);
  else if (was_minimized_) ShowWindow(window_, SW_SHOWMINNOACTIVE);
}

std::optional<LRESULT> RestrictionWindow::HandleMessage(UINT message, WPARAM wparam, LPARAM lparam) {
  if (!active_) return std::nullopt;
  if (message == WM_DISPLAYCHANGE) {
    MONITORINFO display{sizeof(MONITORINFO)};
    if (GetMonitorInfoW(MonitorFromWindow(window_, MONITOR_DEFAULTTONEAREST), &display)) {
      monitor_ = display.rcMonitor;
      CoverMonitor();
    }
  }
  if (message == WM_CLOSE) return 0;
  if (message == WM_SYSCOMMAND) {
    const auto command = wparam & 0xfff0;
    if (command == SC_CLOSE || command == SC_MINIMIZE || command == SC_MOVE ||
        command == SC_SIZE || command == SC_MAXIMIZE || command == SC_RESTORE) return 0;
  }
  if (message == WM_WINDOWPOSCHANGING && !positioning_) {
    auto* position = reinterpret_cast<WINDOWPOS*>(lparam);
    position->x = monitor_.left;
    position->y = monitor_.top;
    position->cx = monitor_.right - monitor_.left;
    position->cy = monitor_.bottom - monitor_.top;
    position->hwndInsertAfter = HWND_TOPMOST;
    position->flags &= ~(SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_HIDEWINDOW);
    position->flags |= SWP_SHOWWINDOW;
  }
  if (message == WM_GETMINMAXINFO) {
    auto* limits = reinterpret_cast<MINMAXINFO*>(lparam);
    limits->ptMinTrackSize = {monitor_.right - monitor_.left, monitor_.bottom - monitor_.top};
    limits->ptMaxTrackSize = limits->ptMinTrackSize;
    return 0;
  }
  if (message == WM_SIZE && wparam == SIZE_MINIMIZED && !positioning_) {
    positioning_ = true;
    ShowWindow(window_, SW_RESTORE);
    positioning_ = false;
    CoverMonitor();
  }
  return std::nullopt;
}
