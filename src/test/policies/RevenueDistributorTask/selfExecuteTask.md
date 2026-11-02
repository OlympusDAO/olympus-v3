# selfExecuteTask scenario plan

Source: [RevenueDistributorTask](../../../policies/RevenueDistributorTask.sol).

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

Independently fuzz each local/distributor lifecycle flag and guarantee all sixteen boolean combinations with deterministic seeds. The caller remains external in every case; only the caller identity affects this boundary. Seed Admin, Heart, Revenue Distributor Admin, Emergency, RD and zero without authorizing self impersonation.

| ID | Caller | Local active | Local enabled | Distributor active | Distributor enabled | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SELF-A01 | Fuzz caller excluding only this Task; seed every role-bearing identity listed above | Independently fuzz false/true | Independently fuzz false/true | Independently fuzz false/true | Independently fuzz false/true | RevenueDistributorTask_OnlySelf() before dependency or lifecycle reads | No distributor getter, token transfer, cursor change or committed logs | Covered: [test][test_whenExternalCallerExecutesTaskDirectly_reverts], [test][test_givenExternalCallerAndLifecycleSeeds_reverts] |

Retired SELF-A02 through SELF-A16 are subsumed by SELF-A01 without dropping any lifecycle combination. Their existing test comments remain historical mappings until test implementation updates the reciprocal annotations.

[test_whenExternalCallerExecutesTaskDirectly_reverts]: ./selfExecuteTask.t.sol#L9

[test_givenExternalCallerAndLifecycleSeeds_reverts]: ./selfExecuteTask.t.sol#L49
