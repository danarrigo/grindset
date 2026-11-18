#include "activity_probe.h"
#include "windows_apps.h"

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
#include <thread>

using MediaManager = winrt::Windows::Media::Control::GlobalSystemMediaTransportControlsSessionManager;
using PlaybackStatus = winrt::Windows::Media::Control::GlobalSystemMediaTransportControlsSessionPlaybackStatus;

struct ActivityProbeState {
  std::mutex mutex;
  MediaManager manager{nullptr};
  bool alive = true;
  std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> catalog_result;
  std::optional<flutter::EncodableList> catalog_apps;
  // Finished icon lookups, answered on the UI thread.
  std::vector<std::pair<std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>, flutter::EncodableMap>> details;
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
constexpr UINT kForegroundChanged = WM_APP + 173;
constexpr UINT kCatalogReady = WM_APP + 174;
constexpr UINT kDetailsReady = WM_APP + 175;
// OUTOFCONTEXT callbacks are delivered on the registering UI thread. The runner
// owns exactly one Flutter window per process; no other-app titles are queried.
HWND foreground_notification_window = nullptr;
void CALLBACK ForegroundChanged(HWINEVENTHOOK, DWORD, HWND, LONG, LONG, DWORD, DWORD) {
  if (foreground_notification_window) PostMessageW(foreground_notification_window, kForegroundChanged, 0, 0);
}
}  // namespace

ActivityProbe::ActivityProbe(flutter::BinaryMessenger* messenger, HWND window)
    : window_(window), restriction_(window), state_(std::make_shared<ActivityProbeState>()),
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
  channel_->SetMethodCallHandler([this, state](const auto& call, auto result) {
    const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
    if (call.method_name() == "listWindowsApps") {
      {
        const std::lock_guard<std::mutex> guard(state->mutex);
        if (state->catalog_result) { result->Error("APP_SCAN_BUSY", "An app scan is already running."); return; }
        state->catalog_result = std::move(result);
      }
      const HWND host = window_;
      std::thread([state, host]() {
        std::optional<flutter::EncodableList> apps;
        try { apps = ListWindowsApps(); } catch (...) { /* Report on the UI thread. */ }
        const std::lock_guard<std::mutex> guard(state->mutex);
        if (!state->alive) return;
        state->catalog_apps = std::move(apps);
        PostMessageW(host, kCatalogReady, 0, 0);
      }).detach();
      return;
    }
    if (call.method_name() == "appDetails") {
      const auto it = args ? args->find(flutter::EncodableValue("executables")) : flutter::EncodableMap::const_iterator{};
      const auto* list = args && it != args->end() ? std::get_if<flutter::EncodableList>(&it->second) : nullptr;
      if (!list || list->size() > 32) { result->Error("INVALID_APPS", "Up to 32 executable names are required."); return; }
      std::vector<std::string> executables;
      for (const auto& value : *list) {
        if (const auto* name = std::get_if<std::string>(&value)) executables.push_back(*name);
      }
      const HWND host = window_;
      std::thread([state, host, executables, response = std::move(result)]() mutable {
        flutter::EncodableMap details;
        try { details = WindowsAppDetails(executables); } catch (...) { /* Unknown apps keep letter icons. */ }
        const std::lock_guard<std::mutex> guard(state->mutex);
        if (!state->alive) return;
        state->details.emplace_back(std::move(response), std::move(details));
        PostMessageW(host, kDetailsReady, 0, 0);
      }).detach();
      return;
    }
    if (call.method_name() == "describeWindowsApp") {
      if (!args) { result->Error("INVALID_APP", "Choose an executable."); return; }
      const auto it = args->find(flutter::EncodableValue("path"));
      const auto* path = it == args->end() ? nullptr : std::get_if<std::string>(&it->second);
      if (!path) { result->Error("INVALID_APP", "Choose an executable."); return; }
      result->Success(DescribeWindowsApp(*path));
      return;
    }
    if (call.method_name() == "setForegroundWatch") {
      const auto it = args ? args->find(flutter::EncodableValue("enabled")) : flutter::EncodableMap::const_iterator{};
      const auto* enabled = args && it != args->end() ? std::get_if<bool>(&it->second) : nullptr;
      if (!enabled) { result->Error("INVALID_WATCH", "An enabled flag is required."); return; }
      result->Success(flutter::EncodableValue(SetForegroundWatch(*enabled)));
      return;
    }
    if (call.method_name() == "dismissRestriction") {
      restriction_.Dismiss();
      result->Success();
      return;
    }
    if (call.method_name() == "presentRestriction" || call.method_name() == "restoreRestrictedApp") {
      if (!args) { result->Error("INVALID_APP", "A selected app is required."); return; }
      const auto source_it = args->find(flutter::EncodableValue("source"));
      const auto* source = source_it == args->end() ? nullptr : std::get_if<std::string>(&source_it->second);
      if (!source) { result->Error("INVALID_APP", "An app source is required."); return; }
      if (call.method_name() == "restoreRestrictedApp") {
        result->Success(flutter::EncodableValue(restriction_.RestoreTarget(*source)));
        return;
      }
      const auto pid_it = args->find(flutter::EncodableValue("pid"));
      DWORD pid = 0;
      if (pid_it != args->end()) {
        if (const auto* value = std::get_if<int32_t>(&pid_it->second)) pid = static_cast<DWORD>(*value);
        if (const auto* value = std::get_if<int64_t>(&pid_it->second)) pid = static_cast<DWORD>(*value);
      }
      const auto status = restriction_.Present(pid, *source);
      if (status == "refused") { result->Error("RESTRICTION_REFUSED", "Windows could not minimize the selected app. It has not been locked."); return; }
      result->Success(flutter::EncodableValue(status));
      return;
    }
    if (call.method_name() != "activityState") { result->NotImplemented(); return; }
    const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
    if (!arguments) { result->Error("INVALID_PID", "A foreground process is required."); return; }
    const auto it = arguments->find(flutter::EncodableValue("pid"));
    DWORD pid = 0;
    if (it != arguments->end()) {
      if (const auto* pid32 = std::get_if<int32_t>(&it->second)) pid = static_cast<DWORD>(*pid32);
      if (const auto* pid64 = std::get_if<int64_t>(&it->second)) pid = static_cast<DWORD>(*pid64);
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

bool ActivityProbe::SetForegroundWatch(bool enabled) {
  if (!enabled) {
    if (foreground_hook_) UnhookWinEvent(foreground_hook_);
    foreground_hook_ = nullptr;
    foreground_notification_window = nullptr;
    return true;
  }
  if (foreground_hook_) return true;
  foreground_notification_window = window_;
  foreground_hook_ = SetWinEventHook(EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND,
      nullptr, ForegroundChanged, 0, 0, WINEVENT_OUTOFCONTEXT);
  if (!foreground_hook_) foreground_notification_window = nullptr;
  return foreground_hook_ != nullptr;
}

std::optional<LRESULT> ActivityProbe::HandleMessage(UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == kCatalogReady) {
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> response;
    std::optional<flutter::EncodableList> apps;
    {
      const std::lock_guard<std::mutex> guard(state_->mutex);
      response = std::move(state_->catalog_result);
      apps = std::move(state_->catalog_apps);
    }
    if (response) {
      if (apps) response->Success(flutter::EncodableValue(*apps));
      else response->Error("APP_SCAN_FAILED", "Could not read Windows applications. Try again or browse for an executable.");
    }
    return 0;
  }
  if (message == kDetailsReady) {
    decltype(state_->details) ready;
    {
      const std::lock_guard<std::mutex> guard(state_->mutex);
      ready.swap(state_->details);
    }
    for (auto& [response, details] : ready) response->Success(flutter::EncodableValue(std::move(details)));
    return 0;
  }
  if (message == kForegroundChanged) {
    if (foreground_hook_) channel_->InvokeMethod("foregroundChanged", nullptr);
    return 0;
  }
  return restriction_.HandleMessage(message, wparam, lparam);
}

ActivityProbe::~ActivityProbe() {
  {
    const std::lock_guard<std::mutex> guard(state_->mutex);
    state_->alive = false;
    state_->catalog_result.reset();
    state_->details.clear();
  }
  SetForegroundWatch(false);
  channel_->SetMethodCallHandler(nullptr);
}
