#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include "macro_relay.h"

#include <windows.h>
#include <commctrl.h>
#include <commdlg.h>
#include <shellapi.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <deque>
#include <memory>
#include <mutex>
#include <random>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

namespace {

constexpr DWORD kKeyeventfExtendedkey = 0x0001;
constexpr DWORD kKeyeventfKeyup = 0x0002;
constexpr DWORD kKeyeventfUnicode = 0x0004;

struct Step {
  int kind = 0;
  int code = 0;
  int down = 1;
  int delay_ms = 0;
  int x = 0;
  int y = 0;
  int x2 = 0;
  int y2 = 0;
  int has_pos = 0;
  std::wstring text;
};

struct Session {
  int id = 0;
  int interval_ms = 50;
  double speed = 1.0;
  bool jitter = false;
  int loop_mode = 0;
  int repeat_count = 1;
  int duration_ms = 10000;
  int focus_mode = 0;
  int input_mode = MR_INPUT_SILENT;
  std::string process;
  std::string title;
  std::vector<Step> steps;
  std::atomic<int> state{0};  // 0 stopped, 1 running, 2 paused
  std::thread worker;
  std::atomic<bool> stop{false};
  std::atomic<bool> pause{false};
};

std::mutex g_mu;
std::deque<MrEvent> g_recorded;
bool g_keep_delays = true;
bool g_recording = false;
ULONGLONG g_last_tick = 0;
bool g_first_event = true;
HHOOK g_kb = nullptr;
HHOOK g_mouse = nullptr;
DWORD g_hook_tid = 0;
std::thread g_hook_thread;
std::atomic<int> g_next_id{1};
std::unordered_map<int, std::unique_ptr<Session>> g_sessions;
std::mutex g_stuck_mu;
std::vector<WORD> g_stuck_keys;
std::vector<int> g_stuck_buttons;
int g_vk_play = VK_F6;
int g_vk_once = VK_F7;
int g_vk_record = VK_F9;
int g_vk_panic = VK_F12;
bool g_close_to_tray = false;
bool g_tray_added = false;
HWND g_tray_hwnd = nullptr;
constexpr UINT kTrayMsg = WM_APP + 77;
constexpr UINT_PTR kTraySubclass = 1;
std::atomic<int> g_last_input_status{0};  // 0 ok, 1 uipi, 2 fail
constexpr int kClickMoveDelayMs = 20;
constexpr int kClickHoldDelayMs = 40;

bool IsExtended(WORD vk) {
  switch (vk) {
    case VK_PRIOR:
    case VK_NEXT:
    case VK_END:
    case VK_HOME:
    case VK_LEFT:
    case VK_UP:
    case VK_RIGHT:
    case VK_DOWN:
    case VK_INSERT:
    case VK_DELETE:
    case VK_RCONTROL:
    case VK_RMENU:
    case VK_LWIN:
    case VK_RWIN:
    case VK_DIVIDE:
      return true;
    default:
      return false;
  }
}

void SendKey(WORD vk, bool up) {
  INPUT in{};
  in.type = INPUT_KEYBOARD;
  in.ki.wVk = vk;
  in.ki.wScan = static_cast<WORD>(MapVirtualKeyW(vk, MAPVK_VK_TO_VSC));
  in.ki.dwFlags = up ? kKeyeventfKeyup : 0;
  if (IsExtended(vk)) in.ki.dwFlags |= kKeyeventfExtendedkey;
  SendInput(1, &in, sizeof(INPUT));
}

void SendUnicode(wchar_t ch, bool up) {
  INPUT in{};
  in.type = INPUT_KEYBOARD;
  in.ki.wScan = static_cast<WORD>(ch);
  in.ki.dwFlags = kKeyeventfUnicode | (up ? kKeyeventfKeyup : 0);
  SendInput(1, &in, sizeof(INPUT));
}

void SendMouseButton(int button, bool down) {
  INPUT in{};
  in.type = INPUT_MOUSE;
  switch (button) {
    case MR_MOUSE_LEFT:
      in.mi.dwFlags = down ? MOUSEEVENTF_LEFTDOWN : MOUSEEVENTF_LEFTUP;
      break;
    case MR_MOUSE_RIGHT:
      in.mi.dwFlags = down ? MOUSEEVENTF_RIGHTDOWN : MOUSEEVENTF_RIGHTUP;
      break;
    case MR_MOUSE_MIDDLE:
      in.mi.dwFlags = down ? MOUSEEVENTF_MIDDLEDOWN : MOUSEEVENTF_MIDDLEUP;
      break;
    case MR_MOUSE_X1:
      in.mi.dwFlags = down ? MOUSEEVENTF_XDOWN : MOUSEEVENTF_XUP;
      in.mi.mouseData = XBUTTON1;
      break;
    case MR_MOUSE_X2:
      in.mi.dwFlags = down ? MOUSEEVENTF_XDOWN : MOUSEEVENTF_XUP;
      in.mi.mouseData = XBUTTON2;
      break;
    default:
      return;
  }
  SendInput(1, &in, sizeof(INPUT));
}

void MoveAbs(int x, int y) {
  const int sw = GetSystemMetrics(SM_CXVIRTUALSCREEN);
  const int sh = GetSystemMetrics(SM_CYVIRTUALSCREEN);
  const int left = GetSystemMetrics(SM_XVIRTUALSCREEN);
  const int top = GetSystemMetrics(SM_YVIRTUALSCREEN);
  INPUT in{};
  in.type = INPUT_MOUSE;
  in.mi.dx = static_cast<LONG>(std::lround(((x - left) * 65535.0) / std::max(sw - 1, 1)));
  in.mi.dy = static_cast<LONG>(std::lround(((y - top) * 65535.0) / std::max(sh - 1, 1)));
  in.mi.dwFlags = MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK;
  SendInput(1, &in, sizeof(INPUT));
}

void TrackKey(WORD vk, bool down) {
  std::lock_guard<std::mutex> lock(g_stuck_mu);
  if (down) {
    g_stuck_keys.push_back(vk);
  } else {
    g_stuck_keys.erase(std::remove(g_stuck_keys.begin(), g_stuck_keys.end(), vk), g_stuck_keys.end());
  }
}

void TrackButton(int button, bool down) {
  std::lock_guard<std::mutex> lock(g_stuck_mu);
  if (down) {
    g_stuck_buttons.push_back(button);
  } else {
    g_stuck_buttons.erase(std::remove(g_stuck_buttons.begin(), g_stuck_buttons.end(), button),
                          g_stuck_buttons.end());
  }
}

void ReleaseStuck() {
  std::vector<WORD> keys;
  std::vector<int> buttons;
  {
    std::lock_guard<std::mutex> lock(g_stuck_mu);
    keys.swap(g_stuck_keys);
    buttons.swap(g_stuck_buttons);
  }
  for (WORD vk : keys) SendKey(vk, true);
  for (int b : buttons) SendMouseButton(b, false);
}

std::wstring Utf8ToWide(const char* utf8) {
  if (!utf8 || !*utf8) return {};
  int n = MultiByteToWideChar(CP_UTF8, 0, utf8, -1, nullptr, 0);
  std::wstring w(n > 0 ? n - 1 : 0, L'\0');
  if (n > 1) MultiByteToWideChar(CP_UTF8, 0, utf8, -1, w.data(), n);
  return w;
}

std::string WideToUtf8(const std::wstring& w) {
  if (w.empty()) return {};
  int n = WideCharToMultiByte(CP_UTF8, 0, w.c_str(), -1, nullptr, 0, nullptr, nullptr);
  std::string s(n > 0 ? n - 1 : 0, '\0');
  if (n > 1) WideCharToMultiByte(CP_UTF8, 0, w.c_str(), -1, s.data(), n, nullptr, nullptr);
  return s;
}

int ConsumeDelay() {
  ULONGLONG now = GetTickCount64();
  int delay = static_cast<int>(now - g_last_tick);
  if (delay < 0) delay = 0;
  if (delay > 60000) delay = 60000;
  g_last_tick = now;
  if (g_first_event) {
    g_first_event = false;
    return 0;
  }
  return g_keep_delays ? delay : 0;
}

bool IsOwnWindowAt(POINT pt) {
  HWND hwnd = WindowFromPoint(pt);
  if (!hwnd) return false;
  HWND root = GetAncestor(hwnd, GA_ROOT);
  if (root) hwnd = root;
  DWORD pid = 0;
  GetWindowThreadProcessId(hwnd, &pid);
  return pid == GetCurrentProcessId();
}

bool IsHotkeyVk(int vk) {
  return vk == g_vk_play || vk == g_vk_once || vk == g_vk_record || vk == g_vk_panic;
}

void PushEvent(int kind, int code, int down, int x = 0, int y = 0, int has_pos = 0) {
  MrEvent e{};
  e.kind = kind;
  e.code = code;
  e.down = down;
  e.delay_ms = ConsumeDelay();
  e.x = x;
  e.y = y;
  e.has_pos = has_pos;
  std::lock_guard<std::mutex> lock(g_mu);
  g_recorded.push_back(e);
}

LRESULT CALLBACK KeyboardProc(int code, WPARAM wParam, LPARAM lParam) {
  if (code >= 0) {
    const auto* data = reinterpret_cast<KBDLLHOOKSTRUCT*>(lParam);
    const bool down = wParam == WM_KEYDOWN || wParam == WM_SYSKEYDOWN;
    const bool up = wParam == WM_KEYUP || wParam == WM_SYSKEYUP;
    if ((down || up) && !IsHotkeyVk(static_cast<int>(data->vkCode))) {
      PushEvent(MR_KIND_KEY, static_cast<int>(data->vkCode), down ? 1 : 0);
    }
  }
  return CallNextHookEx(g_kb, code, wParam, lParam);
}

LRESULT CALLBACK MouseProc(int code, WPARAM wParam, LPARAM lParam) {
  if (code >= 0) {
    const auto* data = reinterpret_cast<MSLLHOOKSTRUCT*>(lParam);
    if (IsOwnWindowAt(data->pt)) {
      return CallNextHookEx(g_mouse, code, wParam, lParam);
    }
    int button = -1;
    int down = 0;
    switch (wParam) {
      case WM_LBUTTONDOWN:
        button = MR_MOUSE_LEFT;
        down = 1;
        break;
      case WM_LBUTTONUP:
        button = MR_MOUSE_LEFT;
        down = 0;
        break;
      case WM_RBUTTONDOWN:
        button = MR_MOUSE_RIGHT;
        down = 1;
        break;
      case WM_RBUTTONUP:
        button = MR_MOUSE_RIGHT;
        down = 0;
        break;
      case WM_MBUTTONDOWN:
        button = MR_MOUSE_MIDDLE;
        down = 1;
        break;
      case WM_MBUTTONUP:
        button = MR_MOUSE_MIDDLE;
        down = 0;
        break;
      case WM_XBUTTONDOWN:
        button = (HIWORD(data->mouseData) == XBUTTON2) ? MR_MOUSE_X2 : MR_MOUSE_X1;
        down = 1;
        break;
      case WM_XBUTTONUP:
        button = (HIWORD(data->mouseData) == XBUTTON2) ? MR_MOUSE_X2 : MR_MOUSE_X1;
        down = 0;
        break;
      default:
        break;
    }
    if (button >= 0) {
      // Store client coords relative to the top-level window under the cursor so
      // silent playback can SendMessage to that window without moving the cursor.
      POINT pt = data->pt;
      HWND hit = WindowFromPoint(pt);
      HWND root = hit ? GetAncestor(hit, GA_ROOT) : nullptr;
      int cx = 0, cy = 0, has_pos = 0;
      if (root) {
        POINT local = pt;
        if (ScreenToClient(root, &local)) {
          cx = local.x;
          cy = local.y;
          has_pos = 1;
        }
      }
      PushEvent(MR_KIND_MOUSE, button, down, cx, cy, has_pos);
    }
  }
  return CallNextHookEx(g_mouse, code, wParam, lParam);
}

void HookThreadMain() {
  g_hook_tid = GetCurrentThreadId();
  HMODULE mod = nullptr;
  GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                         GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                     reinterpret_cast<LPCWSTR>(&KeyboardProc), &mod);
  g_kb = SetWindowsHookExW(WH_KEYBOARD_LL, KeyboardProc, mod, 0);
  g_mouse = SetWindowsHookExW(WH_MOUSE_LL, MouseProc, mod, 0);
  MSG msg;
  while (GetMessageW(&msg, nullptr, 0, 0) > 0) {
    TranslateMessage(&msg);
    DispatchMessageW(&msg);
  }
  if (g_kb) UnhookWindowsHookEx(g_kb);
  if (g_mouse) UnhookWindowsHookEx(g_mouse);
  g_kb = nullptr;
  g_mouse = nullptr;
}

HWND FindTarget(const std::string& process, const std::string& title) {
  struct Query {
    std::wstring process;
    std::wstring title;
    HWND hwnd = nullptr;
  } q{Utf8ToWide(process.c_str()), Utf8ToWide(title.c_str())};

  EnumWindows(
      [](HWND hwnd, LPARAM lp) -> BOOL {
        if (!IsWindowVisible(hwnd)) return TRUE;
        auto* query = reinterpret_cast<Query*>(lp);
        wchar_t buf[512];
        GetWindowTextW(hwnd, buf, 512);
        std::wstring wtitle = buf;
        if (!query->title.empty() &&
            wtitle.find(query->title) == std::wstring::npos)
          return TRUE;
        DWORD pid = 0;
        GetWindowThreadProcessId(hwnd, &pid);
        HANDLE h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
        if (!h) return TRUE;
        wchar_t path[MAX_PATH];
        DWORD n = MAX_PATH;
        BOOL ok = QueryFullProcessImageNameW(h, 0, path, &n);
        CloseHandle(h);
        if (!ok) return TRUE;
        std::wstring image = path;
        auto slash = image.find_last_of(L"\\/");
        std::wstring name = slash == std::wstring::npos ? image : image.substr(slash + 1);
        if (name.size() > 4 && _wcsicmp(name.c_str() + name.size() - 4, L".exe") == 0)
          name.resize(name.size() - 4);
        if (!query->process.empty() && _wcsicmp(name.c_str(), query->process.c_str()) != 0)
          return TRUE;
        query->hwnd = hwnd;
        return FALSE;
      },
      reinterpret_cast<LPARAM>(&q));
  return q.hwnd;
}

void ActivateWindow(HWND hwnd) {
  if (!hwnd || !IsWindow(hwnd)) return;
  if (IsIconic(hwnd)) ShowWindow(hwnd, SW_RESTORE);
  HWND fg = GetForegroundWindow();
  DWORD thisTid = GetCurrentThreadId();
  DWORD fgTid = GetWindowThreadProcessId(fg, nullptr);
  if (fgTid != thisTid) AttachThreadInput(thisTid, fgTid, TRUE);
  BringWindowToTop(hwnd);
  SetForegroundWindow(hwnd);
  if (fgTid != thisTid) AttachThreadInput(thisTid, fgTid, FALSE);
}

void InterruptibleSleep(std::atomic<bool>& stop, int ms);

void PostKey(HWND hwnd, WORD vk, bool up) {
  const UINT msg = up ? WM_KEYUP : WM_KEYDOWN;
  const UINT scan = MapVirtualKeyW(vk, MAPVK_VK_TO_VSC);
  LPARAM lp = 1 | (static_cast<LPARAM>(scan) << 16);
  if (up) lp |= (1L << 30) | (1L << 31);
  if (IsExtended(vk)) lp |= (1L << 24);
  if (!PostMessageW(hwnd, msg, vk, lp)) {
    g_last_input_status.store(GetLastError() == ERROR_ACCESS_DENIED ? 1 : 2);
  }
}

DWORD ProcessIntegrity(HANDLE token) {
  DWORD len = 0;
  GetTokenInformation(token, TokenIntegrityLevel, nullptr, 0, &len);
  if (len == 0) return 0;
  std::vector<BYTE> buf(len);
  if (!GetTokenInformation(token, TokenIntegrityLevel, buf.data(), len, &len)) return 0;
  auto* til = reinterpret_cast<TOKEN_MANDATORY_LABEL*>(buf.data());
  if (!til || !til->Label.Sid) return 0;
  return *GetSidSubAuthority(til->Label.Sid, static_cast<DWORD>(*GetSidSubAuthorityCount(til->Label.Sid) - 1));
}

DWORD ProcessIntegrityByPid(DWORD pid) {
  HANDLE proc = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (!proc) return 0x7000;  // treat unreadable as high / blocked
  HANDLE token = nullptr;
  DWORD level = 0;
  if (OpenProcessToken(proc, TOKEN_QUERY, &token)) {
    level = ProcessIntegrity(token);
    CloseHandle(token);
  }
  CloseHandle(proc);
  return level;
}

DWORD OurIntegrity() {
  HANDLE token = nullptr;
  DWORD level = SECURITY_MANDATORY_MEDIUM_RID;
  if (OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) {
    level = ProcessIntegrity(token);
    CloseHandle(token);
  }
  return level;
}

bool TargetNeedsAdmin(HWND hwnd) {
  if (!hwnd || !IsWindow(hwnd)) return false;
  DWORD pid = 0;
  GetWindowThreadProcessId(hwnd, &pid);
  if (!pid) return false;
  return ProcessIntegrityByPid(pid) > OurIntegrity();
}

HWND SameRootOrNull(HWND root, HWND candidate) {
  if (!candidate || !IsWindow(candidate)) return nullptr;
  HWND candRoot = GetAncestor(candidate, GA_ROOT);
  HWND wantRoot = root ? GetAncestor(root, GA_ROOT) : nullptr;
  if (wantRoot && candRoot && candRoot != wantRoot) return nullptr;
  return candidate;
}

HWND ResolveLeafFromScreen(HWND root, POINT screen) {
  // Prefer walking children of the known target. WindowFromPoint returns the
  // topmost window at that screen point (often the foreground app), which is
  // wrong when the target is in the background — the Clicador-style case.
  if (root && IsWindow(root)) {
    POINT local = screen;
    if (ScreenToClient(root, &local)) {
      HWND child = root;
      for (int depth = 0; depth < 32; depth++) {
        HWND next =
            ChildWindowFromPointEx(child, local, CWP_SKIPINVISIBLE | CWP_SKIPDISABLED);
        if (!next || next == child) break;
        MapWindowPoints(child, next, &local, 1);
        child = next;
      }
      return child;
    }
  }

  HWND fromPt = WindowFromPoint(screen);
  if (HWND ok = SameRootOrNull(root, fromPt)) return ok;
  return fromPt ? fromPt : root;
}

struct ResolvedClick {
  HWND hwnd = nullptr;
  int x = 0;
  int y = 0;
  POINT screen{};
};

ResolvedClick ResolveClickTarget(HWND root, int clientX, int clientY, bool has_pos) {
  ResolvedClick out;
  out.hwnd = root;
  out.x = clientX;
  out.y = clientY;
  if (!root || !IsWindow(root)) return out;

  POINT screen{};
  if (has_pos) {
    screen.x = clientX;
    screen.y = clientY;
    ClientToScreen(root, &screen);
  } else {
    GetCursorPos(&screen);
  }

  HWND leaf = ResolveLeafFromScreen(root, screen);
  if (!leaf) leaf = root;
  out.hwnd = leaf;
  out.screen = screen;

  POINT local = screen;
  ScreenToClient(leaf, &local);
  out.x = local.x;
  out.y = local.y;
  return out;
}

void MouseMsgParts(int button, bool down, UINT* msg, WPARAM* wp) {
  *msg = WM_LBUTTONDOWN;
  *wp = 0;
  switch (button) {
    case MR_MOUSE_LEFT:
      *msg = down ? WM_LBUTTONDOWN : WM_LBUTTONUP;
      if (down) *wp = MK_LBUTTON;
      break;
    case MR_MOUSE_RIGHT:
      *msg = down ? WM_RBUTTONDOWN : WM_RBUTTONUP;
      if (down) *wp = MK_RBUTTON;
      break;
    case MR_MOUSE_MIDDLE:
      *msg = down ? WM_MBUTTONDOWN : WM_MBUTTONUP;
      if (down) *wp = MK_MBUTTON;
      break;
    case MR_MOUSE_X1:
      *msg = down ? WM_XBUTTONDOWN : WM_XBUTTONUP;
      *wp = MAKEWPARAM(down ? MK_XBUTTON1 : 0, XBUTTON1);
      break;
    case MR_MOUSE_X2:
      *msg = down ? WM_XBUTTONDOWN : WM_XBUTTONUP;
      *wp = MAKEWPARAM(down ? MK_XBUTTON2 : 0, XBUTTON2);
      break;
    default:
      break;
  }
}

WPARAM MouseMoveKeys(int button) {
  switch (button) {
    case MR_MOUSE_LEFT:
      return MK_LBUTTON;
    case MR_MOUSE_RIGHT:
      return MK_RBUTTON;
    case MR_MOUSE_MIDDLE:
      return MK_MBUTTON;
    case MR_MOUSE_X1:
      return MK_XBUTTON1;
    case MR_MOUSE_X2:
      return MK_XBUTTON2;
    default:
      return 0;
  }
}

LPARAM PackClientLParam(int x, int y) {
  const int cx = (std::max)(-32768, (std::min)(32767, x));
  const int cy = (std::max)(-32768, (std::min)(32767, y));
  return MAKELPARAM(static_cast<WORD>(static_cast<short>(cx)),
                    static_cast<WORD>(static_cast<short>(cy)));
}

const wchar_t* MsgName(UINT msg) {
  switch (msg) {
    case WM_MOUSEMOVE:
      return L"WM_MOUSEMOVE";
    case WM_LBUTTONDOWN:
      return L"WM_LBUTTONDOWN";
    case WM_LBUTTONUP:
      return L"WM_LBUTTONUP";
    case WM_RBUTTONDOWN:
      return L"WM_RBUTTONDOWN";
    case WM_RBUTTONUP:
      return L"WM_RBUTTONUP";
    case WM_MBUTTONDOWN:
      return L"WM_MBUTTONDOWN";
    case WM_MBUTTONUP:
      return L"WM_MBUTTONUP";
    case WM_XBUTTONDOWN:
      return L"WM_XBUTTONDOWN";
    case WM_XBUTTONUP:
      return L"WM_XBUTTONUP";
    default:
      return L"WM_?";
  }
}

void LogSilentSend(HWND root, HWND target, int x, int y, UINT msg, const wchar_t* api) {
  wchar_t buf[384];
  _snwprintf_s(buf, _TRUNCATE,
               L"[MacroRelay Silent] API=%s root=%p target=%p client=(%d,%d) msg=%s (0x%04X) lParam=0x%08lX\n",
               api, root, target, x, y, MsgName(msg), msg,
               static_cast<unsigned long>(PackClientLParam(x, y)));
  OutputDebugStringW(buf);
}

// Clicador-style ClickAppNoMove: SendMessage calls the target WndProc directly
// without SetCursorPos / SetForegroundWindow / AttachThreadInput. PostMessage alone
// often never runs for background / non-pumping game clients.
bool SilentSendMouseMessage(HWND root, HWND hwnd, UINT msg, WPARAM wp, int x, int y) {
  if (!hwnd || !IsWindow(hwnd)) {
    g_last_input_status.store(2);
    return false;
  }
  const LPARAM lp = PackClientLParam(x, y);
  LogSilentSend(root, hwnd, x, y, msg, L"SendMessageTimeoutW");
  DWORD_PTR result = 0;
  const LRESULT ok =
      SendMessageTimeoutW(hwnd, msg, wp, lp, SMTO_ABORTIFHUNG | SMTO_NORMAL, 1000, &result);
  if (!ok) {
    const DWORD err = GetLastError();
    g_last_input_status.store(err == ERROR_ACCESS_DENIED || err == 5 || err == ERROR_TIMEOUT ? 1 : 2);
    wchar_t buf[192];
    _snwprintf_s(buf, _TRUNCATE, L"[MacroRelay Silent] SendMessageTimeoutW FAILED err=%lu — trying PostMessageW\n",
                 static_cast<unsigned long>(err));
    OutputDebugStringW(buf);
    LogSilentSend(root, hwnd, x, y, msg, L"PostMessageW");
    if (!PostMessageW(hwnd, msg, wp, lp)) {
      g_last_input_status.store(GetLastError() == ERROR_ACCESS_DENIED ? 1 : 2);
      return false;
    }
  }
  return true;
}

bool SilentDispatchToTargets(HWND root, HWND leaf, int rootX, int rootY, int leafX, int leafY, UINT msg,
                             WPARAM wp) {
  // Clicador ClickAppNoMove targets one "App Handle" (top-level) with client coords.
  // Prefer that first — many game clients ignore child HWNDs.
  bool ok = SilentSendMouseMessage(root, root, msg, wp, rootX, rootY);
  // If a real child exists, also deliver there (Win32 controls). Same client message
  // on an inert DirectX child is usually ignored, so this rarely double-fires in games.
  if (leaf && leaf != root) {
    SilentSendMouseMessage(root, leaf, msg, wp, leafX, leafY);
  }
  return ok;
}

bool SilentPostMouseEdge(HWND root, int button, bool down, int clientX, int clientY, bool has_pos,
                         std::atomic<bool>* stop) {
  g_last_input_status.store(0);
  if (!root || !IsWindow(root)) return false;

  const int rootX = has_pos ? clientX : 0;
  const int rootY = has_pos ? clientY : 0;
  ResolvedClick t = ResolveClickTarget(root, clientX, clientY, has_pos);
  UINT msg = 0;
  WPARAM wp = 0;
  MouseMsgParts(button, down, &msg, &wp);

  if (down) {
    if (!SilentDispatchToTargets(root, t.hwnd, rootX, rootY, t.x, t.y, WM_MOUSEMOVE, 0)) return false;
    if (stop) InterruptibleSleep(*stop, kClickMoveDelayMs);
    else std::this_thread::sleep_for(std::chrono::milliseconds(kClickMoveDelayMs));
    if (stop && stop->load()) return false;
  }
  return SilentDispatchToTargets(root, t.hwnd, rootX, rootY, t.x, t.y, msg, wp);
}

bool SilentPostMouseClickSequence(HWND root, int button, int clientX, int clientY, bool has_pos,
                                  std::atomic<bool>& stop) {
  g_last_input_status.store(0);
  if (!root || !IsWindow(root)) return false;

  const int rootX = has_pos ? clientX : 0;
  const int rootY = has_pos ? clientY : 0;
  ResolvedClick t = ResolveClickTarget(root, clientX, clientY, has_pos);
  UINT downMsg = 0, upMsg = 0;
  WPARAM downWp = 0, upWp = 0;
  MouseMsgParts(button, true, &downMsg, &downWp);
  MouseMsgParts(button, false, &upMsg, &upWp);

  OutputDebugStringW(
      L"[MacroRelay Silent] MOVE→DOWN→hold→UP via SendMessageTimeoutW (no cursor/focus)\n");
  if (!SilentDispatchToTargets(root, t.hwnd, rootX, rootY, t.x, t.y, WM_MOUSEMOVE, 0)) return false;
  InterruptibleSleep(stop, kClickMoveDelayMs);
  if (stop.load()) return false;
  if (!SilentDispatchToTargets(root, t.hwnd, rootX, rootY, t.x, t.y, downMsg, downWp)) return false;
  InterruptibleSleep(stop, kClickHoldDelayMs);
  if (stop.load()) return false;
  if (!SilentDispatchToTargets(root, t.hwnd, rootX, rootY, t.x, t.y, WM_MOUSEMOVE, MouseMoveKeys(button)))
    return false;
  return SilentDispatchToTargets(root, t.hwnd, rootX, rootY, t.x, t.y, upMsg, upWp);
}

void SendMouseClickAtScreen(POINT screen, int button) {
  OutputDebugStringW(L"[MacroRelay SnapBack] SetCursorPos + SendInput click\n");
  POINT saved{};
  GetCursorPos(&saved);
  SetCursorPos(screen.x, screen.y);
  std::this_thread::sleep_for(std::chrono::milliseconds(8));
  MoveAbs(screen.x, screen.y);
  SendMouseButton(button, true);
  std::this_thread::sleep_for(std::chrono::milliseconds(kClickHoldDelayMs));
  SendMouseButton(button, false);
  SetCursorPos(saved.x, saved.y);
  MoveAbs(saved.x, saved.y);
}

void SendMouseEdgeAtScreen(POINT screen, int button, bool down) {
  OutputDebugStringW(L"[MacroRelay SnapBack] SetCursorPos + SendInput edge\n");
  POINT saved{};
  GetCursorPos(&saved);
  SetCursorPos(screen.x, screen.y);
  std::this_thread::sleep_for(std::chrono::milliseconds(8));
  MoveAbs(screen.x, screen.y);
  SendMouseButton(button, down);
  SetCursorPos(saved.x, saved.y);
  MoveAbs(saved.x, saved.y);
}

bool UseSnapBack(int input_mode, HWND hwnd) {
  // Silent mode must never snap-back (no SetCursorPos / SendInput).
  if (input_mode == MR_INPUT_SILENT) return false;
  if (input_mode == MR_INPUT_SNAPBACK) return true;
  if (input_mode == MR_INPUT_AUTO && TargetNeedsAdmin(hwnd)) {
    g_last_input_status.store(1);
    return true;
  }
  return false;
}

void PlayPositionalMouse(HWND root, int button, bool down, int x, int y, bool has_pos, int input_mode,
                         std::atomic<bool>* stop, bool full_click) {
  if (!root) root = GetForegroundWindow();
  if (!root) return;

  ResolvedClick t = ResolveClickTarget(root, x, y, has_pos);

  // Strict silent pathway: SendMessageTimeoutW only (no SetCursorPos / SendInput / focus APIs).
  if (input_mode == MR_INPUT_SILENT) {
    if (full_click && stop) {
      SilentPostMouseClickSequence(root, button, x, y, has_pos, *stop);
    } else {
      SilentPostMouseEdge(root, button, down, x, y, has_pos, stop);
    }
    return;
  }

  if (UseSnapBack(input_mode, root)) {
    g_last_input_status.store(input_mode == MR_INPUT_AUTO ? 1 : 0);
    if (full_click) {
      SendMouseClickAtScreen(t.screen, button);
    } else {
      SendMouseEdgeAtScreen(t.screen, button, down);
    }
    return;
  }

  // Auto (non-elevated): try silent PostMessage first; snap-back only if post fails.
  bool ok = false;
  if (full_click && stop) {
    ok = SilentPostMouseClickSequence(root, button, x, y, has_pos, *stop);
  } else {
    ok = SilentPostMouseEdge(root, button, down, x, y, has_pos, stop);
  }
  if (!ok && input_mode == MR_INPUT_AUTO) {
    OutputDebugStringW(L"[MacroRelay Auto] PostMessage failed — falling back to SnapBack\n");
    if (full_click) {
      SendMouseClickAtScreen(t.screen, button);
    } else {
      SendMouseEdgeAtScreen(t.screen, button, down);
    }
  }
}

void PostMouse(HWND hwnd, int button, bool down, int x, int y) {
  SilentPostMouseEdge(hwnd, button, down, x, y, true, nullptr);
}

void PostText(HWND hwnd, const std::wstring& text) {
  for (wchar_t ch : text) {
    PostMessageW(hwnd, WM_CHAR, static_cast<WPARAM>(ch), 1);
  }
}

void PostWheel(HWND hwnd, int delta, int x, int y) {
  ResolvedClick t = ResolveClickTarget(hwnd, x, y, true);
  POINT pt = t.screen;
  PostMessageW(t.hwnd, WM_MOUSEWHEEL, MAKEWPARAM(0, delta), MAKELPARAM(pt.x, pt.y));
}

void PostDrag(HWND hwnd, int button, int x1, int y1, int x2, int y2) {
  ResolvedClick a = ResolveClickTarget(hwnd, x1, y1, true);
  ResolvedClick b = ResolveClickTarget(hwnd, x2, y2, true);
  HWND target = a.hwnd ? a.hwnd : hwnd;
  WPARAM mk = MouseMoveKeys(button);
  SilentSendMouseMessage(hwnd, target, WM_MOUSEMOVE, 0, a.x, a.y);
  std::this_thread::sleep_for(std::chrono::milliseconds(kClickMoveDelayMs));
  UINT downMsg = 0;
  WPARAM downWp = 0;
  MouseMsgParts(button, true, &downMsg, &downWp);
  SilentSendMouseMessage(hwnd, target, downMsg, downWp, a.x, a.y);
  const int n = 12;
  for (int i = 1; i <= n; i++) {
    const int x = a.x + (b.x - a.x) * i / n;
    const int y = a.y + (b.y - a.y) * i / n;
    SilentSendMouseMessage(hwnd, target, WM_MOUSEMOVE, mk, x, y);
    std::this_thread::sleep_for(std::chrono::milliseconds(8));
  }
  UINT upMsg = 0;
  WPARAM upWp = 0;
  MouseMsgParts(button, false, &upMsg, &upWp);
  SilentSendMouseMessage(hwnd, target, upMsg, upWp, b.x, b.y);
}

void SendWheel(int delta) {
  INPUT in{};
  in.type = INPUT_MOUSE;
  in.mi.dwFlags = MOUSEEVENTF_WHEEL;
  in.mi.mouseData = static_cast<DWORD>(delta);
  SendInput(1, &in, sizeof(INPUT));
}

int ScaleDelay(int ms, double speed, bool jitter, std::mt19937& rng) {
  double sp = speed <= 0 ? 1.0 : speed;
  double value = ms / sp;
  if (jitter) {
    std::uniform_real_distribution<double> dist(-0.15, 0.15);
    value *= 1.0 + dist(rng);
  }
  if (value < 0) value = 0;
  if (value > 60000) value = 60000;
  return static_cast<int>(std::lround(value));
}

void InterruptibleSleep(std::atomic<bool>& stop, int ms) {
  if (ms <= 0) return;
  const auto deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(ms);
  while (!stop.load()) {
    const auto now = std::chrono::steady_clock::now();
    if (now >= deadline) break;
    auto left = std::chrono::duration_cast<std::chrono::milliseconds>(deadline - now).count();
    if (left <= 0) break;
    std::this_thread::sleep_for(std::chrono::milliseconds(left > 10 ? 10 : left));
  }
}

HWND ResolveTarget(HWND cached, const std::string& process, const std::string& title) {
  if (cached && IsWindow(cached)) return cached;
  if (process.empty() && title.empty()) return nullptr;
  return FindTarget(process, title);
}

void EnsureRestoredNoActivate(HWND hwnd) {
  if (!hwnd || !IsWindow(hwnd) || !IsIconic(hwnd)) return;
  ShowWindow(hwnd, SW_SHOWNOACTIVATE);
  SetWindowPos(hwnd, HWND_NOTOPMOST, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
  HWND fg = GetForegroundWindow();
  if (fg && fg != hwnd) {
    SetWindowPos(hwnd, fg, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
  }
  std::this_thread::sleep_for(std::chrono::milliseconds(80));
}

void PlayStep(const Step& step, int focus_mode, int input_mode, HWND hwnd, std::atomic<bool>& stop) {
  const bool background = focus_mode == MR_FOCUS_BACKGROUND && hwnd != nullptr;
  const bool silent = input_mode == MR_INPUT_SILENT;

  // Silent must never steal focus (no AttachThreadInput / SetForegroundWindow).
  if (!silent && focus_mode == MR_FOCUS_TARGET && hwnd && GetForegroundWindow() != hwnd) {
    ActivateWindow(hwnd);
  }

  if (background) {
    // Silent: do not ShowWindow / SetWindowPos — leave Z-order and minimize state alone.
    if (!silent) EnsureRestoredNoActivate(hwnd);
    if (TargetNeedsAdmin(hwnd)) g_last_input_status.store(1);
    int cx = step.x;
    int cy = step.y;
    if (!step.has_pos) {
      POINT pt{};
      GetCursorPos(&pt);
      ScreenToClient(hwnd, &pt);
      cx = pt.x;
      cy = pt.y;
    }
    switch (step.kind) {
      case MR_KIND_KEY:
        PostKey(hwnd, static_cast<WORD>(step.code), step.down == 0);
        break;
      case MR_KIND_MOUSE:
        PlayPositionalMouse(hwnd, step.code, step.down != 0, cx, cy, step.has_pos != 0, input_mode,
                            &stop, false);
        break;
      case MR_KIND_TEXT:
        PostText(hwnd, step.text);
        break;
      case MR_KIND_WHEEL:
        PostWheel(hwnd, step.code, cx, cy);
        break;
      case MR_KIND_DRAG:
        PostDrag(hwnd, step.code, step.x, step.y, step.x2, step.y2);
        break;
      default:
        break;
    }
    return;
  }

  switch (step.kind) {
    case MR_KIND_KEY:
      if (step.down) {
        SendKey(static_cast<WORD>(step.code), false);
        TrackKey(static_cast<WORD>(step.code), true);
      } else {
        SendKey(static_cast<WORD>(step.code), true);
        TrackKey(static_cast<WORD>(step.code), false);
      }
      break;
    case MR_KIND_MOUSE: {
      if (step.has_pos) {
        HWND target = hwnd ? hwnd : GetForegroundWindow();
        if (target) {
          PlayPositionalMouse(target, step.code, step.down != 0, step.x, step.y, true, input_mode,
                              &stop, false);
        }
        break;
      }
      if (step.down) {
        SendMouseButton(step.code, true);
        TrackButton(step.code, true);
      } else {
        SendMouseButton(step.code, false);
        TrackButton(step.code, false);
      }
      break;
    }
    case MR_KIND_TEXT:
      for (wchar_t ch : step.text) {
        SendUnicode(ch, false);
        SendUnicode(ch, true);
      }
      break;
    case MR_KIND_WHEEL: {
      HWND target = hwnd ? hwnd : GetForegroundWindow();
      if (target && step.has_pos) {
        PostWheel(target, step.code, step.x, step.y);
      } else {
        SendWheel(step.code);
      }
      break;
    }
    case MR_KIND_DRAG: {
      HWND target = hwnd ? hwnd : GetForegroundWindow();
      if (target) {
        PostDrag(target, step.code, step.x, step.y, step.x2, step.y2);
      }
      break;
    }
    default:
      break;
  }
}

void JoinWorker(Session* s) {
  if (s && s->worker.joinable()) s->worker.join();
}

void WorkerMain(Session* s) {
  std::mt19937 rng{std::random_device{}()};
  std::vector<Step> steps;
  int interval_ms = 50;
  double speed = 1.0;
  bool jitter = false;
  int loop_mode = 0;
  int repeat_count = 1;
  int duration_ms = 10000;
  int focus_mode = 0;
  int input_mode = MR_INPUT_SILENT;
  std::string process;
  std::string title;
  {
    std::lock_guard<std::mutex> lock(g_mu);
    steps = s->steps;
    interval_ms = s->interval_ms;
    speed = s->speed;
    jitter = s->jitter;
    loop_mode = s->loop_mode;
    repeat_count = s->repeat_count;
    duration_ms = s->duration_ms;
    focus_mode = s->focus_mode;
    input_mode = s->input_mode;
    process = s->process;
    title = s->title;
  }

  const auto started = std::chrono::steady_clock::now();
  int loops = 0;
  size_t index = 0;
  HWND hwnd = nullptr;
  while (!s->stop.load()) {
    if (s->pause.load()) {
      s->state.store(2);
      InterruptibleSleep(s->stop, 30);
      continue;
    }
    s->state.store(1);
    if (loop_mode == MR_LOOP_DURATION) {
      auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
                         std::chrono::steady_clock::now() - started)
                         .count();
      if (elapsed >= duration_ms) break;
    }
    if (index >= steps.size()) {
      loops++;
      if (loop_mode == MR_LOOP_ONCE) break;
      if (loop_mode == MR_LOOP_COUNT && loops >= std::max(1, repeat_count)) break;
      index = 0;
      InterruptibleSleep(s->stop, ScaleDelay(interval_ms, speed, jitter, rng));
      if (steps.empty() || s->stop.load()) continue;
    }
    Step step = steps[index++];
    if (step.kind == MR_KIND_DELAY) {
      InterruptibleSleep(s->stop, ScaleDelay(step.delay_ms, speed, jitter, rng));
      continue;
    }
    if (s->stop.load()) break;
    hwnd = ResolveTarget(hwnd, process, title);

    // Coalesce positional mouse down+up into a full MOVE→DOWN→hold→UP sequence.
    if (step.kind == MR_KIND_MOUSE && step.down && step.has_pos && index < steps.size()) {
      const Step& next = steps[index];
      if (next.kind == MR_KIND_MOUSE && !next.down && next.code == step.code && next.has_pos &&
          next.x == step.x && next.y == step.y) {
        index++;
        const bool silent = input_mode == MR_INPUT_SILENT;
        if (!silent && focus_mode == MR_FOCUS_BACKGROUND && hwnd) EnsureRestoredNoActivate(hwnd);
        if (!silent && focus_mode == MR_FOCUS_TARGET && hwnd && GetForegroundWindow() != hwnd) {
          ActivateWindow(hwnd);
        }
        HWND target = hwnd ? hwnd : GetForegroundWindow();
        if (target) {
          PlayPositionalMouse(target, step.code, true, step.x, step.y, true, input_mode, &s->stop,
                              true);
        }
        continue;
      }
    }

    PlayStep(step, focus_mode, input_mode, hwnd, s->stop);
  }
  ReleaseStuck();
  s->state.store(0);
}

Session* FindSession(int id) {
  auto it = g_sessions.find(id);
  return it == g_sessions.end() ? nullptr : it->second.get();
}

}  // namespace

extern "C" {

const char* mr_version(void) { return "1.5.1"; }

int32_t mr_record_start(int32_t keep_delays) {
  std::lock_guard<std::mutex> lock(g_mu);
  if (g_recording) return 1;
  g_keep_delays = keep_delays != 0;
  g_recorded.clear();
  g_last_tick = GetTickCount64();
  g_first_event = true;
  g_recording = true;
  g_hook_thread = std::thread(HookThreadMain);
  return 0;
}

void mr_record_stop(void) {
  {
    std::lock_guard<std::mutex> lock(g_mu);
    if (!g_recording) return;
    g_recording = false;
  }
  if (g_hook_tid) PostThreadMessageW(g_hook_tid, WM_QUIT, 0, 0);
  if (g_hook_thread.joinable()) g_hook_thread.join();
  g_hook_tid = 0;
}

int32_t mr_record_poll(MrEvent* out, int32_t max_events) {
  if (!out || max_events <= 0) return 0;
  std::lock_guard<std::mutex> lock(g_mu);
  int32_t n = 0;
  while (n < max_events && !g_recorded.empty()) {
    out[n++] = g_recorded.front();
    g_recorded.pop_front();
  }
  return n;
}

int32_t mr_session_create(void) {
  std::lock_guard<std::mutex> lock(g_mu);
  int id = g_next_id++;
  auto s = std::make_unique<Session>();
  s->id = id;
  g_sessions[id] = std::move(s);
  return id;
}

void mr_session_destroy(int32_t id) {
  mr_session_stop(id);
  std::lock_guard<std::mutex> lock(g_mu);
  g_sessions.erase(id);
}

void mr_session_clear_steps(int32_t id) {
  std::lock_guard<std::mutex> lock(g_mu);
  if (auto* s = FindSession(id)) s->steps.clear();
}

void mr_session_set_options(int32_t id, int32_t interval_ms, double speed, int32_t jitter_enabled,
                            int32_t loop_mode, int32_t repeat_count, int32_t duration_ms,
                            int32_t focus_mode) {
  std::lock_guard<std::mutex> lock(g_mu);
  auto* s = FindSession(id);
  if (!s) return;
  s->interval_ms = interval_ms;
  s->speed = speed;
  s->jitter = jitter_enabled != 0;
  s->loop_mode = loop_mode;
  s->repeat_count = repeat_count;
  s->duration_ms = duration_ms;
  s->focus_mode = focus_mode;
}

void mr_session_set_input_mode(int32_t id, int32_t input_mode) {
  std::lock_guard<std::mutex> lock(g_mu);
  auto* s = FindSession(id);
  if (!s) return;
  if (input_mode < 0 || input_mode > 2) input_mode = MR_INPUT_AUTO;
  s->input_mode = input_mode;
}

void mr_session_set_target(int32_t id, const char* process_utf8, const char* title_utf8) {
  std::lock_guard<std::mutex> lock(g_mu);
  auto* s = FindSession(id);
  if (!s) return;
  s->process = process_utf8 ? process_utf8 : "";
  s->title = title_utf8 ? title_utf8 : "";
}

void mr_session_add_key(int32_t id, int32_t vk, int32_t down) {
  std::lock_guard<std::mutex> lock(g_mu);
  auto* s = FindSession(id);
  if (!s) return;
  Step st;
  st.kind = MR_KIND_KEY;
  st.code = vk;
  st.down = down;
  s->steps.push_back(std::move(st));
}

void mr_session_add_mouse(int32_t id, int32_t button, int32_t down, int32_t x, int32_t y,
                          int32_t has_pos) {
  std::lock_guard<std::mutex> lock(g_mu);
  auto* s = FindSession(id);
  if (!s) return;
  Step st;
  st.kind = MR_KIND_MOUSE;
  st.code = button;
  st.down = down;
  st.x = x;
  st.y = y;
  st.has_pos = has_pos;
  s->steps.push_back(std::move(st));
}

void mr_session_add_delay(int32_t id, int32_t delay_ms) {
  std::lock_guard<std::mutex> lock(g_mu);
  auto* s = FindSession(id);
  if (!s) return;
  Step st;
  st.kind = MR_KIND_DELAY;
  st.delay_ms = delay_ms;
  s->steps.push_back(std::move(st));
}

void mr_session_add_text(int32_t id, const char* utf8) {
  std::lock_guard<std::mutex> lock(g_mu);
  auto* s = FindSession(id);
  if (!s) return;
  Step st;
  st.kind = MR_KIND_TEXT;
  st.text = Utf8ToWide(utf8);
  s->steps.push_back(std::move(st));
}

void mr_session_add_wheel(int32_t id, int32_t delta, int32_t x, int32_t y, int32_t has_pos) {
  std::lock_guard<std::mutex> lock(g_mu);
  auto* s = FindSession(id);
  if (!s) return;
  Step st;
  st.kind = MR_KIND_WHEEL;
  st.code = delta;
  st.x = x;
  st.y = y;
  st.has_pos = has_pos;
  s->steps.push_back(std::move(st));
}

void mr_session_add_drag(int32_t id, int32_t button, int32_t x1, int32_t y1, int32_t x2, int32_t y2) {
  std::lock_guard<std::mutex> lock(g_mu);
  auto* s = FindSession(id);
  if (!s) return;
  Step st;
  st.kind = MR_KIND_DRAG;
  st.code = button;
  st.x = x1;
  st.y = y1;
  st.x2 = x2;
  st.y2 = y2;
  st.has_pos = 1;
  s->steps.push_back(std::move(st));
}

int32_t mr_session_start(int32_t id) {
  Session* s = nullptr;
  {
    std::lock_guard<std::mutex> lock(g_mu);
    s = FindSession(id);
    if (!s) return -1;
    if (s->worker.joinable() && s->state.load() == 2) {
      s->pause.store(false);
      s->state.store(1);
      return 0;
    }
    s->stop.store(true);
    s->pause.store(false);
  }
  JoinWorker(s);
  s->stop.store(false);
  s->pause.store(false);
  s->state.store(1);
  s->worker = std::thread(WorkerMain, s);
  return 0;
}

void mr_session_pause(int32_t id) {
  std::lock_guard<std::mutex> lock(g_mu);
  auto* s = FindSession(id);
  if (!s) return;
  s->pause.store(true);
}

void mr_session_stop(int32_t id) {
  Session* s = nullptr;
  {
    std::lock_guard<std::mutex> lock(g_mu);
    s = FindSession(id);
    if (!s) return;
    s->stop.store(true);
    s->pause.store(false);
  }
  JoinWorker(s);
  s->state.store(0);
  ReleaseStuck();
}

void mr_stop_all(void) {
  std::vector<int> ids;
  {
    std::lock_guard<std::mutex> lock(g_mu);
    for (auto& [id, _] : g_sessions) ids.push_back(id);
  }
  for (int id : ids) mr_session_stop(id);
}

int32_t mr_session_state(int32_t id) {
  std::lock_guard<std::mutex> lock(g_mu);
  auto* s = FindSession(id);
  return s ? s->state.load() : 0;
}

int32_t mr_running_count(void) {
  std::lock_guard<std::mutex> lock(g_mu);
  int n = 0;
  for (auto& [_, s] : g_sessions)
    if (s->state.load() == 1) n++;
  return n;
}

int32_t mr_window_at_cursor(char* process, int32_t process_len, char* title, int32_t title_len,
                            int32_t* pid) {
  POINT pt;
  GetCursorPos(&pt);
  HWND hwnd = WindowFromPoint(pt);
  if (!hwnd) return 0;
  HWND root = GetAncestor(hwnd, GA_ROOT);
  if (root) hwnd = root;
  DWORD process_id = 0;
  GetWindowThreadProcessId(hwnd, &process_id);
  if (pid) *pid = static_cast<int32_t>(process_id);
  wchar_t wtitle[512]{};
  GetWindowTextW(hwnd, wtitle, 512);
  std::string t = WideToUtf8(wtitle);
  std::string proc;
  HANDLE h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, process_id);
  if (h) {
    wchar_t path[MAX_PATH];
    DWORD n = MAX_PATH;
    if (QueryFullProcessImageNameW(h, 0, path, &n)) {
      std::wstring image = path;
      auto slash = image.find_last_of(L"\\/");
      std::wstring name = slash == std::wstring::npos ? image : image.substr(slash + 1);
      if (name.size() > 4 && _wcsicmp(name.c_str() + name.size() - 4, L".exe") == 0)
        name.resize(name.size() - 4);
      proc = WideToUtf8(name);
    }
    CloseHandle(h);
  }
  if (process && process_len > 0) {
    std::snprintf(process, static_cast<size_t>(process_len), "%s", proc.c_str());
  }
  if (title && title_len > 0) {
    std::snprintf(title, static_cast<size_t>(title_len), "%s", t.c_str());
  }
  return 1;
}

int32_t mr_cursor_client(const char* process_utf8, const char* title_utf8, int32_t* x, int32_t* y) {
  POINT pt;
  GetCursorPos(&pt);
  HWND hwnd = nullptr;
  if ((process_utf8 && *process_utf8) || (title_utf8 && *title_utf8)) {
    hwnd = FindTarget(process_utf8 ? process_utf8 : "", title_utf8 ? title_utf8 : "");
  }
  if (!hwnd) {
    hwnd = WindowFromPoint(pt);
    if (hwnd) {
      HWND root = GetAncestor(hwnd, GA_ROOT);
      if (root) hwnd = root;
    }
  }
  if (!hwnd) return 0;
  ScreenToClient(hwnd, &pt);
  if (x) *x = pt.x;
  if (y) *y = pt.y;
  return 1;
}

int32_t mr_target_needs_admin(const char* process_utf8, const char* title_utf8) {
  HWND hwnd = FindTarget(process_utf8 ? process_utf8 : "", title_utf8 ? title_utf8 : "");
  if (!hwnd) return 0;
  return TargetNeedsAdmin(hwnd) ? 1 : 0;
}

int32_t mr_last_input_status(void) { return g_last_input_status.load(); }

int32_t mr_ctrl_shift_down(void) {
  return (GetAsyncKeyState(VK_CONTROL) & 0x8000) && (GetAsyncKeyState(VK_SHIFT) & 0x8000) ? 1 : 0;
}

int32_t mr_hotkey_poll(int32_t* play_toggle, int32_t* record_toggle) {
  static bool primed = false;
  static bool play_was = false;
  static bool record_was = false;
  const bool play_down = (GetAsyncKeyState(g_vk_play) & 0x8000) != 0;
  const bool record_down = (GetAsyncKeyState(g_vk_record) & 0x8000) != 0;
  if (!primed) {
    play_was = play_down;
    record_was = record_down;
    primed = true;
    if (play_toggle) *play_toggle = 0;
    if (record_toggle) *record_toggle = 0;
    return 0;
  }
  const int play = (play_down && !play_was) ? 1 : 0;
  const int rec = (record_down && !record_was) ? 1 : 0;
  play_was = play_down;
  record_was = record_down;
  if (play_toggle) *play_toggle = play;
  if (record_toggle) *record_toggle = rec;
  return play || rec;
}

void mr_hotkey_set(int32_t play_vk, int32_t once_vk, int32_t record_vk, int32_t panic_vk) {
  if (play_vk) g_vk_play = play_vk;
  if (once_vk) g_vk_once = once_vk;
  if (record_vk) g_vk_record = record_vk;
  if (panic_vk) g_vk_panic = panic_vk;
}

int32_t mr_key_down(int32_t vk) {
  if (vk <= 0 || vk > 255) return 0;
  return (GetAsyncKeyState(vk) & 0x8000) ? 1 : 0;
}

int32_t mr_any_key_down(void) {
  const int extra[] = {VK_MBUTTON, VK_XBUTTON1, VK_XBUTTON2};
  for (int vk : extra) {
    if (GetAsyncKeyState(vk) & 0x8000) return vk;
  }
  for (int vk = 0x08; vk <= 0xFE; vk++) {
    if (vk == VK_SHIFT || vk == VK_CONTROL || vk == VK_MENU || vk == VK_LSHIFT || vk == VK_RSHIFT ||
        vk == VK_LCONTROL || vk == VK_RCONTROL || vk == VK_LMENU || vk == VK_RMENU || vk == VK_CAPITAL)
      continue;
    if (GetAsyncKeyState(vk) & 0x8000) return vk;
  }
  return 0;
}

void mr_beep(int32_t kind) {
  DWORD freq = 880;
  if (kind == 1) freq = 660;
  if (kind == 2) freq = 440;
  Beep(freq, 70);
}

int32_t mr_pick_file(int32_t save, char* out, int32_t out_len) {
  if (!out || out_len < 8) return 0;
  wchar_t path[MAX_PATH]{};
  OPENFILENAMEW ofn{};
  ofn.lStructSize = sizeof(ofn);
  ofn.hwndOwner = GetForegroundWindow();
  ofn.lpstrFilter = L"JSON (*.json)\0*.json\0All files (*.*)\0*.*\0";
  ofn.lpstrFile = path;
  ofn.nMaxFile = MAX_PATH;
  ofn.Flags = OFN_EXPLORER | OFN_HIDEREADONLY | OFN_NOCHANGEDIR;
  ofn.lpstrDefExt = L"json";
  BOOL ok = FALSE;
  if (save) {
    ofn.Flags |= OFN_OVERWRITEPROMPT;
    ok = GetSaveFileNameW(&ofn);
  } else {
    ofn.Flags |= OFN_FILEMUSTEXIST;
    ok = GetOpenFileNameW(&ofn);
  }
  if (!ok) return 0;
  std::string utf8 = WideToUtf8(path);
  std::snprintf(out, static_cast<size_t>(out_len), "%s", utf8.c_str());
  return 1;
}

int32_t mr_startup_get(void) {
  HKEY key = nullptr;
  if (RegOpenKeyExW(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Run", 0,
                    KEY_READ, &key) != ERROR_SUCCESS)
    return 0;
  DWORD type = 0, bytes = 0;
  const LONG st = RegQueryValueExW(key, L"MacroRelay", nullptr, &type, nullptr, &bytes);
  RegCloseKey(key);
  return st == ERROR_SUCCESS ? 1 : 0;
}

int32_t mr_startup_set(int32_t enable) {
  HKEY key = nullptr;
  if (RegOpenKeyExW(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Run", 0,
                    KEY_SET_VALUE, &key) != ERROR_SUCCESS)
    return 0;
  LONG st;
  if (enable) {
    wchar_t exe[MAX_PATH]{};
    GetModuleFileNameW(nullptr, exe, MAX_PATH);
    wchar_t cmd[MAX_PATH + 24]{};
    _snwprintf_s(cmd, _TRUNCATE, L"\"%s\" --tray", exe);
    st = RegSetValueExW(key, L"MacroRelay", 0, REG_SZ, reinterpret_cast<const BYTE*>(cmd),
                        static_cast<DWORD>((wcslen(cmd) + 1) * sizeof(wchar_t)));
  } else {
    st = RegDeleteValueW(key, L"MacroRelay");
    if (st == ERROR_FILE_NOT_FOUND) st = ERROR_SUCCESS;
  }
  RegCloseKey(key);
  return st == ERROR_SUCCESS ? 1 : 0;
}

LRESULT CALLBACK TraySubclass(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam, UINT_PTR, DWORD_PTR) {
  if (msg == kTrayMsg) {
    if (lparam == WM_LBUTTONUP || lparam == WM_LBUTTONDBLCLK) {
      ShowWindow(hwnd, SW_SHOW);
      ShowWindow(hwnd, SW_RESTORE);
      SetForegroundWindow(hwnd);
    }
    return 0;
  }
  if (msg == WM_CLOSE && g_close_to_tray) {
    ShowWindow(hwnd, SW_HIDE);
    return 0;
  }
  return DefSubclassProc(hwnd, msg, wparam, lparam);
}

HWND AppHwnd() {
  HWND hwnd = GetActiveWindow();
  if (!hwnd) hwnd = GetForegroundWindow();
  if (hwnd) {
    HWND root = GetAncestor(hwnd, GA_ROOT);
    if (root) hwnd = root;
  }
  return hwnd;
}

void mr_close_to_tray(int32_t enable) { g_close_to_tray = enable != 0; }

int32_t mr_tray_set(int32_t enable) {
  HWND hwnd = AppHwnd();
  if (!hwnd) return 0;
  INITCOMMONCONTROLSEX icc{};
  icc.dwSize = sizeof(icc);
  icc.dwICC = ICC_WIN95_CLASSES;
  InitCommonControlsEx(&icc);
  if (enable) {
    if (!g_tray_hwnd) {
      SetWindowSubclass(hwnd, TraySubclass, kTraySubclass, 0);
      g_tray_hwnd = hwnd;
    }
    if (!g_tray_added) {
      NOTIFYICONDATAW nid{};
      nid.cbSize = sizeof(nid);
      nid.hWnd = hwnd;
      nid.uID = 1;
      nid.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
      nid.uCallbackMessage = kTrayMsg;
      nid.hIcon = LoadIconW(GetModuleHandleW(nullptr), MAKEINTRESOURCEW(101));
      if (!nid.hIcon) nid.hIcon = LoadIconW(nullptr, IDI_APPLICATION);
      lstrcpynW(nid.szTip, L"MacroRelay", 128);
      g_tray_added = Shell_NotifyIconW(NIM_ADD, &nid) != FALSE;
    }
  } else if (g_tray_added) {
    NOTIFYICONDATAW nid{};
    nid.cbSize = sizeof(nid);
    nid.hWnd = g_tray_hwnd ? g_tray_hwnd : hwnd;
    nid.uID = 1;
    Shell_NotifyIconW(NIM_DELETE, &nid);
    g_tray_added = false;
  }
  return 1;
}

int32_t mr_window_command(int32_t cmd) {
  HWND hwnd = AppHwnd();
  if (!hwnd) return 0;
  switch (cmd) {
    case 0:
      ReleaseCapture();
      SendMessageW(hwnd, WM_NCLBUTTONDOWN, HTCAPTION, 0);
      break;
    case 1:
      ShowWindow(hwnd, SW_MINIMIZE);
      break;
    case 2:
      ShowWindow(hwnd, IsZoomed(hwnd) ? SW_RESTORE : SW_MAXIMIZE);
      break;
    case 3:
      if (g_close_to_tray) {
        ShowWindow(hwnd, SW_HIDE);
      } else {
        PostMessageW(hwnd, WM_CLOSE, 0, 0);
      }
      break;
    case 4:
      ShowWindow(hwnd, SW_HIDE);
      break;
    case 5:
      ShowWindow(hwnd, SW_SHOW);
      ShowWindow(hwnd, SW_RESTORE);
      SetForegroundWindow(hwnd);
      break;
    default:
      return 0;
  }
  return 1;
}

}  // extern "C"
