# setConfigOperator scenarios

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

ADMIN-only rotation requires own activity but permits pause. Zero revokes;
unchanged addresses revert after authorization. No candidate metadata is probed.
Fuzz nonzero addresses across their full range; zero is a separate revocation case.

| ID | Caller | Local active | Local enabled | Oracle active | Oracle enabled | Input/history | Expected execution | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BO-SETCONFIGOPERATOR-01 | ADMIN | true | false/true (read/setup) | N/A | N/A | when Admin Rotates | Success; exact authoritative state/getter assertions | Covered: [test][test_whenAdminRotates] |
| BO-SETCONFIGOPERATOR-02 | Fuzz unauthorized | true | false/true (read/setup) | N/A | N/A | when Unauthorized reverts | ROLES_RequireRole | Covered: [test][test_whenUnauthorized_reverts] |
| BO-SETCONFIGOPERATOR-03 | ADMIN | true | false/true (read/setup) | N/A | N/A | when Unchanged reverts | ConfigOperator_Unchanged | Covered: [test][test_whenUnchanged_reverts] |
| BO-SETCONFIGOPERATOR-04 | ADMIN | false | false/true (read/setup) | N/A | N/A | given Inactive when Rotate reverts | BackingOracle_PolicyNotActive(self) | Covered: [test][test_givenInactive_whenRotate_reverts] |
| BO-SETCONFIGOPERATOR-05 | Selected operator | true | true | N/A | N/A | given Enabled when Operator Writes | Success; exact authoritative state/getter assertions | Covered: [test][test_givenEnabled_whenOperatorWrites] |
| BO-SETCONFIGOPERATOR-06 | ADMIN | true | true | N/A | N/A | given Recovered when Admin Rotates | Success; exact authoritative state/getter assertions | Covered: [test][test_givenRecovered_whenAdminRotates] |

[test_whenAdminRotates]: ./setConfigOperator.t.sol#L15
[test_whenUnauthorized_reverts]: ./setConfigOperator.t.sol#L30
[test_whenUnchanged_reverts]: ./setConfigOperator.t.sol#L38
[test_givenInactive_whenRotate_reverts]: ./setConfigOperator.t.sol#L45
[test_givenEnabled_whenOperatorWrites]: ./setConfigOperator.t.sol#L52
[test_givenRecovered_whenAdminRotates]: ./setConfigOperator.t.sol#L61
