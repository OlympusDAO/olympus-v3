# Timelock disable scenarios

Source: `src/policies/BackingOracleConfigTimelock.sol`, `PolicyEnablerV2` and
`EnablerV2`. ADMIN and EMERGENCY are distinct actors; backing_admin alone cannot
disable. The fixture starts with an active, enabled queue and a selected oracle.

The enabled-state guard precedes authorization, which precedes the empty-payload
check. Own inactivity and broken target metadata must not prevent an authorized
pause. Successful transitions emit Disabled and Transition with the caller,
direction, empty payload and current timestamp. Pending actions, configuration
commitments, reservations, backing and operator selection remain unchanged.
Failures emit no events and preserve the transition timestamp and all intent.

| ID | Caller | Local active | Local enabled | Input/state | Expected result | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BO-TIMELOCK-DISABLE-01 | Fuzz ADMIN/EMERGENCY, exclusive or overlapping roles | Fuzz false/true | true | Empty data, pending intent, target getters revert | Disable succeeds; exact events/timestamp; intent and backing preserved | Covered: [authorized pause][test_givenPending_whenAuthorized] |
| BO-TIMELOCK-DISABLE-02 | Fuzz all unauthorized callers, including zero | Fuzz false/true | true | Nonempty data | NotAuthorised before payload validation; complete rollback | Covered: [unauthorized][test_whenUnauthorized_reverts] |
| BO-TIMELOCK-DISABLE-03 | Fuzz any caller, including zero | Fuzz false/true | false | Nonempty data | NotEnabled before authorization/payload validation; complete rollback | Covered: [already disabled][test_givenDisabled_whenDisable_reverts] |
| BO-TIMELOCK-DISABLE-04 | Fuzz ADMIN/EMERGENCY | Fuzz false/true | true | Fuzz nonempty data | BackingOracleTimelock_InvalidEnablerData; complete rollback | Covered: [invalid data][test_whenNonemptyData_reverts] |
| BO-TIMELOCK-DISABLE-05 | ADMIN | true | Re-enabled | Empty data, pending intent | Disable succeeds after recovery; pending intent preserved | Covered: [recovered pause][test_givenReEnabled_whenDisable] |

[test_givenPending_whenAuthorized]: ./disable.t.sol#L17
[test_whenUnauthorized_reverts]: ./disable.t.sol#L59
[test_givenDisabled_whenDisable_reverts]: ./disable.t.sol#L81
[test_whenNonemptyData_reverts]: ./disable.t.sol#L107
[test_givenReEnabled_whenDisable]: ./disable.t.sol#L135
