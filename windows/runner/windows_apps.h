#ifndef RUNNER_WINDOWS_APPS_H_
#define RUNNER_WINDOWS_APPS_H_
#include <flutter/encodable_value.h>
#include <string>
#include <vector>

bool IsProtectedWindowsApp(const std::wstring& executable);
flutter::EncodableList ListWindowsApps();
flutter::EncodableValue DescribeWindowsApp(const std::string& path);
// Label and PNG icon for each running or registered executable name. Call off
// the UI thread; it initializes COM for the calling thread.
flutter::EncodableMap WindowsAppDetails(const std::vector<std::string>& executables);
#endif
