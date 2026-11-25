# Contributing to TerminalKit

## Requirements

- Swift 6.4+ on macOS 26+

## Workflow

```sh
swift format lint --strict --recursive Sources Tests Package.swift
swift test
```

Keep terminal mode restoration unconditional (even on crash or signal exit) and keep render hot paths allocation-free.
