# API Version Mismatch Issue

## Date
2026-02-08

## Problem

The codebase is using `@process.collect_output_merged` and `@http.get_stream` APIs that are **not available** in the current release of `moonbitlang/async` (v0.16.5).

## Root Cause

- The `collect_output_merged` function was added to moonbitlang/async on **September 22, 2025** (commit 44b7d12)
- The latest official release is **v0.16.5** from **February 5, 2025**
- The function exists in the `main` branch but hasn't been released yet

## Affected Files

1. `docker.mbt` - Uses `@process.collect_output_merged`
2. `logs.mbt` - Uses `@process.collect_output_merged`
3. `wait_strategy.mbt` - Uses both:
   - `@process.collect_output_merged` (multiple places)
   - `@http.get_stream`

## Verification

Source code verification from GitHub:
- [Process module source](https://github.com/moonbitlang/async/blob/main/src/process/process.mbt) confirms `collect_output_merged` exists
- Commit history shows it was added September 2025
- Latest release v0.16.5 predates this addition

## Solutions

### Option 1: Wait for Next Release (Recommended)
Wait for moonbitlang/async v0.17.0+ which will include the missing functions.

### Option 2: Use Development Version
If MoonBit supports git dependencies, update `moon.mod.json` to use the main branch:
```json
{
  "deps": {
    "moonbitlang/async": { "git": "https://github.com/moonbitlang/async.git", "branch": "main" }
  }
}
```
**Note**: This syntax is unverified - MoonBit's git dependency support is unclear.

### Option 3: Implement Workaround
Rewrite affected code to use `@process.run` with pipes manually.

## Required Actions

1. **Update dependency**: When moonbitlang/async v0.17.0+ is released, update `moon.mod.json`
2. **Verify APIs**: Ensure all used APIs are available in the target version
3. **Test compilation**: Run `moon check` after updating

## References

- [MoonBit Async GitHub](https://github.com/moonbitlang/async)
- [Commit adding collect_output_merged](https://github.com/moonbitlang/async/commit/44b7d12)
- [Latest Release v0.16.5](https://github.com/moonbitlang/async/releases/tag/v0.16.5)
