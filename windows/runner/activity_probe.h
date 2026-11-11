#ifndef RUNNER_ACTIVITY_PROBE_H_
#define RUNNER_ACTIVITY_PROBE_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <memory>

struct ActivityProbeState;

// Only process identity, idle time and playback state. No window/media titles.
class ActivityProbe {
 public:
  explicit ActivityProbe(flutter::BinaryMessenger* messenger);
  ~ActivityProbe();

 private:
  std::shared_ptr<ActivityProbeState> state_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif
