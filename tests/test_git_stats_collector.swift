/// Unit tests for GitStatsCollector.parseGitLogOutput().
/// Run: swift GitStatsCollectorTests.swift (standalone, no dependencies)

import Foundation

// MARK: - Inline copy of parse logic (for standalone testing without full project compilation)

struct GitStatsResultTest: Equatable {
    let commits: Int
    let additions: Int
    let deletions: Int
    static let zero = GitStatsResultTest(commits: 0, additions: 0, deletions: 0)
}

func parseGitLogOutput(_ output: String) -> GitStatsResultTest {
    var commits = 0
    var totalAdded = 0
    var totalRemoved = 0

    for line in output.components(separatedBy: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { continue }

        if trimmed.contains("\0") {
            let clean = trimmed.replacingOccurrences(of: "\0", with: "")
            if clean.count >= 40 {
                commits += 1
            }
            continue
        }

        let parts = trimmed.components(separatedBy: "\t")
        if parts.count == 3 {
            guard let added = Int(parts[0]), let removed = Int(parts[1]) else { continue }
            totalAdded += added
            totalRemoved += removed
        }
    }

    return GitStatsResultTest(commits: commits, additions: totalAdded, deletions: totalRemoved)
}

// MARK: - Test harness

var passed = 0
var failed = 0

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ msg: String, line: Int = #line) {
    if actual == expected {
        passed += 1
    } else {
        failed += 1
        print("FAIL [line \(line)] \(msg): expected \(expected), got \(actual)")
    }
}

// MARK: - Tests

func testEmptyOutput() {
    let result = parseGitLogOutput("")
    assertEqual(result.commits, 0, "empty output commits")
    assertEqual(result.additions, 0, "empty output additions")
    assertEqual(result.deletions, 0, "empty output deletions")
}

func testSingleCommitWithNumstat() {
    let output = "\0abc123def456789012345678901234567890abcd\nfeat: add new feature\n\nCo-Authored-By: Claude\0\n10\t2\tsrc/main.swift\n5\t0\tREADME.md"
    let result = parseGitLogOutput(output)
    assertEqual(result.commits, 1, "single commit count")
    assertEqual(result.additions, 15, "single commit additions")
    assertEqual(result.deletions, 2, "single commit deletions")
}

func testMultipleCommits() {
    let hash1 = String(repeating: "a", count: 40)
    let hash2 = String(repeating: "b", count: 40)
    let output = "\0\(hash1)\nfirst commit\0\n3\t1\tfile1.py\n7\t2\tfile2.py\n\n\0\(hash2)\nsecond commit\0\n20\t10\tfile3.py"
    let result = parseGitLogOutput(output)
    assertEqual(result.commits, 2, "multiple commits count")
    assertEqual(result.additions, 30, "multiple commits additions")
    assertEqual(result.deletions, 13, "multiple commits deletions")
}

func testBinaryFilesSkipped() {
    let hash = String(repeating: "c", count: 40)
    let output = "\0\(hash)\nadd image\0\n-\t-\timage.png\n5\t1\tindex.html"
    let result = parseGitLogOutput(output)
    assertEqual(result.commits, 1, "binary skip commits")
    assertEqual(result.additions, 5, "binary skip additions")
    assertEqual(result.deletions, 1, "binary skip deletions")
}

func testNoNumstatLines() {
    let hash = String(repeating: "d", count: 40)
    let output = "\0\(hash)\nempty commit with no file changes\0"
    let result = parseGitLogOutput(output)
    assertEqual(result.commits, 1, "no numstat commits")
    assertEqual(result.additions, 0, "no numstat additions")
    assertEqual(result.deletions, 0, "no numstat deletions")
}

func testGitStatsResultEquality() {
    let a = GitStatsResultTest(commits: 1, additions: 10, deletions: 5)
    let b = GitStatsResultTest(commits: 1, additions: 10, deletions: 5)
    let c = GitStatsResultTest.zero
    assertEqual(a == b, true, "equal results")
    assertEqual(a == c, false, "unequal results")
}

func testMalformedLines() {
    let output = "random garbage\nnot\ta\tnumstat\tbut\ttoo\tmany\ttabs\nabc\tdef\tfile.txt"
    let result = parseGitLogOutput(output)
    assertEqual(result.commits, 0, "malformed commits")
    assertEqual(result.additions, 0, "malformed additions")
    assertEqual(result.deletions, 0, "malformed deletions")
}

// MARK: - Run all tests

testEmptyOutput()
testSingleCommitWithNumstat()
testMultipleCommits()
testBinaryFilesSkipped()
testNoNumstatLines()
testGitStatsResultEquality()
testMalformedLines()

print("\nResults: \(passed) passed, \(failed) failed")
if failed > 0 {
    exit(1)
}
