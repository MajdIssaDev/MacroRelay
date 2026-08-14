#pragma once

/* MacroRelay native engine: WH_*_LL hooks + SendInput.
   Mouse move/wheel are never recorded. Playback never injects into other
   processes and never loads a virtual HID / Interception driver. */

#include <stdint.h>

#ifdef _WIN32
#ifdef MACRO_RELAY_EXPORTS
#define MR_API __declspec(dllexport)
#else
#define MR_API __declspec(dllimport)
#endif
#else
#define MR_API
#endif

#ifdef __cplusplus
extern "C" {
#endif

enum MrKind {
  MR_KIND_KEY = 0,
  MR_KIND_MOUSE = 1,
  MR_KIND_DELAY = 2,
  MR_KIND_TEXT = 3,
  MR_KIND_WHEEL = 4,
  MR_KIND_DRAG = 5
};

enum MrMouseButton {
  MR_MOUSE_LEFT = 0,
  MR_MOUSE_RIGHT = 1,
  MR_MOUSE_MIDDLE = 2,
  MR_MOUSE_X1 = 3,
  MR_MOUSE_X2 = 4
};

enum MrLoopMode {
  MR_LOOP_INFINITE = 0,
  MR_LOOP_COUNT = 1,
  MR_LOOP_DURATION = 2,
  MR_LOOP_ONCE = 3
};

enum MrFocusMode {
  MR_FOCUS_NONE = 0,
  MR_FOCUS_TARGET = 1,
  MR_FOCUS_BACKGROUND = 2
};

typedef struct MrEvent {
  int32_t kind;
  int32_t code;
  int32_t down;
  int32_t delay_ms;
  int32_t x;
  int32_t y;
  int32_t has_pos;
} MrEvent;

MR_API const char* mr_version(void);

MR_API int32_t mr_record_start(int32_t keep_delays);
MR_API void mr_record_stop(void);
MR_API int32_t mr_record_poll(MrEvent* out, int32_t max_events);

MR_API int32_t mr_session_create(void);
MR_API void mr_session_destroy(int32_t id);
MR_API void mr_session_clear_steps(int32_t id);
MR_API void mr_session_set_options(int32_t id, int32_t interval_ms, double speed,
                                   int32_t jitter_enabled, int32_t loop_mode,
                                   int32_t repeat_count, int32_t duration_ms,
                                   int32_t focus_mode);
MR_API void mr_session_set_target(int32_t id, const char* process_utf8, const char* title_utf8);
MR_API void mr_session_add_key(int32_t id, int32_t vk, int32_t down);
MR_API void mr_session_add_mouse(int32_t id, int32_t button, int32_t down, int32_t x, int32_t y,
                                 int32_t has_pos);
MR_API void mr_session_add_delay(int32_t id, int32_t delay_ms);
MR_API void mr_session_add_text(int32_t id, const char* utf8);
MR_API void mr_session_add_wheel(int32_t id, int32_t delta, int32_t x, int32_t y, int32_t has_pos);
MR_API void mr_session_add_drag(int32_t id, int32_t button, int32_t x1, int32_t y1, int32_t x2,
                                int32_t y2);

MR_API int32_t mr_session_start(int32_t id);
MR_API void mr_session_pause(int32_t id);
MR_API void mr_session_stop(int32_t id);
MR_API void mr_stop_all(void);
MR_API int32_t mr_session_state(int32_t id);
MR_API int32_t mr_running_count(void);

MR_API int32_t mr_window_at_cursor(char* process, int32_t process_len, char* title,
                                   int32_t title_len, int32_t* pid);
MR_API int32_t mr_cursor_client(const char* process_utf8, const char* title_utf8,
                                int32_t* x, int32_t* y);
MR_API int32_t mr_ctrl_shift_down(void);
MR_API int32_t mr_hotkey_poll(int32_t* play_toggle, int32_t* record_toggle);
MR_API void mr_hotkey_set(int32_t play_vk, int32_t once_vk, int32_t record_vk, int32_t panic_vk);
MR_API int32_t mr_key_down(int32_t vk);
MR_API int32_t mr_any_key_down(void);
MR_API void mr_beep(int32_t kind);
MR_API int32_t mr_pick_file(int32_t save, char* out, int32_t out_len);
MR_API int32_t mr_startup_get(void);
MR_API int32_t mr_startup_set(int32_t enable);
MR_API int32_t mr_tray_set(int32_t enable);
MR_API void mr_close_to_tray(int32_t enable);
MR_API int32_t mr_window_command(int32_t cmd);

#ifdef __cplusplus
}
#endif
