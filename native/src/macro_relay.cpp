#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include "macro_relay.h"

#include <windows.h>

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

void PushEvent(int kind, int code, int down) {
  MrEvent e{};
  e.kind = kind;
  e.code = code;
  e.down = down;
  e.delay_ms = ConsumeDelay();
  e.has_pos = 0;
  std::lock_guard<std::mutex> lock(g_mu);
  g_recorded.push_back(e);
}

LRESULT CALLBACK KeyboardProc(int code, WPARAM wParam, LPARAM lParam) {
  if (code >= 0) {
    const auto* data = reinterpret_cast<KBDLLHOOKSTRUCT*>(lParam);
    const bool down = wParam == WM_KEYDOWN || wParam == WM_SYSKEYDOWN;
    const bool up = wParam == WM_KEYUP || wParam == WM_SYSKEYUP;
    if (down || up) PushEvent(MR_KIND_KEY, static_cast<int>(data->vkCode), down ? 1 : 0);
  }
  return CallNextHookEx(g_kb, code, wParam, lParam);
}

LRESULT CALLBACK MouseProc(int code, WPARAM wParam, LPARAM lParam) {
  if (code >= 0) {
    const auto* data = reinterpret_cast<MSLLHOOKSTRUCT*>(lParam);
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
    if (button >= 0) PushEvent(MR_KIND_MOUSE, button, down);
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

void PostKey(HWND hwnd, WORD vk, bool up) {
  const UINT msg = up ? WM_KEYUP : WM_KEYDOWN;
  const UINT scan = MapVirtualKeyW(vk, MAPVK_VK_TO_VSC);
  LPARAM lp = 1 | (static_cast<LPARAM>(scan) << 16);
  if (up) lp |= (1L << 30) | (1L << 31);
  if (IsExtended(vk)) lp |= (1L << 24);
  PostMessageW(hwnd, msg, vk, lp);
}

void PostMouse(HWND hwnd, int button, bool down, int x, int y) {
  UINT msg = WM_LBUTTONDOWN;
  WPARAM wp = 0;
  switch (button) {
    case MR_MOUSE_LEFT:
      msg = down ? WM_LBUTTONDOWN : WM_LBUTTONUP;
      if (down) wp = MK_LBUTTON;
      break;
    case MR_MOUSE_RIGHT:
      msg = down ? WM_RBUTTONDOWN : WM_RBUTTONUP;
      if (down) wp = MK_RBUTTON;
      break;
    case MR_MOUSE_MIDDLE:
      msg = down ? WM_MBUTTONDOWN : WM_MBUTTONUP;
      if (down) wp = MK_MBUTTON;
      break;
    case MR_MOUSE_X1:
      msg = down ? WM_XBUTTONDOWN : WM_XBUTTONUP;
      wp = MAKEWPARAM(down ? MK_XBUTTON1 : 0, XBUTTON1);
      break;
    case MR_MOUSE_X2:
      msg = down ? WM_XBUTTONDOWN : WM_XBUTTONUP;
      wp = MAKEWPARAM(down ? MK_XBUTTON2 : 0, XBUTTON2);
      break;
    default:
      break;
  }
  const LPARAM lp = MAKELPARAM(x, y);
  PostMessageW(hwnd, WM_MOUSEMOVE, 0, lp);
  PostMessageW(hwnd, msg, wp, lp);
}

void PostText(HWND hwnd, const std::wstring& text) {
  for (wchar_t ch : text) {
    PostMessageW(hwnd, WM_CHAR, static_cast<WPARAM>(ch), 1);
  }
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

void PlayStep(const Step& step, int focus_mode, HWND hwnd) {
  const bool background = focus_mode == MR_FOCUS_BACKGROUND && hwnd != nullptr;

  if (focus_mode == MR_FOCUS_TARGET && hwnd && GetForegroundWindow() != hwnd) {
    ActivateWindow(hwnd);
  }

  if (background) {
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
        PostMouse(hwnd, step.code, step.down != 0, cx, cy);
        break;
      case MR_KIND_TEXT:
        PostText(hwnd, step.text);
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
          PostMouse(target, step.code, step.down != 0, step.x, step.y);
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
    PlayStep(step, focus_mode, hwnd);
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

const char* mr_version(void) { return "1.2.2"; }

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

int32_t mr_ctrl_shift_down(void) {
  return (GetAsyncKeyState(VK_CONTROL) & 0x8000) && (GetAsyncKeyState(VK_SHIFT) & 0x8000) ? 1 : 0;
}

}  // extern "C"
