#include "activity_probe.h"

#include <windows.h>
#include <appmodel.h>
#include <audiopolicy.h>
#include <mmdeviceapi.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Media.Control.h>
#include <flutter/standard_method_codec.h>
#include <algorithm>
#include <cwctype>
#include <iterator>
#include <mutex>
#include <string>
#include <vector>

using MediaManager = winrt::Windows::Media::Control::GlobalSystemMediaTransportControlsSessionManager;
using PlaybackStatus = winrt::Windows::Media::Control::GlobalSystemMediaTransportControlsSessionPlaybackStatus;

struct ActivityProbeState {
  std::mutex mutex;
  MediaManager manager{nullptr};
};

namespace {
std::wstring Lower(std::wstring text) {
  std::transform(text.begin(), text.end(), text.begin(), [](wchar_t c) {
    return static_cast<wchar_t>(std::towlower(c));
  });
  return text;
}

bool HasActiveAudio(DWORD pid) {
  winrt::com_ptr<IMMDeviceEnumerator> devices;
  if (FAILED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
                              __uuidof(IMMDeviceEnumerator), devices.put_void()))) return false;
  winrt::com_ptr<IMMDeviceCollection> endpoints;
  if (FAILED(devices->EnumAudioEndpoints(eRender, DEVICE_STATE_ACTIVE, endpoints.put()))) return false;
  UINT count = 0;
  endpoints->GetCount(&count);
  for (UINT i = 0; i < count; ++i) {
    winrt::com_ptr<IMMDevice> endpoint;
    winrt::com_ptr<IAudioSessionManager2> manager;
    winrt::com_ptr<IAudioSessionEnumerator> sessions;
    if (FAILED(endpoints->Item(i, endpoint.put())) ||
        FAILED(endpoint->Activate(__uuidof(IAudioSessionManager2), CLSCTX_ALL, nullptr, manager.put_void())) ||
        FAILED(manager->GetSessionEnumerator(sessions.put()))) continue;
    int session_count = 0;
    sessions->GetCount(&session_count);
    for (int n = 0; n < session_count; ++n) {
      winrt::com_ptr<IAudioSessionControl> session;
      if (FAILED(sessions->GetSession(n, session.put()))) continue;
      auto detail = session.try_as<IAudioSessionControl2>();
      if (!detail) continue;
      DWORD owner = 0;
      AudioSessionState status = AudioSessionStateInactive;
      if (detail->GetProcessId(&owner) == S_OK && owner == pid &&
          SUCCEEDED(session->GetState(&status)) && status == AudioSessionStateActive) return true;
    }
  }
  return false;
}

bool IsPlaying(const MediaManager& manager, DWORD pid) {
  HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (!process) return false;
  std::wstring app_id;
  UINT length = 0;
  if (GetApplicationUserModelId(process, &length, nullptr) == ERROR_INSUFFICIENT_BUFFER && length < 4096) {
    std::vector<wchar_t> buffer(length);
    if (GetApplicationUserModelId(process, &length, buffer.data()) == ERROR_SUCCESS) app_id = Lower(buffer.data());
  }
  wchar_t image[32768];
  DWORD image_size = static_cast<DWORD>(std::size(image));
  std::wstring executable;
  if (QueryFullProcessImageNameW(process, 0, image, &image_size)) {
    executable = Lower(std::wstring(image, image_size));
    executable = executable.substr(executable.find_last_of(L"\\/") + 1);
  }
  CloseHandle(process);
  const auto stem = executable.substr(0, executable.rfind(L'.'));
  // Do not query media properties, titles, artist names or artwork.
  for (const auto& session : manager.GetSessions()) {
    const auto owner = Lower(session.SourceAppUserModelId().c_str());
    if ((!app_id.empty() && owner == app_id) || owner == executable || owner == stem) {
      if (session.GetPlaybackInfo().PlaybackStatus() == PlaybackStatus::Playing) return true;
    }
  }
  return false;
}
}  // namespace

ActivityProbe::ActivityProbe(flutter::BinaryMessenger* messenger)
    : state_(std::make_shared<ActivityProbeState>()),
      channel_(std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "app.lockin/windows", &flutter::StandardMethodCodec::GetInstance())) {
  const auto state = state_;
  try {
    MediaManager::RequestAsync().Completed([state](const auto& request, const auto status) {
      if (status != winrt::Windows::Foundation::AsyncStatus::Completed) return;
      try {
        const auto manager = request.GetResults();
        const std::lock_guard<std::mutex> guard(state->mutex);
        state->manager = manager;
      } catch (const winrt::hresult_error&) { /* Conservative idle behavior if unavailable. */ }
    });
  } catch (const winrt::hresult_error&) { /* Older Windows or denied media capability. */ }
  channel_->SetMethodCallHandler([state](const auto& call, auto result) {
    if (call.method_name() != "activityState") { result->NotImplemented(); return; }
    const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
    if (!arguments) { result->Error("INVALID_PID", "A foreground process is required."); return; }
    const auto it = arguments->find(flutter::EncodableValue("pid"));
    DWORD pid = 0;
    if (it != arguments->end()) {
      if (const auto* small = std::get_if<int32_t>(&it->second)) pid = static_cast<DWORD>(*small);
      if (const auto* large = std::get_if<int64_t>(&it->second)) pid = static_cast<DWORD>(*large);
    }
    DWORD foreground = 0;
    GetWindowThreadProcessId(GetForegroundWindow(), &foreground);
    LASTINPUTINFO input{sizeof(LASTINPUTINFO), 0};
    const bool idle_known = GetLastInputInfo(&input) != FALSE;
    const DWORD idle = static_cast<DWORD>(GetTickCount64()) - input.dwTime;
    MediaManager manager{nullptr};
    { const std::lock_guard<std::mutex> guard(state->mutex); manager = state->manager; }
    bool available = manager != nullptr;
    bool playing = HasActiveAudio(pid);
    if (manager && !playing) {
      try { playing = IsPlaying(manager, pid); }
      catch (const winrt::hresult_error&) { available = false; }
    }
    result->Success(flutter::EncodableMap{
        {flutter::EncodableValue("current"), flutter::EncodableValue(pid != 0 && pid == foreground)},
        {flutter::EncodableValue("idleMs"), flutter::EncodableValue(static_cast<int64_t>(idle))},
        {flutter::EncodableValue("idleKnown"), flutter::EncodableValue(idle_known)},
        {flutter::EncodableValue("mediaAvailable"), flutter::EncodableValue(available)},
        {flutter::EncodableValue("mediaPlaying"), flutter::EncodableValue(playing)},
    });
  });
}

ActivityProbe::~ActivityProbe() { channel_->SetMethodCallHandler(nullptr); }
