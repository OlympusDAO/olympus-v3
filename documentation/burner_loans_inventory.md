# Burner Loans Inventory

## Purpose

`BurnerLoansInventory` holds OHM funding and records provider claims, supplied idle OHM, active principal and the global debt cap. Core settles each loan operation against FLOAN and Inventory in one transaction.

Inventory's Core and OHM identities are immutable. Its local config operator controls surplus recovery alongside ADMIN. That delegation does not grant control over the global cap or provider funds.

## Relationships

| Caller | Operations |
| --- | --- |
| Immutable Core | `draw`, `settleRepayment`, `settleDefault` |
| Provider-role holder | `supply`, withdrawal of its available provider claim |
| ADMIN | Global-cap changes and local config-operator rotation |
| `burner_loans_admin` | `syncMintApproval` |
| ADMIN or local config operator | `burnSurplus`, `rescueSurplus` |

Core's config-operator handoff does not change Inventory's recovery operator. Config does not forward global-cap changes: ADMIN calls Inventory directly.

MINTR supplies mint/burn authority. Inventory checks that MINTR's OHM identity matches its own. A module upgrade with another token is incompatible.

## State

| Quantity | Meaning |
| --- | --- |
| `globalDebtCapOhm` | Maximum active principal, in OHM decimals |
| `activePrincipalOhm` | Outstanding principal settled through this Inventory |
| `suppliedOhm` | Aggregate provider claim, including supplied OHM currently lent or defaulted |
| `providerClaimOhm(provider)` | One provider's remaining claim |
| `suppliedIdleOhm` | Claim-backed OHM held and available for draws or provider withdrawal |
| Actual MINTR approval | OHM that MINTR can still mint for Inventory |

Default reduces principal without reducing provider claims or creating idle OHM. Repayment restores idle backing for the provider claim before any excess is burned.

## Capacity and invariants

```text
remainingCapOhm = globalDebtCapOhm - activePrincipalOhm
desiredApproval = max(remainingCapOhm - suppliedIdleOhm, 0)
availableCapacity = min(suppliedIdleOhm + actualApproval, remainingCapOhm)
```

| Invariant | Consequence |
| --- | --- |
| `activePrincipalOhm <= globalDebtCapOhm` | Funding cannot exceed the global active-debt cap |
| `actualApproval <= desiredApproval` after successful reconciliation | Idle provider funds and mint authority are not double-counted |
| `suppliedIdleOhm <= suppliedOhm` | Accounted idle funds do not exceed provider claims |
| `suppliedIdleOhm <= OHM.balanceOf(Inventory)` | Accounted idle funds remain backed |
| Inventory principal equals Core's canonical FLOAN principal after settlement | Loan and funding accounting change together |

The cap limits debt, not custody. Supplied idle OHM can exceed the cap. The capacity calculation prevents drawing that excess.

A direct donation creates surplus. It does not create provider claims, supplied idle OHM or lending capacity.

## State transitions

| Action | Principal | Supplied idle | Provider claim | Other effects |
| --- | --- | --- | --- | --- |
| Supply `x` | Unchanged | `+x` | Caller and aggregate `+x` | Exact incoming receipt; reduce unsafe approval |
| Withdraw `x` | Unchanged | `-x` | Caller and aggregate `-x` | Transfer OHM; attempt approval restoration |
| Draw `x` | `+x` | Consume idle first | Unchanged | Mint the shortfall; transfer the full draw once |
| Repay `x` | `-x` | Restore claim backing first | Unchanged | Burn the remainder; failed burn becomes surplus |
| Default `x` | `-x` | Unchanged | Unchanged | Attempt approval restoration |
| Change cap | Unchanged | Unchanged | Unchanged | Reconcile approval exactly or revert |

Supply and repayment require exact incoming OHM. Outgoing transfers use SafeERC20 and the protocol's admitted-token assumptions. A provider can withdraw only its available claim backed by supplied idle OHM.

## Operating states

Inventory must be Kernel-active for its mutations. Funding, settlement, provider withdrawals, approval synchronization, surplus burning and cap changes also require local enablement.

Surplus rescue and recovery-operator rotation permit local disablement. They still require Inventory activity and cannot interrupt Core settlement. Surplus recovery preserves supplied idle OHM.

Inventory can enable without a selected recovery operator. It does not require Core's or that operator's local enablement. Core checks its own downstream services separately.

## MINTR failure semantics

Approval reductions protect the cap and must succeed. Failure reverts the transition.

Approval increases restore available capacity. Failure emits `ApprovalRestorationFailed` and leaves less capacity than permitted. It does not undo a provider withdrawal, repayment or default. The operational administrator can retry `syncMintApproval` while Inventory is active and enabled.

A repayment burn failure emits `OhmBurnFailed` without undoing settlement. The unburned OHM remains surplus. ADMIN or the local recovery operator can retry burning while enabled, or rescue surplus to Treasury while locally disabled.

Synchronization cannot exceed the desired approval. A manual approval reduction is not persistent configuration: later transitions can restore approval. Use the debt cap or pause when a restriction must persist.

## Deployment

Enable Inventory before selecting it on Core. Set the global cap directly as ADMIN while Inventory is active and enabled. See the [system deployment order](burner_loans.md#deployment-and-activation).

## Replacement

Core's pointer setter checks the candidate's service interfaces, Core/Kernel/OHM identity, activity and enablement. Candidate principal must equal canonical FLOAN debt. When an old Inventory is selected, old and new active principal and aggregate provider claims must match.

Those checks permit prepared matching nonzero ledgers. They do not transfer OHM, copy individual provider claims, reconcile provider identities or prove that a migration is complete. The prepared-ledger acceptance tests are not a production migration mechanism.

Inventory has no export/import or recapitalization API. The supported rollout procedure is to settle loans and withdraw provider funding before replacing an empty ledger. A nonzero-ledger replacement needs a separately reviewed migration design and complete provider/custody reconciliation.

Default losses remain owed to providers. Supplying 100 OHM and defaulting 100 can leave a 100 OHM claim with zero active principal and idle funding. A donation alone does not replenish the supplied-idle ledger or erase that claim.

Claim-free surplus can be burned or rescued separately. A zero raw token balance is not itself a pointer-replacement requirement. Core's pointer change does not disable or retire the old Inventory.

### Delayed surplus recovery

`BurnerLoansInventoryConfigTimelock` can be selected as Inventory's independent config operator. ADMIN or `burner_loans_admin` can propose `queueBurnSurplus` or `queueRescueSurplus`. The queue must be active/enabled and Inventory active in the same Kernel. Core settlement must be idle when the Inventory operation runs.

Burning requires Inventory locally enabled. Rescue permits a local Inventory pause. Emergency cancellation requires the queue Kernel-active, permits a local queue pause and does not depend on Inventory readiness. Pointer/controller drift and stale commitments prevent unintended execution. See the [queue authority matrix](burner_loans_access_control.md#config-timelock-matrix).
