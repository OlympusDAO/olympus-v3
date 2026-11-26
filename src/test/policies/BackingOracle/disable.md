# disable scenarios

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

ADMIN or EMERGENCY can pause while own Kernel-inactive. Empty data is required.
Backing and pending intent persist. Already-disabled calls reject before authorization.

| ID | Caller | Local active | Local enabled | Oracle active | Oracle enabled | Input/history | Expected execution | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BO-DISABLE-01 | ADMIN | true | true | N/A | N/A | when Admin Disables | Success; exact authoritative state/getter assertions | Covered: [test][test_whenAdminDisables] |
| BO-DISABLE-02 | EMERGENCY | false | true | N/A | N/A | given Inactive when Emergency Disables | Success; exact authoritative state/getter assertions | Covered: [test][test_givenInactive_whenEmergencyDisables] |
| BO-DISABLE-03 | Fuzz unauthorized | true | true | N/A | N/A | when Unauthorized reverts | NotAuthorised | Covered: [test][test_whenUnauthorized_reverts] |
| BO-DISABLE-04 | ADMIN | true | false/true (read/setup) | N/A | N/A | given Disabled when Disable reverts | NotEnabled | Covered: [test][test_givenDisabled_whenDisable_reverts] |
| BO-DISABLE-05 | ADMIN | true | true | N/A | N/A | when Nonempty Data reverts | BackingOracle_InvalidDisableDataLength | Covered: [test][test_whenNonemptyData_reverts] |

[test_whenAdminDisables]: ./disable.t.sol#L9
[test_givenInactive_whenEmergencyDisables]: ./disable.t.sol#L17
[test_whenUnauthorized_reverts]: ./disable.t.sol#L24
[test_givenDisabled_whenDisable_reverts]: ./disable.t.sol#L32
[test_whenNonemptyData_reverts]: ./disable.t.sol#L39
