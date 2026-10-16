# BurnerLoansYieldClaimer.selfExecuteTask coverage plan

Scope: public boundary of `selfExecuteTask`; traversal outcomes belong to [execute](./execute.md).

## Domains and assertions

Only `msg.sender == address(YieldClaimer)` is permitted. Admin, Heart, Burner Loans Admin, and
Emergency roles do not authorize a direct call. In production, only `execute` can create the
required sender through its external self-call. Unauthorized calls do not read the registry or
change the cursor.

## Authorization

| ID | Caller | Task Kernel state | Task local state | Target state | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SELF-A01 | Any external caller, fuzz; seed every task role and Burner Loans | Active or inactive | Enabled or disabled | Active or inactive | `BurnerLoansYieldClaimer_OnlySelf()` | Unchanged; no event | Covered: [fuzz][test_whenExternalCallerExecutesTaskDirectly_reverts], [roles][test_whenRoleBearingExternalCallerExecutesTaskDirectly_reverts] |
| SELF-P01 | Yield Claimer itself | Active or inactive | Enabled or disabled | Active and enabled | Task body executes | Registered asset is claimed; cursor progresses independently of the outer task's lifecycle gates | Covered: [test][test_givenCallerIsSelf_executesTask] |

[test_whenExternalCallerExecutesTaskDirectly_reverts]: ./selfExecuteTask.t.sol#L14
[test_whenRoleBearingExternalCallerExecutesTaskDirectly_reverts]: ./selfExecuteTask.t.sol#L31
[test_givenCallerIsSelf_executesTask]: ./selfExecuteTask.t.sol#L47
