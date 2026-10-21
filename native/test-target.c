#include <stdio.h>
#include <unistd.h>

__attribute__((noinline)) int lginput_uinput_send_position(void) { return 1; }
__attribute__((noinline)) int lginput_uinput_send_wheel(void) { return 2; }
__attribute__((noinline)) int lginput_uinput_send_custom_event(void) { return 3; }
__attribute__((noinline)) int lginput_uinput_send_button(void) { return 123; }

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    while (1) {
        printf("position=%d wheel=%d custom=%d button=%d\n",
            lginput_uinput_send_position(), lginput_uinput_send_wheel(),
            lginput_uinput_send_custom_event(), lginput_uinput_send_button());
        sleep(1);
    }
}
