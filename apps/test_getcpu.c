#define _GNU_SOURCE
#include <elf.h>
#include <errno.h>
#include <pthread.h>
#include <sched.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/auxv.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>

static long diff(struct timespec end, struct timespec start) {
    return (end.tv_sec - start.tv_sec) * 1000000000L + (end.tv_nsec - start.tv_nsec);
}

typedef int (*vdso_getcpu_t)(unsigned *cpu, unsigned *node, void *unused);

typedef struct {
    int tid;
    int bind_cpu;
    int loops;
    unsigned long samples;
    unsigned long mismatches;
    unsigned long errors;
} worker_arg_t;

static int bind_to_cpu(int cpu) {
    cpu_set_t set;
    CPU_ZERO(&set);
    CPU_SET((size_t)cpu, &set);
    return sched_setaffinity(0, sizeof(set), &set);
}

static inline int sys_getcpu(unsigned *cpu) {
    return syscall(SYS_getcpu, cpu, NULL, NULL);
}

static vdso_getcpu_t resolve_vdso_getcpu() {
    uintptr_t base = getauxval(AT_SYSINFO_EHDR);
    if (!base) return NULL;

    Elf64_Ehdr *eh = (Elf64_Ehdr *)base;
    Elf64_Phdr *ph = (Elf64_Phdr *)(base + eh->e_phoff);

    Elf64_Dyn *dyn = NULL;
    for (int i = 0; i < eh->e_phnum; i++)
        if (ph[i].p_type == PT_DYNAMIC)
            dyn = (Elf64_Dyn *)(base + ph[i].p_vaddr);

    if (!dyn) return NULL;

    Elf64_Sym *symtab = NULL;
    const char *strtab = NULL;
    uint32_t *hashtab = NULL;

    for (Elf64_Dyn *d = dyn; d->d_tag != DT_NULL; d++) {
        if (d->d_tag == DT_SYMTAB) symtab = (void *)(base + d->d_un.d_ptr);
        if (d->d_tag == DT_STRTAB) strtab = (void *)(base + d->d_un.d_ptr);
        if (d->d_tag == DT_HASH)   hashtab = (void *)(base + d->d_un.d_ptr);
    }

    if (!symtab || !strtab || !hashtab) return NULL;

    size_t n = hashtab[1];
    for (size_t i = 0; i < n; i++) {
        const char *name = strtab + symtab[i].st_name;
        if (!strcmp(name, "__vdso_getcpu"))
            return (vdso_getcpu_t)(base + symtab[i].st_value);
    }

    return NULL;
}

static void *worker_fn(void *p) {
    worker_arg_t *a = (worker_arg_t *)p;

    if (a->bind_cpu >= 0) {
        if (bind_to_cpu(a->bind_cpu) != 0) {
            fprintf(stderr, "[T%d] bind cpu %d failed: %s\n",
                    a->tid, a->bind_cpu, strerror(errno));
            a->errors++;
            return NULL;
        }
    }

    for (int i = 0; i < a->loops; i++) {
        unsigned sys_cpu = 0;

        if (sys_getcpu(&sys_cpu) != 0) {
            a->errors++;
            continue;
        }

        vdso_getcpu_t vdso_fn = resolve_vdso_getcpu();
        if (!vdso_fn) {
            a->errors++;
            continue;
        }

        unsigned vdso_cpu = 0;
        if (vdso_fn(&vdso_cpu, NULL, NULL) != 0) {
            a->errors++;
            continue;
        }

        a->samples++;

        if (a->bind_cpu >= 0 && (int)sys_cpu != a->bind_cpu) {
            a->mismatches++;
        }
        if (vdso_cpu != sys_cpu) {
            a->mismatches++;
        }
    }
    return NULL;
}

static long getcpu_sched(int n) {
    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    for (int i = 0; i < n; i++) {
        sched_getcpu();
    }
    clock_gettime(CLOCK_MONOTONIC, &t1);
    return diff(t1, t0);
}

static long getcpu_syscall(int n) {
    struct timespec t0, t1;
    unsigned cpu = 0;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    for (int i = 0; i < n; i++) {
        sys_getcpu(&cpu);
    }
    clock_gettime(CLOCK_MONOTONIC, &t1);
    return diff(t1, t0);
}

static long getcpu_vdso_direct(vdso_getcpu_t fn, int n) {
    struct timespec t0, t1;
    unsigned cpu = 0, node = 0;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    for (int i = 0; i < n; i++) {
        fn(&cpu, &node, NULL);
    }
    clock_gettime(CLOCK_MONOTONIC, &t1);
    return diff(t1, t0);
}

int main() {
    int loops = 200000;
    int nthreads = (int)sysconf(_SC_NPROCESSORS_ONLN);

    printf("threads=%d loops=%d\n", nthreads, loops);
    pthread_t *ths = calloc((size_t)nthreads, sizeof(*ths));
    worker_arg_t *args = calloc((size_t)nthreads, sizeof(*args));
    if (!ths || !args) {
        printf("FAIL: alloc\n");
        free(ths);
        free(args);
        return 2;
    }
    for (int i = 0; i < nthreads; i++) {
        args[i].tid = i;
        args[i].bind_cpu = i;
        args[i].loops = loops;
        pthread_create(&ths[i], NULL, worker_fn, &args[i]);
    }
    for (int i = 0; i < nthreads; i++) pthread_join(ths[i], NULL);

    unsigned long total_samples = 0, total_mismatch = 0, total_err = 0;
    for (int i = 0; i < nthreads; i++) {
        total_samples += args[i].samples;
        total_mismatch += args[i].mismatches;
        total_err += args[i].errors;
    }

    printf("samples=%lu mismatch=%lu errors=%lu\n",
           total_samples, total_mismatch, total_err);
    free(ths);
    free(args);

    int n = 1000000;
    vdso_getcpu_t vdso_getcpu = resolve_vdso_getcpu();
    if (vdso_getcpu) {
        long direct_vdso_time = getcpu_vdso_direct(vdso_getcpu, n);
        printf("direct __vdso_getcpu time: %ld ns\n", direct_vdso_time);
    } else {
        printf("direct __vdso_getcpu not found\n");
    }

    long sched_time = getcpu_sched(n);
    long syscall_time = getcpu_syscall(n);
    printf("sched_getcpu time: %ld ns\n", sched_time);
    printf("syscall getcpu time: %ld ns\n", syscall_time);

    return 0;
}
