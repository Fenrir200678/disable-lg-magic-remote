/* Bridge the current ezinject module ABI to the legacy PHP module's lib_main.
 * The legacy crt_init is deliberately never called with a modern bearing.
 */
#include <dlfcn.h>
#include <stdio.h>
#include "ezinject_module.h"

int lib_loginit(log_config_t *config) {
    (void)config;
    return -1; /* Use the current CRT's default log configuration. */
}

int lib_preinit(struct injcode_user *user) {
    user->persist = 1;
    return 0;
}

int lib_main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "PHP bridge: expected libphp.so and a PHP script\n");
        return 1;
    }
    void *php = dlopen(argv[1], RTLD_NOW | RTLD_GLOBAL);
    if (!php) {
        fprintf(stderr, "PHP bridge: %s\n", dlerror());
        return 1;
    }
    int (*php_main)(int, char **) = dlsym(php, "lib_main");
    if (!php_main) {
        fprintf(stderr, "PHP bridge: %s\n", dlerror());
        dlclose(php);
        return 1;
    }
    /* This legacy entry point copies argv and starts the PHP worker, then
     * returns -1 even on success. Keep PHP loaded for that worker's lifetime.
     * The PHP script's per-process ready file confirms actual hook success.
     */
    php_main(argc - 1, argv + 1);
    return 0;
}
