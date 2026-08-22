#include <stdio.h>
#include <sys/utsname.h>

int main(void) {
    struct utsname u;
    if (uname(&u) != 0) {
        perror("uname");
        return 2;
    }

    printf("FLDE_RUNTIME_PROBE_OK\n");
    printf("machine=%s\n", u.machine);
    printf("sysname=%s\n", u.sysname);
    fflush(stdout);
    return 0;
}
