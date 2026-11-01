/// Lines that lend their bytes, as a diff reads them, and a string's lines as a diff cuts them: aemi's (ADR 0023), re-exported for
/// the clients that take them from this module. ``Rope`` conforms to `LineSource`.
@_exported public import protocol AemiText.LineSource
@_exported public import struct AemiText.TextLines
