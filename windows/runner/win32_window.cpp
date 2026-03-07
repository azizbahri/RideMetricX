#include "win32_window.h"

#include <dwmapi.h>
#include <flutter_windows.h>

#include "resource.h"

namespace {

/// Window attribute that enables dark mode window decorations.
///
/// Redefined in case the developer's machine has a Windows SDK older than
/// version 10.0.22000.0.
/// See: https://docs.microsoft.com/en-us/windows/win32/api/dwmapi/ne-dwmapi-dwmwindowattribute
constexpr const DWMWINDOWATTRIBUTE DWMWA_USE_IMMERSIVE_DARK_MODE = static_cast<DWMWINDOWATTRIBUTE>(20);

using EnableNonClientDpiScalingPtr = BOOL __stdcall (*)(HWND hwnd);
using GetDpiForMonitorPtr = HRESULT __stdcall (*)(HMONITOR monitor,
                                                  MONITOR_DPI_TYPE dpi_type,
                                                  UINT* dpi_x, UINT* dpi_y);

constexpr const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

/// Registry key for app theme preference.
///
/// A value of 0 indicates apps should use dark mode. A non-zero or missing
/// value indicates apps should use light mode.
constexpr const wchar_t kGetPreferredBrightnessRegKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize";
constexpr const wchar_t kGetPreferredBrightnessRegValue[] = L"AppsUseLightTheme";

// The number of Win32Window objects that currently exist.
static int g_active_window_count = 0;

using Win32Message = std::function<LRESULT(HWND, UINT, WPARAM, LPARAM)>;

int32_t GetDpiForHWND(HWND hwnd) {
  HMODULE user32_module = LoadLibraryA("User32.dll");
  if (!user32_module) {
    return FALSE;
  }
  auto get_dpi_for_window =
      reinterpret_cast<UINT __stdcall (*)(HWND)>(
          GetProcAddress(user32_module, "GetDpiForWindow"));
  if (get_dpi_for_window == nullptr) {
    return FALSE;
  }
  UINT dpi = get_dpi_for_window(hwnd);
  FreeLibrary(user32_module);
  return dpi;
}

LRESULT CALLBACK WndProc(HWND const window, UINT const message,
                          WPARAM const wparam,
                          LPARAM const lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto window_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(window_struct->lpCreateParams));

    auto that = static_cast<Win32Window*>(window_struct->lpCreateParams);
    EnableNonClientDpiScalingPtr enable_non_client_dpi_scaling = nullptr;
    HMODULE user32_module = LoadLibraryA("User32.dll");
    if (user32_module) {
      enable_non_client_dpi_scaling =
          reinterpret_cast<EnableNonClientDpiScalingPtr>(
              GetProcAddress(user32_module, "EnableNonClientDpiScaling"));
      FreeLibrary(user32_module);
    }
    if (enable_non_client_dpi_scaling != nullptr) {
      enable_non_client_dpi_scaling(window);
      that->UpdateAndApplyDpiScale(GetDpiForHWND(window));
    }
    return TRUE;
  } else if (Win32Window* that = GetThisFromHandle(window)) {
    return that->MessageHandler(window, message, wparam, lparam);
  }

  return DefWindowProc(window, message, wparam, lparam);
}

static Win32Window* GetThisFromHandle(HWND const window) noexcept {
  return reinterpret_cast<Win32Window*>(
      GetWindowLongPtr(window, GWLP_USERDATA));
}

}  // namespace

// static
Win32Window::Win32Window() {
  ++g_active_window_count;
}

Win32Window::~Win32Window() {
  --g_active_window_count;
  Destroy();
}

bool Win32Window::Create(const std::wstring& title,
                         const Point& origin,
                         const Size& size) {
  Destroy();
  const wchar_t* window_class =
      RegisterWindowClass(title, WndProc);

  auto* result = CreateWindow(
      window_class, title.c_str(), WS_OVERLAPPEDWINDOW | WS_VISIBLE,
      Scale(origin.x, scale_factor_), Scale(origin.y, scale_factor_),
      Scale(size.width, scale_factor_), Scale(size.height, scale_factor_),
      nullptr, nullptr, GetModuleHandle(nullptr), this);

  if (result == nullptr) {
    UnregisterClass(window_class, nullptr);
    return false;
  }

  return OnCreate();
}

bool Win32Window::Show() {
  return ShowWindow(window_handle_, SW_SHOWNORMAL);
}

// static
const wchar_t* Win32Window::RegisterWindowClass(const std::wstring& title,
                                                 WNDPROC wnd_proc) {
  WNDCLASS window_class{};
  window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
  window_class.lpszClassName = kWindowClassName;
  window_class.style = CS_HREDRAW | CS_VREDRAW;
  window_class.cbClsExtra = 0;
  window_class.cbWndExtra = 0;
  window_class.hInstance = GetModuleHandle(nullptr);
  window_class.hIcon =
      LoadIcon(window_class.hInstance, MAKEINTRESOURCE(IDI_APP_ICON));
  window_class.hbrBackground = 0;
  window_class.lpszMenuName = nullptr;
  window_class.lpfnWndProc = wnd_proc;
  RegisterClass(&window_class);
  return kWindowClassName;
}

LRESULT
Win32Window::MessageHandler(HWND hwnd, UINT const message,
                             WPARAM const wparam,
                             LPARAM const lparam) noexcept {
  switch (message) {
    case WM_DESTROY:
      window_handle_ = nullptr;
      Destroy();
      if (quit_on_close_) {
        PostQuitMessage(0);
      }
      return 0;

    case WM_DPICHANGED: {
      auto newRectSize = reinterpret_cast<RECT*>(lparam);
      LONG newWidth = newRectSize->right - newRectSize->left;
      LONG newHeight = newRectSize->bottom - newRectSize->top;

      SetWindowPos(hwnd, nullptr, newRectSize->left, newRectSize->top, newWidth,
                   newHeight, SWP_NOZORDER | SWP_NOACTIVATE);

      return 0;
    }
    case WM_SIZE: {
      RECT rect = GetClientArea();
      if (child_content_ != nullptr) {
        // Size and position the child window.
        MoveWindow(child_content_, rect.left, rect.top, rect.right - rect.left,
                   rect.bottom - rect.top, TRUE);
      }
      return 0;
    }

    case WM_ACTIVATE:
      if (child_content_ != nullptr) {
        SetFocus(child_content_);
      }
      return 0;

    case WM_DWMCOLORIZATIONCOLORCHANGED:
      UpdateTheme(hwnd);
      return 0;
  }
  return DefWindowProc(window_handle_, message, wparam, lparam);
}

void Win32Window::Destroy() {
  OnDestroy();

  if (window_handle_) {
    DestroyWindow(window_handle_);
    window_handle_ = nullptr;
  }
  if (g_active_window_count == 0) {
    UnregisterClass(kWindowClassName, nullptr);
  }
}

void Win32Window::SetChildContent(HWND content) {
  child_content_ = content;
  SetParent(content, window_handle_);
  RECT frame = GetClientArea();

  MoveWindow(content, frame.left, frame.top, frame.right - frame.left,
             frame.bottom - frame.top, true);

  SetFocus(child_content_);
}

RECT Win32Window::GetClientArea() {
  RECT frame;
  GetClientRect(window_handle_, &frame);
  return frame;
}

HWND Win32Window::GetHandle() {
  return window_handle_;
}

void Win32Window::SetQuitOnClose(bool quit_on_close) {
  quit_on_close_ = quit_on_close;
}

bool Win32Window::OnCreate() {
  // No-op; provided for subclasses.
  return true;
}

void Win32Window::OnDestroy() {
  // No-op; provided for subclasses.
}

void Win32Window::UpdateAndApplyDpiScale(double dpi_scale) {
  scale_factor_ = dpi_scale;
}

void Win32Window::UpdateTheme(HWND const window) {
  DWORD light_mode;
  DWORD light_mode_size = sizeof(light_mode);
  LSTATUS result = RegGetValue(HKEY_CURRENT_USER, kGetPreferredBrightnessRegKey,
                               kGetPreferredBrightnessRegValue,
                               RRF_RT_REG_DWORD, nullptr, &light_mode,
                               &light_mode_size);

  if (result == ERROR_SUCCESS) {
    BOOL enable_dark_mode = light_mode == 0;
    DwmSetWindowAttribute(window, DWMWA_USE_IMMERSIVE_DARK_MODE,
                          &enable_dark_mode, sizeof(enable_dark_mode));
  }
}
