#include <stdint.h>
#include <stdio.h>
#include <unistd.h>

/* Keep these signatures aligned with lginput2's native entry points. */
static volatile int cursor_mode;
static volatile int argument_errors;

__attribute__((noinline)) int lginput_uinput_send_position(void *device, int x, int y) {
    if (device != (void *)(uintptr_t)0x1234 || x != 321 || y != 654)
        ++argument_errors;
    return 1;
}

__attribute__((noinline)) int lginput_uinput_send_wheel(void *device, int amount) {
    if (device != (void *)(uintptr_t)0x1234 || amount != -7)
        ++argument_errors;
    return 2;
}

__attribute__((noinline)) int lginput_uinput_send_custom_event(
        void *device, int kind, unsigned int reason) {
    if (device != (void *)(uintptr_t)0x1234 || reason != 0x5a17u)
        ++argument_errors;
    if (kind == 4)
        cursor_mode = 1;
    else if (kind == 5)
        cursor_mode = 0;
    return 100 + kind;
}

__attribute__((noinline)) int lginput_uinput_send_button(
        void *device, int code, int value) {
    if (device != (void *)(uintptr_t)0x1234 ||
        (code != 0x110 && code != 0x1d0 && code != 0x1d1) ||
        (value != 0 && value != 1 && value != 2))
        ++argument_errors;
    return 1000 + code * 10 + value;
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    while (1) {
        int position = lginput_uinput_send_position((void *)(uintptr_t)0x1234, 321, 654);
        int wheel = lginput_uinput_send_wheel((void *)(uintptr_t)0x1234, -7);
        int custom_on = lginput_uinput_send_custom_event((void *)(uintptr_t)0x1234, 4, 0x5a17u);
        int mode_after_on = cursor_mode;
        int custom_other6 = lginput_uinput_send_custom_event((void *)(uintptr_t)0x1234, 6, 0x5a17u);
        int custom_other2 = lginput_uinput_send_custom_event((void *)(uintptr_t)0x1234, 2, 0x5a17u);
        int custom_off = lginput_uinput_send_custom_event((void *)(uintptr_t)0x1234, 5, 0x5a17u);
        int mode_after_off = cursor_mode;
        int button_press = lginput_uinput_send_button((void *)(uintptr_t)0x1234, 0x110, 1);
        int button_release = lginput_uinput_send_button((void *)(uintptr_t)0x1234, 0x1d0, 0);
        int button_repeat = lginput_uinput_send_button((void *)(uintptr_t)0x1234, 0x1d1, 2);

        printf("position=%d wheel=%d custom_on=%d mode_after_on=%d "
               "custom6=%d custom2=%d custom_off=%d mode_after_off=%d "
               "buttons=%d,%d,%d arg_errors=%d\n",
               position, wheel, custom_on, mode_after_on, custom_other6,
               custom_other2, custom_off, mode_after_off, button_press,
               button_release, button_repeat, argument_errors);
        sleep(1);
    }
}
