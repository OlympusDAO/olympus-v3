# enable scenarios

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

ADMIN supplies exactly 32-byte ABI data with nonzero backing. Enabler state
precedes authorization, then own activity and payload/value checks. Repeated enable
after pause resets backing and intentionally bypasses per-update bounds; fast reEnable preserves backing.

| ID | Caller | Local active | Local enabled | Oracle active | Oracle enabled | Input/history | Expected execution | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BO-ENABLE-10 | ADMIN | true | false | N/A | N/A | given Reactivated when Enable | Success; exact authoritative state/getter assertions | Covered: [test][test_givenReactivated_whenEnable] |
| BO-ENABLE-01 | ADMIN | true | false | N/A | N/A | when Nonzero | Success; exact authoritative state/getter assertions | Covered: [test][test_whenNonzero] |
| BO-ENABLE-02 | ADMIN | true | false | N/A | N/A | when One | Success; exact authoritative state/getter assertions | Covered: [test][test_whenOne] |
| BO-ENABLE-03 | ADMIN | true | false | N/A | N/A | when Maximum | Success; exact authoritative state/getter assertions | Covered: [test][test_whenMaximum] |
| BO-ENABLE-04 | ADMIN | true | false | N/A | N/A | when Zero reverts | BackingOracle_ZeroBacking | Covered: [test][test_whenZero_reverts] |
| BO-ENABLE-05 | ADMIN | true | false | N/A | N/A | when Malformed reverts | BackingOracle_InvalidEnableDataLength | Covered: [test][test_whenMalformed_reverts] |
| BO-ENABLE-06 | Fuzz unauthorized | true | false | N/A | N/A | when Unauthorized reverts | ROLES_RequireRole | Covered: [test][test_whenUnauthorized_reverts] |
| BO-ENABLE-07 | ADMIN | true | false | N/A | N/A | given Enabled when Enable reverts | NotDisabled | Covered: [test][test_givenEnabled_whenEnable_reverts] |
| BO-ENABLE-08 | ADMIN | false | false | N/A | N/A | given Inactive when Enable reverts | BackingOracle_PolicyNotActive(self) | Covered: [test][test_givenInactive_whenEnable_reverts] |
| BO-ENABLE-09 | ADMIN | true | false | N/A | N/A | given Previously Enabled when Enable Resets Backing | Success; exact authoritative state/getter assertions | Covered: [test][test_givenPreviouslyEnabled_whenEnableResetsBacking] |

[test_givenReactivated_whenEnable]: ./enable.t.sol#L13
[test_whenNonzero]: ./enable.t.sol#L21
[test_whenOne]: ./enable.t.sol#L31
[test_whenMaximum]: ./enable.t.sol#L38
[test_whenZero_reverts]: ./enable.t.sol#L45
[test_whenMalformed_reverts]: ./enable.t.sol#L52
[test_whenUnauthorized_reverts]: ./enable.t.sol#L60
[test_givenEnabled_whenEnable_reverts]: ./enable.t.sol#L68
[test_givenInactive_whenEnable_reverts]: ./enable.t.sol#L75
[test_givenPreviouslyEnabled_whenEnableResetsBacking]: ./enable.t.sol#L82
