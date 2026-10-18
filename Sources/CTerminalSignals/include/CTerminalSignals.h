#ifndef C_TERMINAL_SIGNALS_H
#define C_TERMINAL_SIGNALS_H

#include <stdint.h>

// All lifecycle calls are serialized by the Swift owner. The two descriptors and
// the reader thread live until process exit: closing a descriptor while an OS
// handler might still use its number would allow writes into a reused descriptor.
int tk_signal_prepare(void);
int tk_signal_begin(uint32_t generation);
int tk_signal_end(void);

typedef struct {
    uint32_t generation;
    uint32_t pending;
    int error;
} TKSignalEvent;

// Blocks only the dedicated reader thread. Handlers coalesce the same signals,
// as POSIX signals already do. Bits: 1 = WINCH, 2 = INT, 4 = TERM.
TKSignalEvent tk_signal_wait(void);

#endif
