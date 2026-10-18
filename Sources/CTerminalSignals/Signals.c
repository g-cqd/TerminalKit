#include "CTerminalSignals.h"
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdatomic.h>
#include <unistd.h>

_Static_assert(ATOMIC_LLONG_LOCK_FREE == 2, "Signal callbacks require lock-free atomics");

static int descriptors[2] = {-1, -1};
static const int signals[3] = {SIGWINCH, SIGINT, SIGTERM};
static struct sigaction previous[3];
// High 32 bits identify the owner; low bits coalesce pending signals.
static _Atomic unsigned long long pending = 0;

static void deliver(int number) {
    const int saved_errno = errno;
    const unsigned bit = number == SIGWINCH ? 1u : number == SIGINT ? 2u : 4u;
    unsigned long long observed = atomic_load_explicit(&pending, memory_order_relaxed);
    const unsigned long long generation = observed >> 32;
    if (generation != 0) {
        while ((observed >> 32) == generation) {
            if (atomic_compare_exchange_weak_explicit(&pending, &observed, observed | bit,
                                                      memory_order_relaxed, memory_order_relaxed)) {
                // Async-signal-safe, no Swift runtime or locks. A full nonblocking
                // pipe already contains a wakeup; the pending bit is retained.
                const unsigned char wake = 1;
                ssize_t written;
                do { written = write(descriptors[1], &wake, 1); } while (written < 0 && errno == EINTR);
                break;
            }
        }
    }
    errno = saved_errno;
}

int tk_signal_prepare(void) {
    if (descriptors[0] >= 0) return 0;
    int created[2];
    if (pipe(created) != 0) return errno;
    int error = 0;
    if (fcntl(created[0], F_SETFD, FD_CLOEXEC) < 0 ||
        fcntl(created[1], F_SETFD, FD_CLOEXEC) < 0 ||
        fcntl(created[1], F_SETFL, O_NONBLOCK) < 0) error = errno;
    if (error != 0) {
        close(created[0]);
        close(created[1]);
        return error;
    }
    descriptors[0] = created[0];
    descriptors[1] = created[1];
    return 0;
}

int tk_signal_begin(uint32_t generation) {
    if (generation == 0 || descriptors[0] < 0) return EINVAL;
    struct sigaction action = {0};
    action.sa_handler = deliver;
    sigemptyset(&action.sa_mask);
    atomic_store_explicit(&pending, (unsigned long long)generation << 32, memory_order_relaxed);
    for (int i = 0; i < 3; ++i) {
        if (sigaction(signals[i], &action, &previous[i]) != 0) {
            const int error = errno;
            atomic_store_explicit(&pending, 0, memory_order_relaxed);
            while (i > 0) { --i; sigaction(signals[i], &previous[i], 0); }
            return error;
        }
    }
    return 0;
}

int tk_signal_end(void) {
    atomic_store_explicit(&pending, 0, memory_order_relaxed);
    int error = 0;
    for (int i = 0; i < 3; ++i) {
        if (sigaction(signals[i], &previous[i], 0) != 0 && error == 0) error = errno;
    }
    return error;
}

TKSignalEvent tk_signal_wait(void) {
    unsigned char wakeups[64];
    ssize_t count;
    do { count = read(descriptors[0], wakeups, sizeof wakeups); } while (count < 0 && errno == EINTR);
    if (count <= 0) return (TKSignalEvent){0, 0, count < 0 ? errno : EPIPE};
    const unsigned long long value = atomic_fetch_and_explicit(
        &pending, 0xffffffff00000000ULL, memory_order_relaxed);
    return (TKSignalEvent){(uint32_t)(value >> 32), (uint32_t)value, 0};
}
