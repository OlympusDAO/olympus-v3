# BurnerLoansPayout.requestPermissions coverage plan

Source: [requestPermissions](../../../Kernel.sol#L156). Coverage is recorded in the Test column. Apply [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md).

## Domains and behavior

Scenario scope: `BLCU-PERMISSIONS` identifies this contract/function.

Inherited Policy function is permissionless and returns an empty permission array. Payout reads modules and requests no module write permissions.

| ID | Caller | Payout active | Execution / effects | Test |
| --- | --- | --- | --- | --- |
| BLCU-PERMISSIONS-P01 | Fuzz any address | true | Empty array; no accounting, routing or authorization changes | Covered: [test_whenPermissionsRead_thenEmpty][test_whenPermissionsRead_thenEmpty] |
| BLCU-PERMISSIONS-P02 | Fuzz any address | false | Empty array; no accounting, routing or authorization changes | Covered: [test_whenPermissionsRead_thenEmpty][test_whenPermissionsRead_thenEmpty] |

Core enablement/activity does not affect this getter. Verify activation grants no FLOAN/MINTR/TRSRY writes.

- [x] Review expectations before production test implementation.
- [x] Adapt existing Framework/recovery tests and map passing proofs.

[test_whenPermissionsRead_thenEmpty]: ./requestPermissions.t.sol#L10
