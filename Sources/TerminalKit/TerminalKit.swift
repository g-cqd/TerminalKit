/// TerminalKit — the umbrella.
///
/// Re-exports the core so a consumer that only wants the terminal stack imports one module. Test
/// support is deliberately **not** re-exported: the oracle terminal model exists to check a caller,
/// and a shipping binary that links it has paid for a test double it never consulted.

@_exported public import TerminalKitCore
