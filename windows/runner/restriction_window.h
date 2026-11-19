#ifndef RUNNER_RESTRICTION_WINDOW_H_
#define RUNNER_RESTRICTION_WINDOW_H_

#include <windows.h>
#include <optional>
#include <string>

// Owns only Grindset's presentation and a verified foreground app's minimize
// action. No process termination, keyboard hooks or global Windows policy.
class RestrictionWindow {
 public:
  explicit RestrictionWindow(HWND window) : window_(window) {}
  ~RestrictionWindow();
  std::string Present(DWORD pid, const std::string& source);
  void Dismiss();
  std::optional<LRESULT> HandleMessage(UINT message, WPARAM wparam, LPARAM lparam);

 private:
  void CoverMonitor();
  HWND window_;
  HWND target_ = nullptr;
  bool active_ = false;
  bool positioning_ = false;
  bool was_visible_ = false;
  bool was_minimized_ = false;
  LONG_PTR style_ = 0;
  LONG_PTR ex_style_ = 0;
  WINDOWPLACEMENT placement_{sizeof(WINDOWPLACEMENT)};
  RECT bounds_{};
  RECT monitor_{};
};
#endif
