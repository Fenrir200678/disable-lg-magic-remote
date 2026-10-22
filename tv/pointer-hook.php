<?php
// Keep the PHP thread and callback storage alive even after live rollback.
const POINTER_HOOK_VERSION = 'settings-dpad-v1';
$log = fopen('/tmp/pointer-hook.log', 'a');
function logmsg($s) {
    global $log;
    fwrite($log, $s . "\n");
    fsync($log);
    echo $s . "\n";
}

// Five-argument Gum ABI embedded in the pinned libphp.so. The original toolkit
// factory lacks revert/status handling, so retain and check our three hooks here.
class PointerHooks {
    private $ffi;
    private $self;
    private $gum;
    private $callbacks = array();
    private $installed = array();

    public function __construct() {
        $this->ffi = FFI::cdef('
            void gum_init(void);
            void *gum_interceptor_obtain(void);
            int gum_interceptor_replace(void *, void *, void *, void *, void **);
            void gum_interceptor_revert(void *, void *);
            void *dlopen(const char *, int);
            void *dlsym(void *, const char *);
        ');
        $this->self = $this->ffi->dlopen(null, 1);
        if ($this->self == null) {
            throw new RuntimeException('dlopen self failed');
        }
        $this->ffi->gum_init();
        $this->gum = $this->ffi->gum_interceptor_obtain();
    }

    public function symbol($name) {
        $address = $this->ffi->dlsym($this->self, $name);
        if ($address == null) {
            throw new RuntimeException('required symbol NOT found: ' . $name);
        }
        return $address;
    }

    public function replace($name, $type, $hook) {
        $address = $this->symbol($name);
        $arrayType = FFI::arrayType($this->ffi->type($type), array(1));
        $original = FFI::new($arrayType);
        $original[0] = $address;
        $replacement = FFI::new($arrayType);
        $replacement[0] = function (...$args) use ($original, $hook) {
            // Ordinary Gum replace() bypasses the replacement for synchronous
            // calls to the original address made from inside this callback.
            return $hook($original[0], ...$args);
        };
        $this->callbacks[] = array($original, $replacement);
        $status = $this->ffi->gum_interceptor_replace(
            $this->gum, $address, $replacement[0], null, null
        );
        if ($status !== 0) {
            throw new RuntimeException('Gum replace failed: ' . $name . ' status=' . $status);
        }
        $this->installed[] = $address;
    }

    public function revert() {
        foreach (array_reverse($this->installed) as $address) {
            $this->ffi->gum_interceptor_revert($this->gum, $address);
        }
        $this->installed = array();
        // Keep callbacks allocated: native callers might still be returning.
    }
}

$pid = getmypid();
$ready = '/tmp/magic-pointer-ready-' . $pid;
$request = '/tmp/magic-pointer-revert-' . $pid;
$ack = '/tmp/magic-pointer-reverted-' . $pid;
$hooks = null;
logmsg('=== pointer-hook ' . POINTER_HOOK_VERSION . ' pid=' . $pid . ' (' . date('c') . ') ===');
try {
    $hooks = new PointerHooks();
    foreach (array('lginput_uinput_send_position', 'lginput_uinput_send_wheel',
                   'lginput_uinput_send_custom_event') as $name) {
        $hooks->symbol($name);
    }
    $hooks->replace('lginput_uinput_send_position', 'int (*)(void *, int, int)',
        function ($original, $handle, $x, $y) { return 0; });
    $hooks->replace('lginput_uinput_send_wheel', 'int (*)(void *, int)',
        function ($original, $handle, $delta) { return 0; });
    $eventLogCount = 0;
    $hooks->replace('lginput_uinput_send_custom_event', 'int (*)(void *, int, unsigned int)',
        function ($original, $handle, $kind, $reason) use (&$eventLogCount) {
            // Native IDs: 4=CURSOR_ON, 5=CURSOR_OFF (not evdev keycodes).
            // OFF, disconnect, and all unrelated custom events remain native.
            $forward = ($kind === 4) ? 5 : $kind;
            if ($eventLogCount < 12) {
                logmsg('custom kind=' . $kind . ' -> ' . $forward);
                ++$eventLogCount;
            }
            return $original($handle, $forward, $reason);
        });
    // send_button stays native: D-pad, OK, press/release/repeat are unchanged.
    if (file_put_contents($ready, 'installed ' . POINTER_HOOK_VERSION . "\n") === false) {
        throw new RuntimeException('could not write hook readiness marker');
    }
    logmsg('hooks ready; cursor ON becomes native cursor OFF');
} catch (Throwable $error) {
    if ($hooks !== null) {
        $hooks->revert();
    }
    @unlink($ready);
    logmsg('installation failed; native functions restored: ' . $error->getMessage());
}
while (true) {
    clearstatcache();
    if (is_file($request)) {
        if ($hooks !== null) {
            $hooks->revert();
        }
        @unlink($ready);
        if (file_put_contents($ack, 'native ' . POINTER_HOOK_VERSION . "\n") === false) {
            logmsg('ERROR: could not acknowledge live rollback');
        }
        @unlink($request);
        logmsg('live rollback: native functions restored; PHP thread retained');
    }
    sleep(1);
}
