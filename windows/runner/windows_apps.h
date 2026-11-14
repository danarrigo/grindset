#ifndef RUNNER_WINDOWS_APPS_H_
#define RUNNER_WINDOWS_APPS_H_
#include <flutter/encodable_value.h>
#include <string>

bool IsProtectedWindowsApp(const std::wstring& executable);
flutter::EncodableList ListWindowsApps();
flutter::EncodableValue DescribeWindowsApp(const std::string& path);
#endif
