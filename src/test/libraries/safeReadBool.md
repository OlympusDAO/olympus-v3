# safeReadBool scenario plan

Scope: the internal `SafeCallDecoder.safeReadBool(target, selector)` library function. It performs a
no-argument static call and returns a success flag plus a bool without bubbling target or ABI decode
failures. It has no caller authorization, lifecycle state, storage writes, or events.

## Domains and assertions

The target either has no code, reverts, or returns successfully. Successful returndata is short
(0..31 bytes), exactly one ABI word (32 bytes), or oversized (at least 33 bytes). `SafeCall` copies
at most 33 bytes so oversized data remains distinguishable from one exact word without copying
unbounded returndata.

Canonical bool words are exactly zero and one. Every value in `2..type(uint256).max` is a malformed
bool encoding even though it occupies exactly 32 bytes. Failure returns `(false, false)`. Success
returns `(true, false)` for zero or `(true, true)` for one. The function changes no state and emits
no events.

| ID | Target/call | Returndata | Input domain / exact seeds | Expected return | Test |
| --- | --- | --- | --- | --- | --- |
| BOOL-P01 | Target has code; static call succeeds | Exactly 32 bytes | Word is exactly 0 | `(true, false)` | Covered: [canonical seeds][test_whenBoolWordIsCanonical] |
| BOOL-P02 | Target has code; static call succeeds | Exactly 32 bytes | Word is exactly 1 | `(true, true)` | Covered: [canonical seeds][test_whenBoolWordIsCanonical] |
| BOOL-I01 | Target has no code | Empty | Zero address target | `(false, false)` | Covered: [no code][test_whenTargetHasNoCode] |
| BOOL-I02 | Target has code; static call reverts | Any length | Seed empty, 32-byte, and oversized revert data | `(false, false)`; revert data is not bubbled | Covered: [revert-data seeds][test_whenCallReverts] |
| BOOL-I03 | Target has code; static call succeeds | 0..31 bytes | Fuzz length; seed 0, 1, and 31 | `(false, false)` | Covered: [fuzz][test_whenBoolReturnIsShort], [seeds][test_whenBoolReturnIsShortAtBoundaries] |
| BOOL-I04 | Target has code; static call succeeds | At least 33 bytes | Seed 33 and 64 bytes | `(false, false)` | Covered: [seeds][test_whenBoolReturnIsOversized] |
| BOOL-I05 | Target has code; static call succeeds | Exactly 32 bytes | Fuzz `2..type(uint256).max`; seed 2 and `type(uint256).max` | `(false, false)` | Covered: [fuzz][test_whenBoolWordIsNotCanonical], [seeds][test_whenBoolWordIsNotCanonicalAtBoundaries] |

[test_whenBoolReturnIsOversized]: ./safeReadBool.t.sol#L56
[test_whenBoolReturnIsShortAtBoundaries]: ./safeReadBool.t.sol#L49
[test_whenBoolReturnIsShort]: ./safeReadBool.t.sol#L42
[test_whenBoolWordIsCanonical]: ./safeReadBool.t.sol#L75
[test_whenBoolWordIsNotCanonicalAtBoundaries]: ./safeReadBool.t.sol#L69
[test_whenBoolWordIsNotCanonical]: ./safeReadBool.t.sol#L62
[test_whenCallReverts]: ./safeReadBool.t.sol#L35
[test_whenTargetHasNoCode]: ./safeReadBool.t.sol#L27
