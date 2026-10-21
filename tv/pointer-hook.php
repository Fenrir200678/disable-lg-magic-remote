<?php
// pointer-hook.php — disable the LG Magic Remote on-screen pointer by no-op'ing
// the lginput2 functions that emit it, WITHOUT restarting lginput2.
//
// Injected into the running lginput2 via ezinject (ptrace) + libphp + hookfactory
// (Frida Gum interceptor), the same machinery as Simon34545/lginputhook. Because
// injection doesn't restart lginput2, the Magic Remote's radio link is never
// disturbed.
//
// Run by:  ezinject <pid-of-lginput2> <libphp.so> pointer-hook.php lginput2
require_once __DIR__ . '/hookfactory.php';

$hf = new HookFactory2("");

$log = fopen("/tmp/pointer-hook.log", "a");
function logmsg($s) { global $log; fwrite($log, $s . "\n"); fsync($log); echo $s . "\n"; }
logmsg("=== pointer-hook starting (" . date('c') . ") ===");

// lginput2 emits the on-screen pointer through these exported functions. No-op
// them so the cursor never appears/moves. lginput_uinput_send_button (the real
// D-pad/OK/number buttons) is deliberately NOT hooked, so navigation still works.
$targets = array(
    'lginput_uinput_send_position',       // cursor ABS_X / ABS_Y
    'lginput_uinput_send_wheel',          // scroll wheel
    'lginput_uinput_send_custom_event',   // LG custom event codes including 
                                          // cursor on/off (0x4ae/0x4af)
);

// Validate all symbols before installing any hooks.
foreach ($targets as $fn) {
    if (!$hf->hasSymbol($fn)) {
        throw new RuntimeException("required symbol NOT found: $fn");
    }
}

foreach ($targets as $fn) {
    // No-op replacement: ignore args, return 0, don't call the original.
    // (void) signature is safe on ARM AAPCS for a no-op (caller cleans
    // up the stack).
    $hf->newHook("int (*)(void)", $fn, function ($orig) { return 0; });
    logmsg("no-op hook installed: $fn");
}

logmsg("pointer-hook installed; pointer should be disabled");
if (file_put_contents('/tmp/magic-pointer-ready-' . getmypid(), "installed\n") === false) {
    throw new RuntimeException('could not write hook readiness marker');
}

// Keep the injected thread alive to keep hooks active
while (true) {
    sleep(1);
}
