# android_simple

`com.zig.simple_native_activity`

A Simple NativeActivity sample.
Do nothing.

This example show how to use `native_app_glue` and `android_main` entry point.

```sh
> zig build run
> adb logcat -v color -s "ZIG"
I ZIG     : #### android_main: enter ####
D ZIG     : handle_cmd: cmd = APP_CMD_START
D ZIG     : handle_cmd: cmd = APP_CMD_RESUME
D ZIG     : handle_cmd: cmd = APP_CMD_INPUT_CHANGED
D ZIG     : handle_cmd: cmd = APP_CMD_INIT_WINDOW
D ZIG     : handle_cmd: cmd = APP_CMD_WINDOW_RESIZED
D ZIG     : handle_cmd: cmd = APP_CMD_CONTENT_RECT_CHANGED
D ZIG     : handle_cmd: cmd = APP_CMD_WINDOW_REDRAW_NEEDED
D ZIG     : handle_cmd: cmd = APP_CMD_GAINED_FOCUS
D ZIG     : handle_cmd: cmd = APP_CMD_LOST_FOCUS
D ZIG     : handle_cmd: cmd = APP_CMD_PAUSE
D ZIG     : handle_cmd: cmd = APP_CMD_TERM_WINDOW
D ZIG     : handle_cmd: cmd = APP_CMD_STOP
D ZIG     : handle_cmd: cmd = APP_CMD_SAVE_STATE
D ZIG     : handle_cmd: cmd = APP_CMD_INPUT_CHANGED
D ZIG     : handle_cmd: cmd = APP_CMD_DESTROY
I ZIG     : #### android_main: exit ####
```
