# selfExecuteTask scenario plan

Scope: public boundary of RDTask selfExecuteTask; all traversal and distribution outcomes are owned by [execute](./execute.md).

## Domains and assertions

Only msg.sender equal to RDTask is permitted; externally fuzz caller excluding exactly that address.
Admin, Heart and configuration roles do not authorize a direct call. In production, RDTask can
only create this sender through the external self-call in `execute()`. That wrapper calls
`selfExecuteTask()` only while RDTask is Kernel-active and locally enabled, so inactive or disabled
RDTask self-call states are unreachable. Foundry can impersonate RDTask, but such a test would not
represent an executable transaction path.

Unchanged means balances, liabilities, route configuration, membership indexes and lifecycle state
retain their pre-call values; a reverted transaction commits no events. Check exact error data.
Views are permissionless, including while disabled or Kernel-inactive. Unauthorized direct calls
perform no distributor getter or payout. Distributor lifecycle and traversal behavior are exercised
through [execute](./execute.md), the only production caller.

## Authorization

| ID | Caller | Task Kernel | Task local | RD Kernel | RD local | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SELF-A01 | Any external caller, fuzz; seed Admin, Heart, Revenue Distributor Admin, Emergency and RD | Fuzz active/inactive | Fuzz enabled/disabled | Fuzz active/inactive | Fuzz enabled/disabled | RevenueDistributorTask_OnlySelf() | Unchanged | Covered: [fuzz][test_whenExternalCallerExecutesTaskDirectly_reverts], [roles][test_whenRoleBearingExternalCallerExecutesTaskDirectly_reverts] |

[test_whenExternalCallerExecutesTaskDirectly_reverts]: ./selfExecuteTask.t.sol#L9
[test_whenRoleBearingExternalCallerExecutesTaskDirectly_reverts]: ./selfExecuteTask.t.sol#L28
