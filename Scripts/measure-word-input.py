#!/usr/bin/env python3
"""Measure hard versus word-aware editable layout, from the actual sources compiled with swiftc -O.

Scripts/measure-word-input.py
Nine interleaved pairs, 100 layouts per sample, using ASCII and mixed-width drafts. Prints median and range in us/layout.
"""
from pathlib import Path
import statistics
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
HARNESS = r'''
import Foundation
@main struct Measure {
    static func main() {
        let words = CommandLine.arguments[1] == "words"
        let mixed = CommandLine.arguments[2] == "mixed"
        let text = mixed ? String(repeating: "日本語 e\u{301} 👨‍👩‍👧 words\n", count: 100)
            : String(repeating: "a draft with several words to wrap across the editable input's rows\n", count: 100)
        var checksum = 0
        let elapsed = ContinuousClock().measure {
            for _ in 0 ..< 100 {
                let layout = InputLayout(text, columns: 80, firstRowIndent: 5, wrapsWords: words)
                checksum += layout.rows.count + layout.position(at: text.count).column
            }
        }
        let parts = elapsed.components
        print(Double(parts.seconds) * 1e9 + Double(parts.attoseconds) / 1e9, checksum)
    }
}
'''


def main():
    with tempfile.TemporaryDirectory(prefix='word-input-') as directory:
        work = Path(directory)
        harness = work / 'Measure.swift'
        harness.write_text(HARNESS)
        sources = [ROOT / f'Sources/TerminalKitText/{name}.swift' for name in
                   ['InputLayout', 'UnicodeWidth', 'GeneratedUnicodeTables', 'TextSanitizer']]
        binary = work / 'measure'
        subprocess.run(['swiftc', '-O', *map(str, sources), str(harness), '-o', str(binary)], check=True)
        for corpus in ['ascii', 'mixed']:
            samples = {'hard': [], 'words': []}
            for run in range(9):
                for mode in (['hard', 'words'] if run % 2 == 0 else ['words', 'hard']):
                    nanos, checksum = subprocess.check_output([str(binary), mode, corpus], text=True).split()
                    if int(checksum) <= 0:
                        raise RuntimeError('The layout returned no rows.')
                    samples[mode].append(float(nanos) / 100_000)
            for mode, values in samples.items():
                print(f'{corpus}/{mode}: median {statistics.median(values):.1f} us/layout; '
                      f'range {min(values):.1f}..{max(values):.1f}; 9 x 100 layouts')


if __name__ == '__main__':
    main()
