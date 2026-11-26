# OperatorAuth `getGrant` scenarios

Source: `src/policies/utils/OperatorAuth.sol`; ABI: `IOperatorAuth`.

This permissionless view selects the current consumer namespace and returns only current-epoch,
unexpired grants. Missing/stale records return an entirely empty struct. No state or logs change.
The harness starts at timestamp 100; deadlines are uint48 compared against full-width time.
Temporary grants exist only within their accepting transaction; reusable grants persist until
expiry, cancellation or replacement. Caller identity does not confer authority through this view.
Using reusable authority does not consume it or change its epochs. A returned record does not prove
that the next operation fits its result bounds or that the consumer is currently operational.

| ID | State / inputs | Return / proof | Effects | Test |
| --- | --- | --- | --- | --- |
| OAGRANT-V01 | Account A approved at deadline 100; read at 101 | Getter returns entirely empty grant; capture reverts OperatorAuth_ExpiredGrant(100) | Read leaves state unchanged | Covered: [test][test_givenExpiredGrant_whenRead_returnsEmpty] |
| OAGRANT-V02 | Fuzz account/operator; no grant | Entirely empty grant | No writes | Covered: [test][test_givenNoGrant_whenRead_returnsEmpty] |
| OAGRANT-V03 | Reusable grant was used, then account-wide cancellation | Entirely empty grant; old stamp rejects InvalidContext | Pair epoch stays one, account epoch becomes one; no getter writes | Covered: [test][test_givenAccountCancelled_whenRead_returnsEmpty] |
| OAGRANT-V04 | Read at deadline equality | Exact live grant | No writes | Covered: [test][test_givenDeadlineEquality_whenRead_returnsLiveGrant] |
| OAGRANT-V05 | Time exceeds uint48 maximum | Entirely empty grant | No writes | Covered: [test][test_givenFullWidthTimeBeyondMaximumDeadline_whenRead_returnsEmpty] |
| OAGRANT-V06 | Live context changes without new grant | Entirely empty grant | No writes | Covered: [test][test_givenDifferentContext_whenRead_returnsEmpty] |
| OAGRANT-V07 | Unused reusable grant; fuzz unrestricted viewer, expiry 101..MAX48 and independent read time 100..expiry-1; seed minimum and maximum expiry | Exact complete grant | One acceptance pair epoch, account epoch zero; getter changes neither | Covered: [fuzz][test_givenReusableGrant_whenReadBeforeUse], [seeds][test_whenReusableGrantReadTimeBoundarySeeds] |
| OAGRANT-V08 | Reusable grant validated for two actions before expiry; same viewer/expiry/read-time fuzz domains and expiry boundary seeds | Same complete grant, permissions and stamp after repeated use | Uses consume no further pair/account epochs | Covered: [fuzz][test_givenReusableGrant_whenReadAfterRepeatedUse], [seeds][test_whenReusableGrantReadTimeBoundarySeeds] |
| OAGRANT-V09 | Reusable grant used at 100 and at inclusive expiry 101; read/use at 102 | Getter entirely empty; old stamp rejects ExpiredGrant(101) | Pair/account epochs remain one/zero | Covered: [test][test_givenUsedReusableGrant_whenDeadlinePasses_returnsEmpty] |
| OAGRANT-V10 | Used reusable grant; account cancels its pair | Getter entirely empty; old stamp rejects InvalidContext | Pair epoch becomes two; account epoch stays zero | Covered: [test][test_givenUsedReusableGrant_whenPairCancelled_returnsEmpty] |
| OAGRANT-V11 | Used reusable grant replaced with different permissions | Exact new grant and permissions; old stamp rejected, new stamp live | Pair epoch becomes two; account epoch stays zero | Covered: [test][test_givenUsedReusableGrant_whenReplaced_returnsReplacement] |
| OATEMP-P06 | Temporary grant read within accepting transaction | Account/operator, mode and permissions returned | No getter writes | Covered: [test][test_givenTemporaryGrant_whenReadInAcceptingTransaction_returnsLiveGrant] |

[test_givenAccountCancelled_whenRead_returnsEmpty]: ./getGrant.t.sol#L154
[test_givenDeadlineEquality_whenRead_returnsLiveGrant]: ./getGrant.t.sol#L231
[test_givenDifferentContext_whenRead_returnsEmpty]: ./getGrant.t.sol#L250
[test_givenExpiredGrant_whenRead_returnsEmpty]: ./getGrant.t.sol#L133
[test_givenFullWidthTimeBeyondMaximumDeadline_whenRead_returnsEmpty]: ./getGrant.t.sol#L243
[test_givenNoGrant_whenRead_returnsEmpty]: ./getGrant.t.sol#L146
[test_givenTemporaryGrant_whenReadInAcceptingTransaction_returnsLiveGrant]: ./getGrant.t.sol#L257
[test_givenReusableGrant_whenReadBeforeUse]: ./getGrant.t.sol#L24
[test_givenReusableGrant_whenReadAfterRepeatedUse]: ./getGrant.t.sol#L45
[test_givenUsedReusableGrant_whenDeadlinePasses_returnsEmpty]: ./getGrant.t.sol#L102
[test_givenUsedReusableGrant_whenPairCancelled_returnsEmpty]: ./getGrant.t.sol#L177
[test_givenUsedReusableGrant_whenReplaced_returnsReplacement]: ./getGrant.t.sol#L196
[test_whenReusableGrantReadTimeBoundarySeeds]: ./getGrant.t.sol#L84
