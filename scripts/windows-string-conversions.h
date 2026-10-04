#pragma once

#include <windows.h>
#include <stdexcept>
#include <string>

// Match ATL's default ANSI code page conversions using built-in Win32 APIs.
inline std::wstring WidenWindowsString(const char* text) {
  const int length = MultiByteToWideChar(CP_ACP, 0, text, -1, nullptr, 0);
  if (length == 0) throw std::runtime_error("Windows string conversion failed");
  std::wstring result(length, L'\0');
  if (MultiByteToWideChar(CP_ACP, 0, text, -1, result.data(), length) == 0)
    throw std::runtime_error("Windows string conversion failed");
  result.resize(length - 1);
  return result;
}

inline std::string NarrowWindowsString(const wchar_t* text) {
  const int length = WideCharToMultiByte(CP_ACP, 0, text, -1, nullptr, 0, nullptr, nullptr);
  if (length == 0) throw std::runtime_error("Windows string conversion failed");
  std::string result(length, '\0');
  if (WideCharToMultiByte(CP_ACP, 0, text, -1, result.data(), length, nullptr, nullptr) == 0)
    throw std::runtime_error("Windows string conversion failed");
  result.resize(length - 1);
  return result;
}
