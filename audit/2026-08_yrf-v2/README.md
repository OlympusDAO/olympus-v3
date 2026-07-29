# Yield Repurchase Facility v2 Audit

## Purpose

Review the rewrite of the Yield Repurchase Facility from a single-asset weekly buyback facility into a multi-asset one, together with the new `BackingOracle` policy and the `YRFTimelock` that owns its operational parameters.

The facility draws yield from a governance-approved whitelist of ERC4626 reserve vaults held by the treasury, spends each asset's share of that yield through daily Bond Protocol SDA markets that buy OHM, and burns the purchased OHM against a treasury withdrawal priced by the backing oracle.

## Design

Key changes from v1.2:

- Multi-asset ERC4626 whitelist, replacing the fixed USDS/sUSDS asset; each asset gets its own market, and assets whose shares cannot be redeemed synchronously (sUSDe) sell the shares directly.
- Per-asset yield split between buybacks and retained backing, replacing the unconditional 100% burn.
- Backing read live from `BackingOracle`, initialized at `$12.04` and replacing the hardcoded `$11.33` constant.
- Non-zero bond-market minimum price anchored to the OHM oracle price, plus a configurable initial discount.
- Governance-controlled Clearinghouse receivables offset and one-way downward yield correction, remediating a reported Cooler v1 receivables-inflation vector.
- Accounting driven by tracked balances rather than raw token balances, closing an OHM-donation inflation vector.
- Mutable teller/auctioneer, and the `IEnabler` lifecycle in place of the bespoke `isShutdown` flag.

Governance authorization is [OIP-194](https://snapshot.box/#/s:olympusdao.eth/proposal/0x5c5a16fefe142bf09bc94814b926204e41b5c58fefc6dfae74ebe7e93b6023cb).

## Scope

Branch: `feat/multi-asset-yrf-updates`

Base commit: `7e72c9a7`. See [scopefile.txt](./scopefile.txt) for the machine-readable list.

### In-Scope Contracts

The contracts in scope for this audit are:

- [src/](../../src)
    - [policies/](../../src/policies)
        - [YieldRepurchaseFacility/](../../src/policies/YieldRepurchaseFacility)
            - [YieldRepurchaseFacilityV2.sol](../../src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityV2.sol)
            - [YRFBondMarketLib.sol](../../src/policies/YieldRepurchaseFacility/YRFBondMarketLib.sol)
            - [YRFClearinghouseLib.sol](../../src/policies/YieldRepurchaseFacility/YRFClearinghouseLib.sol)
            - [YRFTimelock.sol](../../src/policies/YieldRepurchaseFacility/YRFTimelock.sol)
        - [interfaces/YieldRepurchaseFacility/](../../src/policies/interfaces/YieldRepurchaseFacility)
            - [IYieldRepurchaseFacilityV2.sol](../../src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2.sol)
            - [IYRFTimelock.sol](../../src/policies/interfaces/YieldRepurchaseFacility/IYRFTimelock.sol)
        - [BackingOracle.sol](../../src/policies/BackingOracle.sol)
        - [interfaces/IBackingOracle.sol](../../src/policies/interfaces/IBackingOracle.sol)
    - [proposals/](../../src/proposals)
        - [YieldRepurchaseFacilityV2Proposal.sol](../../src/proposals/YieldRepurchaseFacilityV2Proposal.sol)
        - [YieldRepurchaseFacilityV2Activator.sol](../../src/proposals/YieldRepurchaseFacilityV2Activator.sol)
    - [scripts/ops/batches/](../../src/scripts/ops/batches)
        - [YieldRepoV2Install.sol](../../src/scripts/ops/batches/YieldRepoV2Install.sol)

### Out of Scope

- **Shared enabler and timelock bases** — `EnablerV2`, `PolicyEnablerV2`, `ReEnabler`, `ReEnablerGracePeriod`, `PolicyReEnabler`, `TimelockQueue`, `TimelockBatchQueue` and their interfaces. Inherited unmodified by the in-scope policies and covered by the Bridge audit below.
- [YieldRepurchaseFacility.sol](../../src/policies/YieldRepurchaseFacility.sol) — v1.2, shut down by the activation proposal
- `Kernel.sol`, the TRSRY / PRICE / CHREG / ROLES modules, and `Heart.sol` — previously audited, unmodified
- Bond Protocol SDA auctioneer and teller — third-party, unmodified
- The ERC4626 vaults themselves (sUSDS, sUSDe) — third-party

## Previous Audits

**Olympus Bridge (06/2026)** — [report](https://storage.googleapis.com/olympusdao-landing-page-reports/audits/2026-06-Bridge.pdf). Covers the shared enabler lifecycle and timelock-queue bases that `YieldRepurchaseFacilityV2`, `YRFTimelock`, and `BackingOracle` build on. Package: [audit/2026-03_lz-bridge-upgrade](../2026-03_lz-bridge-upgrade/README.md).

## Architecture

```mermaid
flowchart LR
  Heart([Heart]) -->|execute| YRF([YieldRepurchaseFacilityV2])
  TL([YRFTimelock]) -->|queued params| YRF
  BO([BackingOracle]) -.->|backing| YRF
  PRICE[(PRICE)] -.->|OHM price| YRF
  CHREG[(CHREG)] -.->|receivables| YRF
  YRF -->|withdraw shares| TRSRY[(TRSRY)]
  YRF -->|create market| SDA{{Bond SDA}}
  SDA -->|callback: OHM in| YRF
  YRF -->|burn OHM| OHM{{OHM}}
```

## Key Flows

**Weekly reset** (every 21st beat) — re-absorbs facility-held funds into each asset's budget, injects the stored yield projection, projects the next one from the vault conversion rate and (for the backing vault) Clearinghouse interest net of offsets, refreshes snapshots, and prefunds the budget with treasury share withdrawals.

**Daily cycle** (every 3rd beat) — burns accumulated purchased OHM against a fresh backing withdrawal credited to the backing vault's budget, then opens one 24-hour market per enabled asset sized at `weeklyBudgetRemaining / daysRemaining`. Market creation is skipped entirely when the OHM oracle price is zero or below backing; the burn still runs.

**Market pricing** — the market quotes OHM per payout unit, so prices invert the oracle price: the initial price applies the configured discount, and the minimum price corresponds to the undiscounted oracle price, capping payout per OHM. Submission is a `delegatecall` into `YRFBondMarketLib`, so the facility is the market owner and callback.

**Activation** — the one-shot `seedCycle` carries v1.2's epoch position and unspent weekly budget into v2 so the migration does not forfeit a buyback week.

## Access Control

| Role        | Holder             | Reach                                                                                                                                                                             |
| ----------- | ------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `admin`     | OCG timelock       | Structural changes (assets, backing oracle/vault, bond contracts, Clearinghouse offsets and inclusions, `enable`, `seedCycle`), plus a direct path to every operational parameter |
| `yrf_admin` | DAO multisig       | Operational parameters only by queueing on `YRFTimelock` (1-day delay, 3-day execution window, permissionless execution); directly `reEnable` and `rescue`                        |
| `emergency` | Emergency multisig | `disable`, `returnFundsToTreasury`, cancel queued timelock actions                                                                                                                |
| `heart`     | Heart              | `execute`                                                                                                                                                                         |

`BackingOracle` mirrors this: `backing_admin` queues bounded (±10%) backing updates, `admin` may set directly, `emergency` cancels.

## Focus Areas

1. **Budget accounting** — the invariants tying `weeklyBudgetRemaining` to `prefundedShares` / `prefundedReserve` across the weekly re-mark, prefund, redeem, bid, contribution, and bond-callback paths, and whether any of them can double-count yield or over-spend the treasury.
2. **OHM burn accounting** — `OHM.balanceOf(facility) >= _ohmPurchased` must hold across the callback, the pro-rated burn on a short backing withdrawal, `rescue`, and `returnFundsToTreasury`.
3. **Epoch state machine** — `enable`, `reEnable` within the grace window, and the one-shot `seedCycle` all write the epoch counter; check for a sequence that skips or double-runs a weekly reset.
4. **Soft-fail isolation** — per-vault work runs through self-calls whose reverts are caught. Confirm a misbehaving vault or auctioneer cannot stall the heartbeat, and that a caught revert cannot leave partial accounting.
5. **Timelock integrity** — the pre-state hash, the stale-facility guard, and the per-parameter pending slot in `YRFTimelock`, including the batch path.
6. **Donation resistance** — that the tracked-accounting rewrite closes the v1 vectors, and that `rescue` (capped at the excess over tracked, treasury-directed) cannot defund an open market beyond the documented caveat.
7. **Sell-shares assets** — the share-denominated market path for sUSDe, where the oracle price is converted per-share through the vault conversion rate.

## Known Risks

- **Backing is governance-set.** An overstated backing value causes the facility to withdraw more reserve per OHM burned than the OHM is worth. Mitigated by the ±10% per-update bound, the timelock, and the emergency cancel — not by an on-chain solvency check.
- `PRICE.getLastPrice()` **is the stored observation**, refreshed by `Heart.beat()` in the same transaction. Granting the heart role to anything other than the Heart contract would price markets off a stale observation.
- `contribute` **is permissionless and irreversible.** Contributed funds join the facility's tracked pool and cannot be withdrawn by the contributor.
- **Per-asset pausing is timelocked** for `yrf_admin`. The only instant halt is the emergency role disabling the facility as a whole.
