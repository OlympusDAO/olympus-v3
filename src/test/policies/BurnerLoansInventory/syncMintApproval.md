# BurnerLoansInventory.syncMintApproval coverage plan

Source: [syncMintApproval](../../../policies/burnerloans/BurnerLoansInventory.sol#L372). Coverage is recorded in the Test column with reciprocal scenario IDs in the linked tests.

## Domains and notation

Scenario scope: `BLINV-MINT-APPROVAL` identifies this contract/function.

Own-policy admission: require Kernel-active BurnerLoansInventory; own inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansInventory)` before body/input/idempotent work. Apply existing reentrancy guards, own Kernel activity, required local enablement, then caller authorization. Successful body scenarios assume Local active=true, except explicit admission failures.

Immediate BURNER_LOANS_ADMIN_ROLE-only repair while enabled; ADMIN alone without that role rejects. Inputs none. No Inventory timelock queue is involved: this function only reconciles approval to the already-authorized cap-derived target and cannot increase the debt cap. Use shared numerical/custody definitions.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Accounting and interaction setup

OHM state in uint128: cap C, active principal P, supplied claims S, supplied idle J, claims per provider. Desired MINTR approval=max(C−P−J,0) using widened sum. Available capacity=min(C−P,J+actual mint approval); donated surplus does not become supplied idle. Preserve S=sum provider claims, J<=S, P<=C and OHM balance>=J. Default never reduces provider claim. Burn/approval restoration failure can leave recoverable surplus/approval deficit.

Numeric input seed0,1,MAX128 plus exact principal/cap/claim/idle/deficit/desired limits and neighbors. Address equalities include provider=recipient, distinct recipient, zero recipient and recipient=Inventory; derive actual outgoing behavior, no invented self-recipient ban. Callbacks through MINTR or token must attempt an authorized nested Inventory mutation; caught/propagated outcomes differ. A Core guard also covers Inventory callbacks during Core settlement. Unrelated providers/assets/Core loan state remains unchanged on standalone funding operations.

## Authorization

Fixed for this table: Accounting / events: No state/balance/event.

| ID | Caller | Inputs / competing fault | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLINV-MINT-APPROVAL-A01 | Fuzz callers excluding every BURNER_LOANS_ADMIN_ROLE holder | Local enabled=true; no function arguments | `ROLES_RequireRole(BURNER_LOANS_ADMIN_ROLE)` | Covered: [test_givenUnauthorizedCaller_reverts][test_givenUnauthorizedCaller_reverts] |

## Lifecycle

Kernel membership and local enablement vary independently. Cached ROLES and required modules are configured; no Inventory operation is already executing. Successful cases use the authorized caller shown and otherwise-valid inputs. Core lifecycle does not gate Inventory's independent funding/accounting service. Restore membership and retry an activity rejection without changing the position/claim inputs.

| ID | Caller | Local active | Local enabled | History / inputs | Execution | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLINV-MINT-APPROVAL-L01 | BURNER_LOANS_ADMIN_ROLE holder | true | false | No function arguments | NotEnabled() | Unchanged; rejects before caller and body validation | Covered: [test_givenPausedInventory_whenAction_reverts][test_givenPausedInventory_whenAction_reverts]; [test_whenActionLifecycleSeeds][test_whenActionLifecycleSeeds] |
| BLINV-MINT-APPROVAL-L02 | BURNER_LOANS_ADMIN_ROLE holder | true | true | Otherwise-valid operation; positive work | Success | Return desired approval; reconcile MINTR approval exactly; MintApprovalSynchronized; balances, principal and claims unchanged | Covered: [test_givenConservativeDeficit_restoresDesiredApproval][test_givenConservativeDeficit_restoresDesiredApproval] |
| BLINV-MINT-APPROVAL-L03 | BURNER_LOANS_ADMIN_ROLE holder | false | false | Previously activated then deactivated; cached ROLES retained; valid operation | BurnerLoans_PolicyNotActive(BurnerLoansInventory) | Unchanged; own activity precedes local pause, caller and inputs | Covered: [test_givenInactiveDisabledInventory_whenAction_reverts][test_givenInactiveDisabledInventory_whenAction_reverts]; [test_whenActionLifecycleSeeds][test_whenActionLifecycleSeeds] |
| BLINV-MINT-APPROVAL-P03 | BURNER_LOANS_ADMIN_ROLE holder | false | true | Previously activated then Kernel-deactivated; cached ROLES retained; valid operation | BurnerLoans_PolicyNotActive(BurnerLoansInventory) | Unchanged; no token/module writes or committed logs | Covered: [test_givenInactiveEnabledInventory_whenAction_reverts][test_givenInactiveEnabledInventory_whenAction_reverts] |
| BLINV-MINT-APPROVAL-L04 | BURNER_LOANS_ADMIN_ROLE holder | true | true | Disable then permitted reEnable within grace; restore readiness before invoking the action | Success | Return desired approval; reconcile MINTR approval exactly; MintApprovalSynchronized; balances, principal and claims unchanged | Covered: [test_givenReEnabledInventory_whenAction_succeeds][test_givenReEnabledInventory_whenAction_succeeds] |

## Numeric boundaries and reconciliation

Inventory active/enabled, authorized Burner Loans admin, valid modules. Ordinary rows use a desired approval of 100e9 OHM; the cap, principal and idle fixture establishes it independently. No mint/burn or provider/principal accounting change. Every successful call emits MintApprovalSynchronized(desired), including equality.

| ID | Caller | Actual approval | Desired approval | Execution / module interaction | Test |
| --- | --- | --- | --- | --- | --- |
| BLINV-MINT-APPROVAL-N01 | BURNER_LOANS_ADMIN_ROLE holder | 0 | 100e9 | increaseMintApproval by 100e9; return 100e9 | Covered: [test_whenApprovalBoundarySeeds][test_whenApprovalBoundarySeeds] |
| BLINV-MINT-APPROVAL-N02 | BURNER_LOANS_ADMIN_ROLE holder | 100e9-1 | 100e9 | increaseMintApproval by 1; return 100e9 | Covered: [test_whenApprovalBoundarySeeds][test_whenApprovalBoundarySeeds] |
| BLINV-MINT-APPROVAL-N03 | BURNER_LOANS_ADMIN_ROLE holder | 100e9 | 100e9 | No increase/decrease call; return 100e9; still emit synchronization event | Covered: [test_whenApprovalBoundarySeeds][test_whenApprovalBoundarySeeds] |
| BLINV-MINT-APPROVAL-N04 | BURNER_LOANS_ADMIN_ROLE holder | 100e9+1 | 100e9 | decreaseMintApproval by 1; return 100e9 | Covered: [test_whenApprovalBoundarySeeds][test_whenApprovalBoundarySeeds] |
| BLINV-MINT-APPROVAL-N05 | BURNER_LOANS_ADMIN_ROLE holder | MAX256 | 100e9 | decreaseMintApproval by MAX256-100e9; return 100e9; no wraparound | Covered: [test_whenApprovalBoundarySeeds][test_whenApprovalBoundarySeeds] |
| BLINV-MINT-APPROVAL-N06 | BURNER_LOANS_ADMIN_ROLE holder | 0 | 0 | No adjustment call; return 0; still emit synchronization event | Covered: [test_whenApprovalBoundarySeeds][test_whenApprovalBoundarySeeds] |
| BLINV-MINT-APPROVAL-N07 | BURNER_LOANS_ADMIN_ROLE holder | 1 | 0 | decreaseMintApproval by 1; return 0 | Covered: [test_whenApprovalBoundarySeeds][test_whenApprovalBoundarySeeds] |
| BLINV-MINT-APPROVAL-N08 | BURNER_LOANS_ADMIN_ROLE holder | 0 | MAX128 | increaseMintApproval by MAX128; return MAX128 | Covered: [test_whenApprovalBoundarySeeds][test_whenApprovalBoundarySeeds] |

## Atomic rollback

Fixed for this table: Accounting / events: No silent swallowing; safe retained state on failure.

| ID | Caller | Input / pre-state | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLINV-MINT-APPROVAL-P01 | BURNER_LOANS_ADMIN_ROLE holder | Prior caught default/repayment approval failure; actual approval below desired; adjustment now succeeds | Return desired; MintApprovalSynchronized(desired); exact approval restored | Covered: [test_givenCaughtRestorationFailure_whenSyncRetried_succeeds][test_givenCaughtRestorationFailure_whenSyncRetried_succeeds] |
| BLINV-MINT-APPROVAL-P02 | BURNER_LOANS_ADMIN_ROLE holder | Prior caught approval failure; actual approval below desired; configured MINTR adjustment reverts | Exact configured MINTR error; approval and accounting unchanged; no committed sync event | Covered: [test_givenCaughtRestorationFailure_whenSyncFails_reverts][test_givenCaughtRestorationFailure_whenSyncFails_reverts] |

## Shared assertions

Existing Inventory scenario/test formulas inform expectations; do not mirror production logic as the sole assertion. Guarantee boundary seeds and independent actual MINTR approval under/over desired states.

Co-located API assertions: `desiredMintApproval`. These must be asserted independently of the action return value.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

## Validation

The mapped tests run in the focused Inventory suite. [Shared fixtures](BurnerLoansInventoryTest.sol) isolate Core for unit tests; modular tests exercise real Core. The [stateful campaign](BurnerLoansInventory.invariant.t.sol) covers one provider and successful accounting/lifecycle sequences; token failures and multiple providers have focused tests. This is not a repository-wide validation claim.

[test_givenCaughtRestorationFailure_whenSyncFails_reverts]: syncMintApproval.t.sol#L238
[test_givenCaughtRestorationFailure_whenSyncRetried_succeeds]: syncMintApproval.t.sol#L248
[test_givenConservativeDeficit_restoresDesiredApproval]: syncMintApproval.t.sol#L30
[test_givenInactiveEnabledInventory_whenAction_reverts]: syncMintApproval.t.sol#L112
[test_givenPausedInventory_whenAction_reverts]: syncMintApproval.t.sol#L129
[test_givenReEnabledInventory_whenAction_succeeds]: syncMintApproval.t.sol#L150
[test_givenUnauthorizedCaller_reverts]: syncMintApproval.t.sol#L91
[test_whenActionLifecycleSeeds]: syncMintApproval.t.sol#L263
[test_whenApprovalBoundarySeeds]: syncMintApproval.t.sol#L210

[test_givenInactiveDisabledInventory_whenAction_reverts]: syncMintApproval.t.sol#L139
