#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <string>

#include "flutter_window.h"
#include "utils.h"

// Check if any of the GPU-disable flags are present on the command line.
// Usage: PlayTorrio.exe --disable-gpu
//    or: PlayTorrio.exe --software-render
static bool ShouldDisableGpu() {
  int argc = 0;
  LPWSTR *argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (!argv) return false;

  bool disable = false;
  for (int i = 1; i < argc; ++i) {
    std::wstring arg(argv[i]);
    if (arg == L"--disable-gpu" || arg == L"--software-render") {
      disable = true;
      break;
    }
  }
  ::LocalFree(argv);
  return disable;
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // ── GPU fallback ──────────────────────────────────────────────────────
  // On some machines (Intel integrated GPUs, old NVIDIA drivers) the Skia
  // GPU backend produces "GrBackendTextureImageGenerator: Trying to use
  // texture on two GrContexts!" errors that cause lag and crashes.
  // Launching with --disable-gpu forces the Flutter engine to use software
  // rendering, which is slower but stable everywhere.
  if (ShouldDisableGpu()) {
    // FLUTTER_ENGINE_SWITCHES is read by the Flutter engine at startup.
    // Count = number of switches, then each switch as FLUTTER_ENGINE_SWITCH_N.
    ::SetEnvironmentVariableW(L"FLUTTER_ENGINE_SWITCHES", L"1");
    ::SetEnvironmentVariableW(L"FLUTTER_ENGINE_SWITCH_1",
                              L"--disable-gpu");
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"NETMAX", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
