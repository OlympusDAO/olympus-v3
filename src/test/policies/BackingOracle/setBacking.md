# setBacking scenarios

Source: `src/policies/BackingOracle.sol` and inherited framework hooks.

ADMIN = distinct _ADMIN actor; backing_admin = proposer; EMERGENCY = emergency.
Backing is reserve per OHM in 18 decimals; ordinary enabled backing is 100e18.
Reverts preserve authoritative backing, operator selection, action IDs, flags,
payloads and reservations. No token custody or transfers occur. Roles are independent
of Kernel membership and local enablement. Both policies use real Kernel/ROLES.

The oracle starts active and paused. givenEnabled sets backing to 100e18.
givenRecovered enables, pauses, re-enables without payload and deactivates/reactivates. ADMIN
retains direct writes alongside a selected operator; proposer role alone has no
setter authority. Getter/framework queries retain their read/setup semantics.

Numeric bounds: inclusive [90e18,110e18]; exact/adjacent endpoints, zero, one
and MAX256 are seeded. The source floors both bounds: raw backing 19 gives [17,20], since 17.1 and 20.9
round down. Test both exact endpoints and reject adjacent 16/21 with the same
BackingChangeTooLarge(19,new,17,20) data in preflight and execution.
Bounds use 1,000 basis points on a 10,000 scale and full-precision multiplication/division.
Large representable bounds must not fail because an intermediate product exceeds MAX256.
Maximum initial backing still panics because its 110% upper bound cannot fit uint256.

The valid numeric fuzz case independently selects ADMIN or the unprivileged
_CONFIG_OPERATOR, with explicit actor impersonation. Unauthorized caller fuzz selects proposer as operator and excludes both that
operator and ADMIN. Zero remains in the unauthorized caller domain.

`validateSetBacking` is the permissionless preflight for each setter case below.
Its caller is fuzzed independently of value and ADMIN/operator execution authority.
Successful preflight leaves backing unchanged. Lifecycle and numeric failures match
authorized execution exactly; write authorization is deliberately execution-only.

| ID | Caller | Local active | Local enabled | Oracle active | Oracle enabled | Input/history | Preview (`validateSetBacking`) | Expected execution | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BO-SETBACKING-13 | ADMIN | true | true | N/A | N/A | given Recovered when Set | Success; no writes | Success; exact authoritative state/getter assertions | Covered: [test][test_givenRecovered_whenSet] |
| BO-SETBACKING-14 | ADMIN | false | false | N/A | N/A | given Inactive And Disabled when Set reverts | BackingOracle_PolicyNotActive(self) | BackingOracle_PolicyNotActive(self) | Covered: [test][test_givenInactiveAndDisabled_whenSet_reverts] |
| BO-SETBACKING-15 | ADMIN | true | true | N/A | N/A | given One Backing when Same Value | Success; no writes | Success; exact authoritative state/getter assertions | Covered: [test][test_givenOneBacking_whenSameValue] |
| BO-SETBACKING-01 | Fuzz ADMIN / config operator | true | true | N/A | N/A | when Within Bounds | Success; no writes | Success; exact authoritative state/getter assertions | Covered: [test][test_whenWithinBounds] |
| BO-SETBACKING-02 | ADMIN | true | true | N/A | N/A | when Boundary Seeds | Success; no writes | Success; exact authoritative state/getter assertions | Covered: [test][test_whenBoundarySeeds] |
| BO-SETBACKING-03 | ADMIN | true | true | N/A | N/A | when Below Minimum reverts | BackingOracle_BackingChangeTooLarge(current,new,min,max) | BackingOracle_BackingChangeTooLarge(current,new,min,max) | Covered: [test][test_whenBelowMinimum_reverts] |
| BO-SETBACKING-04 | ADMIN | true | true | N/A | N/A | Fuzz [110e18+1,MAX256]; seed 110e18+1 separately | BackingOracle_BackingChangeTooLarge(current,new,min,max) | BackingOracle_BackingChangeTooLarge(current,new,min,max) | Covered: [test][test_whenAboveMaximum_reverts], [adjacent seed][test_whenAdjacentUpper_reverts] |
| BO-SETBACKING-05 | ADMIN | true | true | N/A | N/A | when Type Maximum reverts | BackingOracle_BackingChangeTooLarge(current,new,min,max) | BackingOracle_BackingChangeTooLarge(current,new,min,max) | Covered: [test][test_whenTypeMaximum_reverts] |
| BO-SETBACKING-06 | ADMIN | true | true | N/A | N/A | when Zero reverts | BackingOracle_ZeroBacking | BackingOracle_ZeroBacking | Covered: [test][test_whenZero_reverts] |
| BO-SETBACKING-07 | ADMIN | true | true | N/A | N/A | when One reverts | BackingOracle_BackingChangeTooLarge(current,new,min,max) | BackingOracle_BackingChangeTooLarge(current,new,min,max) | Covered: [test][test_whenOne_reverts] |
| BO-SETBACKING-08 | Fuzz unauthorized | true | true | N/A | N/A | when Unauthorized reverts | Success; no writes (authorization applies only to execution) | NotAuthorised | Covered: [test][test_whenUnauthorized_reverts] |
| BO-SETBACKING-09 | ADMIN | true | false | N/A | N/A | given Disabled when Set reverts | NotEnabled | NotEnabled | Covered: [test][test_givenDisabled_whenSet_reverts] |
| BO-SETBACKING-10 | ADMIN | false | true | N/A | N/A | given Inactive when Set reverts | BackingOracle_PolicyNotActive(self) | BackingOracle_PolicyNotActive(self) | Covered: [test][test_givenInactive_whenSet_reverts] |
| BO-SETBACKING-11 | ADMIN | true | true | N/A | N/A | given Tiny Backing when Lower Bound Rounds Down | Success; no writes | Success; exact authoritative state/getter assertions | Covered: [test][test_givenTinyBacking_whenLowerBoundRoundsDown] |
| BO-SETBACKING-12 | ADMIN | true | true | N/A | N/A | given Maximum Backing when Set panics | Panic 0x11 because computed upper bound exceeds uint256 | Panic 0x11 because computed upper bound exceeds uint256; unchanged backing | Covered: [test][test_givenMaximumBacking_whenSet_panics] |
| BO-SETBACKING-18 | backing_admin (not selected operator) | true | true | N/A | N/A | given Proposer Role Only when Set reverts | Success; no writes (authorization applies only to execution) | NotAuthorised; pending intent/backing preserved | Covered: [test][test_givenProposerRoleOnly_whenSet_reverts] |
| BO-SETBACKING-17 | Former operator | true | true | N/A | N/A | given Former Operator when Set reverts | Success; no writes (authorization applies only to execution) | NotAuthorised; pending intent/backing preserved | Covered: [test][test_givenFormerOperator_whenSet_reverts] |
| BO-SETBACKING-16 | Revoked operator | true | true | N/A | N/A | given Revoked Operator when Set reverts | Success; no writes (authorization applies only to execution) | NotAuthorised; pending intent/backing preserved | Covered: [test][test_givenRevokedOperator_whenSet_reverts] |
| BO-SETBACKING-19 | Fuzz ADMIN / config operator | true | true | N/A | N/A | Current backing 1e76; fuzz new backing in [9e75,11e75] | Success; no writes | Preview and setter succeed with exact value despite overflowing intermediate products | Covered: [large values][test_givenLargeBacking_whenWithinBounds] |
| BO-SETBACKING-20 | ADMIN | true | true | N/A | N/A | Large backing; lower endpoint then upper endpoint of the resulting value | Success; no writes | Inclusive floor-rounded endpoints succeed | Covered: [large boundaries][test_givenLargeBacking_whenBoundarySeeds] |
| BO-SETBACKING-N01 | ADMIN | true | true | N/A | N/A | Current backing 19; new backing 20 (floor of 20.9) | Success; no writes | Store exactly 20; upper endpoint inclusive | Covered: [test][test_givenTinyBacking_whenUpperBoundRoundsDown] |
| BO-SETBACKING-N02 | ADMIN | true | true | N/A | N/A | Current backing 19; new backing 16 (one below floor of 17.1) | BackingChangeTooLarge(19,16,17,20) | Same error; backing stays 19 | Covered: [test][test_givenTinyBacking_whenBelowRoundedMinimum_reverts] |
| BO-SETBACKING-N03 | ADMIN | true | true | N/A | N/A | Current backing 19; new backing 21 (one above floor of 20.9) | BackingChangeTooLarge(19,21,17,20) | Same error; backing stays 19 | Covered: [test][test_givenTinyBacking_whenAboveRoundedMaximum_reverts] |

[test_givenRecovered_whenSet]: ./setBacking.t.sol#L45
[test_givenInactiveAndDisabled_whenSet_reverts]: ./setBacking.t.sol#L53
[test_givenOneBacking_whenSameValue]: ./setBacking.t.sol#L62
[test_whenWithinBounds]: ./setBacking.t.sol#L72
[test_whenBoundarySeeds]: ./setBacking.t.sol#L92
[test_whenBelowMinimum_reverts]: ./setBacking.t.sol#L109
[test_whenAboveMaximum_reverts]: ./setBacking.t.sol#L119
[test_whenTypeMaximum_reverts]: ./setBacking.t.sol#L139
[test_whenZero_reverts]: ./setBacking.t.sol#L148
[test_whenOne_reverts]: ./setBacking.t.sol#L157
[test_whenUnauthorized_reverts]: ./setBacking.t.sol#L166
[test_givenDisabled_whenSet_reverts]: ./setBacking.t.sol#L179
[test_givenInactive_whenSet_reverts]: ./setBacking.t.sol#L188
[test_givenTinyBacking_whenLowerBoundRoundsDown]: ./setBacking.t.sol#L197
[test_givenMaximumBacking_whenSet_panics]: ./setBacking.t.sol#L208
[test_givenProposerRoleOnly_whenSet_reverts]: ./setBacking.t.sol#L220
[test_givenFormerOperator_whenSet_reverts]: ./setBacking.t.sol#L228
[test_givenRevokedOperator_whenSet_reverts]: ./setBacking.t.sol#L240
[test_givenLargeBacking_whenWithinBounds]: ./setBacking.t.sol#L15
[test_givenLargeBacking_whenBoundarySeeds]: ./setBacking.t.sol#L29
[test_whenAdjacentUpper_reverts]: ./setBacking.t.sol#L129
[test_givenTinyBacking_whenUpperBoundRoundsDown]: ./setBacking.t.sol#L252
[test_givenTinyBacking_whenBelowRoundedMinimum_reverts]: ./setBacking.t.sol#L264
[test_givenTinyBacking_whenAboveRoundedMaximum_reverts]: ./setBacking.t.sol#L284
