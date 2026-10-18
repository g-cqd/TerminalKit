// Isolated process probe: never changes signal dispositions in the Swift test runner.
#include "CTerminalSignals.h"
#include <assert.h>
#include <errno.h>
#include <signal.h>
#include <stdio.h>

int main(void) {
    struct sigaction ignored = {0}, saved, restored;
    ignored.sa_handler = SIG_IGN;
    sigemptyset(&ignored.sa_mask);
    assert(sigaction(SIGWINCH, &ignored, &saved) == 0);
    assert(tk_signal_prepare() == 0);
    assert(tk_signal_begin(1) == 0);

    // Saturate the wakeup pipe without a reader. A blocking write would hang;
    // coalesced bits must survive saturation, including both shutdown signals.
    for (int i = 0; i < 100000; ++i) assert(raise(SIGWINCH) == 0);
    assert(raise(SIGINT) == 0);
    assert(raise(SIGTERM) == 0);
    TKSignalEvent event = tk_signal_wait();
    assert(event.error == 0 && event.generation == 1 && event.pending == 7);

    // Inspect the installed callback directly to check preservation of errno.
    struct sigaction installed;
    assert(sigaction(SIGINT, 0, &installed) == 0);
    errno = EDOM;
    installed.sa_handler(SIGINT);
    assert(errno == EDOM);

    assert(tk_signal_end() == 0);
    assert(sigaction(SIGWINCH, 0, &restored) == 0);
    assert(restored.sa_handler == SIG_IGN);
    assert(tk_signal_begin(2) == 0);
    // Old pipe wakeups cannot carry old pending bits into a new owner.
    event = tk_signal_wait();
    assert(event.error == 0 && event.generation == 2 && event.pending == 0);
    assert(raise(SIGTERM) == 0);
    event = tk_signal_wait();
    assert(event.generation == 2 && event.pending == 4);
    assert(tk_signal_end() == 0);
    assert(sigaction(SIGWINCH, &saved, 0) == 0);
    puts("signal safety: saturation, errno, dispositions, generation isolation passed");
    return 0;
}
