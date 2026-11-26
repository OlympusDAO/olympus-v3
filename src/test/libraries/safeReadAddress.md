# safeReadAddress scenario plan

Scope: the internal `SafeCallDecoder.safeReadAddress(target, selector)` library function. It performs
a no-argument static call and returns a success flag plus an address without bubbling target or ABI
decode failures. It has no caller authorization, lifecycle state, storage writes, or events.

## Domains and assertions

The target either has no code, reverts, or returns successfully. Successful returndata is short
(0..31 bytes), exactly one ABI word (32 bytes), or oversized (at least 33 bytes). `SafeCall` copies
at most 33 bytes so oversized data remains distinguishable from one exact word without copying
unbounded returndata.

A canonical address word contains a value in `0..type(uint160).max`; its upper 12 bytes are zero.
A larger 32-byte value has dirty upper bits and is not a valid ABI address encoding. Failure returns
`(false, address(0))`. Success returns `(true, decodedAddress)`. The function changes no state and
emits no events.

| ID | Target/call | Returndata | Input domain / exact seeds | Expected return | Test |
| --- | --- | --- | --- | --- | --- |
| ADDR-P01 | Target has code; static call succeeds | Exactly 32 bytes | Fuzz canonical words `0..type(uint160).max`; seed zero, one, and `type(uint160).max` | `(true, address(uint160(word)))` | Covered: [fuzz][test_whenAddressWordIsCanonical], [seeds][test_whenAddressWordIsCanonicalAtBoundaries] |
| ADDR-I01 | Target has no code | Empty | Zero address target | `(false, address(0))` | Covered: [no code][test_whenTargetHasNoCode] |
| ADDR-I02 | Target has code; static call reverts | Any length | Seed empty, 32-byte, and oversized revert data | `(false, address(0))`; revert data is not bubbled | Covered: [revert-data seeds][test_whenCallReverts] |
| ADDR-I03 | Target has code; static call succeeds | 0..31 bytes | Fuzz length; seed 0, 1, and 31 | `(false, address(0))` | Covered: [fuzz][test_whenAddressReturnIsShort], [seeds][test_whenAddressReturnIsShortAtBoundaries] |
| ADDR-I04 | Target has code; static call succeeds | At least 33 bytes | Seed 33 and 64 bytes | `(false, address(0))` | Covered: [seeds][test_whenAddressReturnIsOversized] |
| ADDR-I05 | Target has code; static call succeeds | Exactly 32 bytes | Fuzz `type(uint160).max + 1..type(uint256).max`; seed both endpoints | `(false, address(0))` | Covered: [fuzz][test_whenAddressWordHasDirtyUpperBits], [seeds][test_whenAddressWordHasDirtyUpperBitsAtBoundaries] |

[test_whenAddressReturnIsOversized]: ./safeReadAddress.t.sol#L57
[test_whenAddressReturnIsShortAtBoundaries]: ./safeReadAddress.t.sol#L50
[test_whenAddressReturnIsShort]: ./safeReadAddress.t.sol#L43
[test_whenAddressWordHasDirtyUpperBitsAtBoundaries]: ./safeReadAddress.t.sol#L70
[test_whenAddressWordHasDirtyUpperBits]: ./safeReadAddress.t.sol#L63
[test_whenAddressWordIsCanonicalAtBoundaries]: ./safeReadAddress.t.sol#L81
[test_whenAddressWordIsCanonical]: ./safeReadAddress.t.sol#L76
[test_whenCallReverts]: ./safeReadAddress.t.sol#L36
[test_whenTargetHasNoCode]: ./safeReadAddress.t.sol#L28
