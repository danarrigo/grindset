#ifndef RUNNER_ACTIVITY_PROBE_H_
#define RUNNER_ACTIVITY_PROBE_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <memory>
#include <windows.h>

#include "restriction_window.h"

struct ActivityProbeState;

// Only process identity, idle time and playback state. No window/media titles.
class ActivityProbe {
 public:
  ActivityProbe(flutter::BinaryMessenger* messenger, HWND window);
  ~ActivityProbe();
  std::optional<LRESULT> HandleMessage(UINT message, WPARAM wparam, LPARAM lparam);

 private:
  bool SetForegroundWatch(bool enabled);
  HWND window_;
  HWINEVENTHOOK foreground_hook_ = nullptr;
  RestrictionWindow restriction_;
  std::shared_ptr<ActivityProbeState> state_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif
