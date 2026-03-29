#define _GNU_SOURCE

#include <stdio.h>
#include <sys/time.h>
#include <time.h>
#include <sys/syscall.h>
#include <unistd.h>
#include <sys/auxv.h>
#include <errno.h>
#include <string.h>

static long diff(struct timespec end, struct timespec start) {
    return (end.tv_sec - start.tv_sec) * 1000000000L + (end.tv_nsec - start.tv_nsec);
}

static void print_res(const char *name, const struct timespec *ts) {
    printf("clock_getres(%s) = %ld.%09ld s\n", name, (long)ts->tv_sec, (long)ts->tv_nsec);
}

static long clock_gettime_vdso(clockid_t clk, int n) {
    struct timespec t0, t1, ts;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    for (int i = 0; i < n; i++) {
        if (clock_gettime(clk, &ts) != 0) {
            printf("clock_gettime failed\n");
            return -1;
        }
    }
    clock_gettime(CLOCK_MONOTONIC, &t1);
    return diff(t1, t0);
}

static long clock_gettime_syscall(clockid_t clk, int n) {
    struct timespec t0, t1, ts;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    for (int i = 0; i < n; i++) {
        if (syscall(SYS_clock_gettime, clk, &ts) != 0) {
            printf("clock_gettime syscall failed\n");
            return -1;
        }
    }
    clock_gettime(CLOCK_MONOTONIC, &t1);
    return diff(t1, t0);
}

static long gettimeofday_vdso(int n, struct timeval *last) {
    struct timespec t0, t1;
    struct timeval tv = {0};

    clock_gettime(CLOCK_MONOTONIC, &t0);
    for (int i = 0; i < n; i++) {
        if (gettimeofday(&tv, NULL) != 0) {
            return -1;
        }
    }
    clock_gettime(CLOCK_MONOTONIC, &t1);

    *last = tv;
    return diff(t1, t0);
}

static long gettimeofday_syscall(int n, struct timeval *last) {
    struct timespec t0, t1;
    struct timeval tv = {0};

    clock_gettime(CLOCK_MONOTONIC, &t0);
    for (int i = 0; i < n; i++) {
        if (syscall(SYS_gettimeofday, &tv, NULL) != 0) {
            return -1;
        }
    }
    clock_gettime(CLOCK_MONOTONIC, &t1);

    *last = tv;
    return diff(t1, t0);
}

int main() {
    int n = 1000000;
    clockid_t clk = CLOCK_REALTIME;
    struct timeval tv = {0};
    unsigned long ehdr = getauxval(AT_SYSINFO_EHDR);
    printf("AT_SYSINFO_EHDR = 0x%lx\n", ehdr);
    struct timespec mono_res = {0}, real_res = {0};
    if (clock_getres(CLOCK_MONOTONIC, &mono_res) != 0) {
        printf("FAIL: clock_getres(CLOCK_MONOTONIC): %s\n", strerror(errno));
        return 1;
    }
    if (clock_getres(CLOCK_REALTIME, &real_res) != 0) {
        printf("FAIL: clock_getres(CLOCK_REALTIME): %s\n", strerror(errno));
        return 2;
    }

    print_res("CLOCK_MONOTONIC", &mono_res);
    print_res("CLOCK_REALTIME", &real_res);

    long vdso_time = clock_gettime_vdso(clk, n);
    long syscall_time = clock_gettime_syscall(clk, n);
    printf("vdso time: %ld ns\n", vdso_time);
    printf("syscall time: %ld ns\n", syscall_time);

    long vdso_gettimeofday_time = gettimeofday_vdso(n, &tv);
    long syscall_gettimeofday_time = gettimeofday_syscall(n, &tv);
    printf("vdso gettimeofday time: %ld ns\n", vdso_gettimeofday_time);
    printf("syscall gettimeofday time: %ld ns\n", syscall_gettimeofday_time);
    
    return 0;
}