#include "windows_apps.h"
#include <windows.h>
#include <shellapi.h>
#include <tlhelp32.h>
#include <wincodec.h>
#include <winver.h>
#include <wrl/client.h>
#include <algorithm>
#include <cwctype>
#include <map>
#include <optional>
#include <iterator>
#include <vector>

namespace {
std::wstring Lower(std::wstring value) {
  std::transform(value.begin(), value.end(), value.begin(), [](wchar_t c) { return static_cast<wchar_t>(std::towlower(c)); });
  return value;
}
std::string Utf8(const std::wstring& value) {
  const int size = WideCharToMultiByte(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), nullptr, 0, nullptr, nullptr);
  std::string text(size, '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), text.data(), size, nullptr, nullptr);
  return text;
}
std::wstring Wide(const std::string& value) {
  const int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(), static_cast<int>(value.size()), nullptr, 0);
  if (size <= 0) return {};
  std::wstring text(size, L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(), static_cast<int>(value.size()), text.data(), size);
  return text;
}
struct App { std::wstring executable, name; bool running; };
using Apps = std::map<std::wstring, App>;
std::optional<App> ReadApp(const std::wstring& path, bool running) {
  // Never probe UNC paths or mapped network drives for file metadata.
  if (path.size() < 4 || path[1] != L':' || path[2] != L'\\') return std::nullopt;
  const auto drive = path.substr(0, 3);
  if (GetDriveTypeW(drive.c_str()) != DRIVE_FIXED && GetDriveTypeW(drive.c_str()) != DRIVE_REMOVABLE) return std::nullopt;
  const auto file = path.substr(path.find_last_of(L"\\/") + 1);
  const auto executable = Lower(file);
  if (executable.size() < 5 || executable.substr(executable.size() - 4) != L".exe" || IsProtectedWindowsApp(executable)) return std::nullopt;
  const auto attributes = GetFileAttributesW(path.c_str());
  if (attributes == INVALID_FILE_ATTRIBUTES || (attributes & FILE_ATTRIBUTE_DIRECTORY)) return std::nullopt;
  std::wstring name = file.substr(0, file.size() - 4);
  DWORD ignored = 0;
  const DWORD size = GetFileVersionInfoSizeW(path.c_str(), &ignored);
  if (size > 0 && size <= 1024 * 1024) {
    std::vector<BYTE> version(size);
    if (GetFileVersionInfoW(path.c_str(), 0, size, version.data())) {
      struct Translation { WORD language, codepage; };
      Translation* languages = nullptr; UINT bytes = 0;
      if (VerQueryValueW(version.data(), L"\\VarFileInfo\\Translation", reinterpret_cast<void**>(&languages), &bytes) && bytes >= sizeof(Translation)) {
        wchar_t key[96];
        swprintf_s(key, L"\\StringFileInfo\\%04x%04x\\FileDescription", static_cast<unsigned>(languages[0].language), static_cast<unsigned>(languages[0].codepage));
        wchar_t* description = nullptr; UINT chars = 0;
        if (VerQueryValueW(version.data(), key, reinterpret_cast<void**>(&description), &chars) && chars > 1 && chars <= 512) {
          name.assign(description, chars - 1);
        }
      }
    }
  }
  if (name.find_first_not_of(L" \t\r\n") == std::wstring::npos) name = file.substr(0, file.size() - 4);
  return App{executable, name, running};
}
void Add(Apps& apps, const std::wstring& path, bool running) {
  if (apps.size() >= 512) return;
  const auto app = ReadApp(path, running);
  if (!app) return;
  const auto found = apps.find(app->executable);
  if (found == apps.end()) apps.emplace(app->executable, *app);
  else found->second.running = found->second.running || running;
}
BOOL CALLBACK RunningWindow(HWND window, LPARAM data) {
  auto& apps = *reinterpret_cast<Apps*>(data);
  if (apps.size() >= 512) return FALSE;
  if (!IsWindowVisible(window) || GetWindow(window, GW_OWNER)) return TRUE;
  DWORD pid = 0; GetWindowThreadProcessId(window, &pid);
  if (pid == GetCurrentProcessId()) return TRUE;
  const HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (!process) return TRUE;
  std::vector<wchar_t> path(32768); DWORD size = static_cast<DWORD>(path.size());
  if (QueryFullProcessImageNameW(process, 0, path.data(), &size)) Add(apps, std::wstring(path.data(), size), true);
  CloseHandle(process);
  return TRUE;
}
void Registered(Apps& apps, HKEY hive, REGSAM view) {
  HKEY root = nullptr;
  if (RegOpenKeyExW(hive, L"Software\\Microsoft\\Windows\\CurrentVersion\\App Paths", 0, KEY_READ | view, &root) != ERROR_SUCCESS) return;
  for (DWORD i = 0; i < 1024 && apps.size() < 512; ++i) {
    wchar_t key[512]; DWORD length = 512;
    const auto status = RegEnumKeyExW(root, i, key, &length, nullptr, nullptr, nullptr, nullptr);
    if (status == ERROR_NO_MORE_ITEMS) break;
    if (status != ERROR_SUCCESS) continue;
    wchar_t raw[32768]; DWORD bytes = static_cast<DWORD>(sizeof(raw));
    if (RegGetValueW(root, key, nullptr, RRF_RT_REG_SZ | RRF_RT_REG_EXPAND_SZ | RRF_NOEXPAND, nullptr, raw, &bytes) != ERROR_SUCCESS) continue;
    wchar_t expanded[32768];
    const DWORD count = ExpandEnvironmentStringsW(raw, expanded, 32768);
    if (count == 0 || count > 32768) continue;
    std::wstring path(expanded);
    if (path.size() > 1 && path.front() == L'"' && path.back() == L'"') path = path.substr(1, path.size() - 2);
    Add(apps, path, false);
  }
  RegCloseKey(root);
}
flutter::EncodableValue Encode(const App& app) {
  return flutter::EncodableMap{
    {flutter::EncodableValue("source"), flutter::EncodableValue("windows:" + Utf8(app.executable))},
    {flutter::EncodableValue("name"), flutter::EncodableValue(Utf8(app.name))},
    {flutter::EncodableValue("running"), flutter::EncodableValue(app.running)},
  };
}
// Where a running or App Paths-registered executable lives. Never searches
// the disk; apps found neither way simply keep their letter icon.
std::optional<std::wstring> LocateExecutable(const std::wstring& executable) {
  const HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snapshot != INVALID_HANDLE_VALUE) {
    PROCESSENTRY32W entry{sizeof(entry)};
    for (BOOL more = Process32FirstW(snapshot, &entry); more; more = Process32NextW(snapshot, &entry)) {
      if (CompareStringOrdinal(entry.szExeFile, -1, executable.c_str(), -1, TRUE) != CSTR_EQUAL) continue;
      const HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, entry.th32ProcessID);
      if (!process) continue;
      std::vector<wchar_t> path(32768); DWORD size = static_cast<DWORD>(path.size());
      const bool found = QueryFullProcessImageNameW(process, 0, path.data(), &size) != FALSE;
      CloseHandle(process);
      if (found) { CloseHandle(snapshot); return std::wstring(path.data(), size); }
    }
    CloseHandle(snapshot);
  }
  const auto key = L"Software\\Microsoft\\Windows\\CurrentVersion\\App Paths\\" + executable;
  for (const HKEY hive : {HKEY_CURRENT_USER, HKEY_LOCAL_MACHINE}) {
    for (const DWORD view : {static_cast<DWORD>(RRF_SUBKEY_WOW6464KEY), static_cast<DWORD>(RRF_SUBKEY_WOW6432KEY)}) {
      std::vector<wchar_t> raw(32768); DWORD bytes = static_cast<DWORD>(raw.size() * sizeof(wchar_t));
      if (RegGetValueW(hive, key.c_str(), nullptr, RRF_RT_REG_SZ | RRF_RT_REG_EXPAND_SZ | view, nullptr, raw.data(), &bytes) != ERROR_SUCCESS) continue;
      std::wstring path(raw.data());
      if (path.size() > 1 && path.front() == L'"' && path.back() == L'"') path = path.substr(1, path.size() - 2);
      if (!path.empty()) return path;
    }
  }
  return std::nullopt;
}
// The executable's own icon as a 64 px PNG.
std::optional<std::vector<uint8_t>> IconPng(const std::wstring& path) {
  using Microsoft::WRL::ComPtr;
  HICON icon = nullptr;
  if (FAILED(SHDefExtractIconW(path.c_str(), 0, 0, &icon, nullptr, 64)) || !icon) return std::nullopt;
  ComPtr<IWICImagingFactory> factory;
  ComPtr<IWICBitmap> bitmap;
  const bool converted =
      SUCCEEDED(CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&factory))) &&
      SUCCEEDED(factory->CreateBitmapFromHICON(icon, &bitmap));
  DestroyIcon(icon);
  if (!converted) return std::nullopt;
  ComPtr<IStream> stream;
  ComPtr<IWICBitmapEncoder> encoder;
  ComPtr<IWICBitmapFrameEncode> frame;
  UINT width = 0, height = 0;
  WICPixelFormatGUID format = GUID_WICPixelFormat32bppBGRA;
  if (FAILED(CreateStreamOnHGlobal(nullptr, TRUE, &stream)) ||
      FAILED(factory->CreateEncoder(GUID_ContainerFormatPng, nullptr, &encoder)) ||
      FAILED(encoder->Initialize(stream.Get(), WICBitmapEncoderNoCache)) ||
      FAILED(encoder->CreateNewFrame(&frame, nullptr)) ||
      FAILED(frame->Initialize(nullptr)) ||
      FAILED(bitmap->GetSize(&width, &height)) ||
      FAILED(frame->SetSize(width, height)) ||
      FAILED(frame->SetPixelFormat(&format)) ||
      FAILED(frame->WriteSource(bitmap.Get(), nullptr)) ||
      FAILED(frame->Commit()) ||
      FAILED(encoder->Commit())) return std::nullopt;
  STATSTG stat{};
  HGLOBAL memory = nullptr;
  if (FAILED(stream->Stat(&stat, STATFLAG_NONAME)) || FAILED(GetHGlobalFromStream(stream.Get(), &memory))) return std::nullopt;
  const auto size = static_cast<size_t>(stat.cbSize.QuadPart);
  const auto* data = static_cast<const uint8_t*>(GlobalLock(memory));
  if (!data) return std::nullopt;
  std::vector<uint8_t> png(data, data + size);
  GlobalUnlock(memory);
  return png;
}
}  // namespace

bool IsProtectedWindowsApp(const std::wstring& executable) {
  static const wchar_t* names[] = {
    L"lockin.exe", L"explorer.exe", L"taskmgr.exe", L"dwm.exe", L"csrss.exe",
    L"winlogon.exe", L"logonui.exe", L"lockapp.exe", L"credentialuibroker.exe",
    L"consent.exe", L"systemsettings.exe", L"applicationframehost.exe",
    L"startmenuexperiencehost.exe", L"shellexperiencehost.exe", L"searchhost.exe",
  };
  return std::any_of(std::begin(names), std::end(names), [&](const auto* name) {
    return CompareStringOrdinal(executable.c_str(), -1, name, -1, TRUE) == CSTR_EQUAL;
  });
}
flutter::EncodableList ListWindowsApps() {
  Apps apps;
  EnumWindows(RunningWindow, reinterpret_cast<LPARAM>(&apps));
  for (const HKEY hive : {HKEY_CURRENT_USER, HKEY_LOCAL_MACHINE}) {
    Registered(apps, hive, KEY_WOW64_64KEY);
    Registered(apps, hive, KEY_WOW64_32KEY);
  }
  flutter::EncodableList result;
  for (const auto& entry : apps) result.push_back(Encode(entry.second));
  return result;
}
flutter::EncodableValue DescribeWindowsApp(const std::string& path) {
  const auto app = ReadApp(Wide(path), false);
  return app ? Encode(*app) : flutter::EncodableValue();
}
flutter::EncodableMap WindowsAppDetails(const std::vector<std::string>& executables) {
  const HRESULT com = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  flutter::EncodableMap details;
  for (const auto& name : executables) {
    const auto executable = Lower(Wide(name));
    if (executable.size() < 5 || executable.size() > 260 || executable.substr(executable.size() - 4) != L".exe" ||
        executable.find_first_of(L"\\/:") != std::wstring::npos) continue;
    const auto path = LocateExecutable(executable);
    if (!path) continue;
    const auto app = ReadApp(*path, false);
    if (!app || app->executable != executable) continue;
    const auto icon = IconPng(*path);
    if (!icon) continue;
    details.emplace(flutter::EncodableValue(Utf8(executable)), flutter::EncodableMap{
      {flutter::EncodableValue("label"), flutter::EncodableValue(Utf8(app->name))},
      {flutter::EncodableValue("icon"), flutter::EncodableValue(*icon)},
    });
  }
  if (SUCCEEDED(com)) CoUninitialize();
  return details;
}
