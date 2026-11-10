# setBackingRiskIntegration scenarios

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

Real oracle and separate timelock with real Kernel/ROLES and BurnerLoansRisk.
PRICE is the existing mock module; oracle admission/backing are never mocked.
Risk constructor/setter accept the oracle, direct and delayed writes appear live,
and paused/inactive oracle reads remain usable. Ceil((1e18+1)*1e8/1e18)
=100000001 proves conversion to eight PRICE decimals. Refresh prices after notice.

| ID | Caller | Local active | Local enabled | Oracle active | Oracle enabled | Input/history | Expected execution | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BO-SETBACKINGRISKINTEGRATION-03 | ADMIN | true | false/true (read/setup) | N/A | N/A | when Price Scale Differs rounds Up | Success; exact authoritative state/getter assertions | Covered: [test][test_whenPriceScaleDiffers_roundsUp] |
| BO-SETBACKINGRISKINTEGRATION-01 | ADMIN | true | false/true (read/setup) | N/A | N/A | when Real Oracle Selected | Success; exact authoritative state/getter assertions | Covered: [test][test_whenRealOracleSelected] |
| BO-SETBACKINGRISKINTEGRATION-02 | ADMIN | true | false/true (read/setup) | N/A | N/A | when Real Oracle In Constructor | Success; exact authoritative state/getter assertions | Covered: [test][test_whenRealOracleInConstructor] |

[test_whenPriceScaleDiffers_roundsUp]: ./setBackingRiskIntegration.t.sol#L29
[test_whenRealOracleSelected]: ./setBackingRiskIntegration.t.sol#L48
[test_whenRealOracleInConstructor]: ./setBackingRiskIntegration.t.sol#L89
