# Deposit Manager

## Purpose

`DepositManager` provides shared collateral custody for protocol policies. A deposit operator accepts
user instructions, calls DepositManager, and receives receipt-token credit representing the user's
underlying-denominated claim. Assets held at rest may remain as the underlying ERC-20 or be deposited
through one immutable vault entry point configured during asset onboarding. The vault's ERC-20 share
token may be the vault itself or a distinct ERC-7575 token.

Each operator has an isolated accounting namespace. One operator cannot spend another operator's
receipt tokens, liabilities, deposited shares, borrowed balance, or claimable yield.

## Versions And Interfaces

V1 remains the compatibility surface. Its deposit, withdrawal, yield, and borrowing requests and
return values are denominated in the configured underlying asset. V1 withdrawals synchronously
redeem vault shares when the asset has a vault.

V1.1 adds token-aware withdrawal overloads. Their boolean selects either synchronous underlying
output or direct share-token output. All requested amounts and accounting remain denominated in the
underlying asset; only `amountOut` changes denomination when `tokenOut` is the configured share
token.

## Asset And Period Configuration

An asset configuration contains:

- An immutable underlying asset and optional immutable vault entry point.
- An immutable share token discovered at onboarding. Idle assets use the underlying token for
    one-to-one share accounting, standard ERC-4626 vaults use the vault token, and ERC-7575 vaults
    use the token returned by `share()`.
- An explicit share-withdrawal requirement for non-standard vaults that restrict synchronous
    redemption without advertising ERC-7540 asynchronous redemption.
- A shared deposit cap measured in underlying-asset units. It limits aggregate credited principal
    for the asset across every operator and deposit period. A zero cap prevents positive-credit
    deposits.
- A minimum single-deposit amount measured in underlying-asset units. Zero disables the minimum.

Every supported operator also needs an asset-period entry identified by
`(asset, depositPeriod, operator)`. Adding the entry creates its receipt token and initially enables
the period. Disabling a period prevents new deposits but does not delete accounting or receipt-token
metadata.

The vault and share-token pairing cannot be replaced. DepositManager reads ERC-7575 `share()` once
at onboarding and then uses the stored share token for accounting, custody, and share withdrawals. A
vault whose share identity can change is unsupported; replacing that identity requires vault-specific
recovery or a new DepositManager deployment.

## Supported Custody Configurations

DepositManager validates the vault class and resolves its share token when `addAsset` is called.
Asynchronous deposits are rejected during onboarding. The redemption capability is read live for
valuation and explicit withdrawal-mode validation because a vault may change between synchronous
and asynchronous redemption. Share-token identity is not read live.

| Custody configuration                                 | Admission requirements                                            | Stored share token                | Underlying withdrawal                          | Share withdrawal                                           |
| ----------------------------------------------------- | ----------------------------------------------------------------- | --------------------------------- | ---------------------------------------------- | ---------------------------------------------------------- |
| Idle ERC-20                                           | `vault == address(0)`                                             | Underlying asset                  | Supported                                      | Unsupported; a vault is required                           |
| Standard ERC-4626                                     | `vault.asset() == asset`                                          | Vault token                       | Supported while redemption is synchronous      | Supported                                                  |
| ERC-4626 + ERC-7575, `share() == vault`               | Valid ERC-7575 interface and ERC-20 share token                   | Vault token                       | Supported while redemption is synchronous      | Supported                                                  |
| ERC-4626 + ERC-7575, external `share()`               | Valid ERC-7575 interface and ERC-20 share token                   | `share()` token                   | Supported while redemption is synchronous      | Supported                                                  |
| sUSDe with cooldown enabled                           | V1.1 onboarding with explicit share-withdrawal requirement        | sUSDe                             | Rejected by DepositManager                     | Supported; `withdrawAsShares = true` is required           |
| ERC-7540 synchronous deposit, asynchronous redemption | ERC-7575 and ERC-7540 operator support                            | `share()` token                   | Rejected while redemption is asynchronous      | Supported; Burner Loans requires `withdrawAsShares = true` |
| ERC-7540 asynchronous deposit at onboarding           | Rejected; DepositManager does not implement the request lifecycle | Not configured                    | Unsupported                                    | Unsupported                                                |
| Configured vault later enables asynchronous deposits  | Preview and synchronous deposit calls are expected to revert      | Existing immutable share token    | Determined by the live redemption capability   | Supported when the share token remains transferable        |
| Non-standard restricted-redemption vault              | Governance explicitly requires share withdrawal                   | Vault token or ERC-7575 `share()` | Rejected while the explicit requirement is set | Supported if synchronous deposits and share transfers work |

DepositManager cannot infer non-standard redemption restrictions from ERC-4626 alone. Governance
must use the V1.1 `addAsset(..., requiresShareWithdrawal)` overload for initial onboarding and the
DepositManagerConfigTimelock's `queueSetAssetShareWithdrawalRequired` function for later changes to
vaults such as sUSDe. This explicit setting is safer and more general than an address whitelist: it
is part of the asset configuration, works for future vaults, and can be cleared after the timelock
delay if synchronous redemption becomes available. Standards-compliant ERC-7540 asynchronous
redemption is detected live and requires share output even when the explicit setting is false.

The token transferred by a withdrawal is independent of the requested amount's denomination:

| Requested output                        | Idle custody     | ERC-4626 or ERC-7575 self-share   | ERC-7575 external share                   |
| --------------------------------------- | ---------------- | --------------------------------- | ----------------------------------------- |
| Underlying (`withdrawAsShares = false`) | Underlying asset | Underlying asset after redemption | Underlying asset after redemption         |
| Shares (`withdrawAsShares = true`)      | Unsupported      | Vault token                       | Token returned by `share()` at onboarding |

## Access Control

Roles, administrative boundaries, lifecycle gates, and timelock pause behavior are documented in
[Deposit Manager Access Control](deposit_manager_access_control.md).

## Deposits And Receipt Credit

`deposit` transfers the underlying asset from the depositor and verifies exact receipt, rejecting
fee-on-transfer behavior at the custody boundary. With no vault, the received asset amount is both
the custody quantity and receipt credit. DepositManager rejects advertised ERC-7540 asynchronous
deposit support at onboarding. For every vault deposit, DepositManager requires the configured
share-token balance to increase by exactly the nonzero share amount reported by the vault. A
configured vault is responsible for consuming the approved underlying amount according to ERC-4626.
If a configured vault later enables asynchronous deposits, its synchronous `deposit` entry point is
expected to revert. The authoritative returned `actualAmount` is the underlying-denominated credit
calculated from the received custody after the vault interaction.

The asset deposit cap applies to that authoritative credit, not the raw token input or current
custody balance. Principal continues consuming capacity while it is lent out because it remains an
outstanding depositor claim. Receipt-backed withdrawals and borrowing defaults release capacity;
borrowing withdrawals, repayments, yield claims, rescue operations, and receipt wrapping do not.
Governance may lower a cap below current utilization without forcing withdrawals or defaults. In
that state, positive-credit deposits remain blocked until utilization falls within the cap.

Share-to-asset accounting uses `previewRedeem` when redemption is synchronous. A standards-compliant
ERC-7540 vault requires that preview to revert while redemption is asynchronous, so DepositManager
uses `convertToAssets` in that live state for custody accounting. Share-output previews return the
raw `convertToShares` result. Underlying-output previews and executions reject assets that require
share withdrawal.

The receipt token may be held in ERC-6909 form or wrapped as an ERC-20. Withdrawal and default paths
enforce the applicable ownership, approval, and balance requirements through ReceiptTokenManager.

`previewDeposit` is a current-state conversion and cap-headroom estimate. A positive estimated
credit reverts when it exceeds the asset's current aggregate headroom; a zero-credit estimate
returns zero. The preview does not reserve capacity. Vault state, the cap, or aggregate utilization
can change before execution, so the value and cap check from a successful deposit are authoritative.

## Withdrawals

Every withdrawal request is denominated in the underlying asset and reduces the corresponding
underlying-denominated liability. The operator must remain solvent after the change.

V1 withdrawals and V1.1 underlying mode require synchronous vault redemption. DepositManager rejects
underlying mode before receipt or borrowing accounting changes when the asset has an explicit
share-withdrawal requirement or its vault currently advertises ERC-7540 asynchronous redemption.
Otherwise, it converts the requested asset amount to shares, rounds down, and redeems those shares;
the underlying amount delivered may therefore be less than the requested amount. If an unmarked
non-standard vault changes behavior without advertising ERC-7540, its native redemption error is the
fallback. Correctly marking that vault is an integration requirement.

V1.1 share mode supports those asynchronous-withdrawal vaults by using the vault's assets-to-shares
conversion and rounding down. DepositManager transfers the resulting configured share token directly
without attempting redemption and returns `(shareToken, sharesOut)`. Conversion calls target the
vault even when ERC-7575 separates the share token from it. Different underlying and share-token
decimals are therefore handled by the vault without manual normalization. The share token must be
freely transferable and deliver the nominal amount.

A normal positive withdrawal that rounds to zero shares can still consume receipt credit and reduce
liability. The token-aware V1.1 withdrawal event is emitted with the configured share token as
`tokenOut` and zero
`amountOut`, making the completed accounting transition observable even though no shares move.
Integrating policies should reject that result for voluntary user withdrawals when zero delivery is
unacceptable. Burner Loans does so atomically.

`previewWithdraw` returns the current expected token and quantity. It does not validate permissions,
receipt ownership, solvency, balances, or enabled state. It does validate the selected output mode:
underlying preview reverts when the asset explicitly requires share withdrawal or the vault currently
advertises ERC-7540 asynchronous redemption. A successful preview remains a conversion estimate;
later vault state can still make execution revert.

## Yield Claims

Claimable yield is the operator's deposited assets plus outstanding borrowed amount minus its
underlying-denominated liabilities. `maxClaimYield` is a theoretical current-state maximum and may
not be exactly deliverable because of vault rounding or restrictions.

V1 claims yield in underlying assets. V1.1 can transfer shares instead. A positive claim that
converts to zero output is a no-op for accounting and transfers. DepositManager still emits the
mode-appropriate withdrawal and claim events with zero output. Repeated calls cannot consume
protocol value and only cost the caller gas.

## Borrowing

`borrowingWithdraw` moves custody out without burning receipt tokens and records an
underlying-denominated borrowed balance. Capacity is bounded by custody and operator solvency. V1.1
share mode reverts atomically when a positive request converts to zero output.

`borrowingRepay` returns underlying assets to custody, deposits them into the configured vault when
applicable, and reduces the borrowed balance by the actual credited amount. `borrowingDefault` burns
receipt credit and reduces both liabilities and borrowed accounting without requiring an outgoing
asset transfer. Repayment and default remain underlying-denominated and are unchanged by share mode.

## Events And Return Values

Underlying-mode calls retain the V1 events and return values. Share-mode calls emit the V1.1
token-aware event instead of also emitting a duplicate legacy event. The event records the requested
underlying amount, output token, and actual output-token quantity.

Callers must use the returned `tokenOut` and `amountOut` as the authoritative delivered token and
quantity. They should not infer share decimals from underlying-asset decimals.

## Safety Assumptions

- Assets must transfer exactly into DepositManager. Fee-on-transfer and rebasing semantics are not
    supported custody assumptions.
- ERC-4626 vault value is assumed not to decrease unexpectedly. Vault loss can make an operator
    insolvent.
- Share output requires a configured vault with composable, exactly transferable ERC-20 shares.
- Asynchronous deposits are rejected at onboarding. If a configured vault later enables them,
    previews and synchronous deposit calls are expected to return the vault's native
    asynchronous-deposit error. Existing custody remains serviceable. Synchronous deposits plus
    asynchronous redemption are supported only through share output.
- Output-token identity is immutable after onboarding. A later change to ERC-7575 `share()` is not
    followed. Asset, vault, and external share-token identities must be disjoint across configured
    custody routes so physical balances cannot be attributed ambiguously.
- Asynchronous redemption is intentionally handled outside DepositManager after share delivery.
    Managing request IDs, maturity, cancellation, partial fills, and venue-specific claim APIs inside
    shared custody would add a second asynchronous state machine and couple DepositManager to
    non-standard vault implementations.
- State-changing custody, withdrawal, yield, and borrowing entrypoints use transaction-scoped
    reentrancy protection.

## V1.0 To V1.1 Changelog

V1.1 preserves every V1 function selector and adds:

- `withdraw(WithdrawParams,bool)`, returning `(tokenOut, amountOut)`.
- `claimYield(IERC20,address,uint256,bool)`, returning `(tokenOut, amountOut)`.
- `borrowingWithdraw(BorrowingWithdrawParams,bool)`, returning `(tokenOut, amountOut)`.
- `previewDeposit(IERC20,uint256)` and `previewWithdraw(IERC20,uint256,bool)` conversion previews.
- The separate `IAssetManagerV1_1` surface adds `getAssetWithdrawalToken(IERC20,bool)`,
    `getAssetDepositCapStatus(IERC20)`, `isAssetShareWithdrawalRequired(IERC20)`,
    `validateAssetWithdrawAsShares(IERC20,bool)`, and
    `validateAssetShareWithdrawalRequired(IERC20,bool)` without changing the V1 asset configuration
    struct. Deposit-cap utilization is aggregate credited principal across all operators and remains
    consumed while principal is lent out.
- A V1.1 `addAsset` overload configures the initial requirement for non-standard vaults whose
    synchronous-redemption restriction cannot be discovered through ERC-7540. Later
    `setAssetShareWithdrawalRequired` changes may be applied by admin or the config operator; the
    DepositManagerConfigTimelock is the normal config-operator route.
- ERC-7575 discovery for self-share and distinct-share vaults.
- ERC-7540 capability routing: asynchronous deposits are rejected at onboarding, synchronous
    redemption accounting uses `previewRedeem`, and asynchronous redemption accounting uses
    `convertToAssets`.
- Configuration-time and runtime-preview rejection of underlying output while a standards-compliant
    asynchronous capability or explicit share-withdrawal requirement is active.
- Token-aware share-withdrawal, yield-claim, and borrowing-withdrawal events.
- Explicit zero-output behavior for voluntary withdrawals, borrowing, yield claims, and seizure
    integrations.
- Recipient validation and transaction-scoped reentrancy protection on the affected entrypoints.
- `PolicyEnablerV2` bounded `reEnable` support and configurable grace period.
- A single-step config operator and separate DepositManagerConfigTimelock for delayed cap, minimum,
    and asset-period changes.
- `deposit_manager_admin` and `emergency` authority separation, with structural registration kept
    admin-only.
- Kernel-activity checks on DepositManagerConfigTimelock queue and execution paths.

V1.1 does not add asynchronous redemption requests. It delivers transferable vault shares so the
recipient can use the vault-specific asynchronous redemption flow independently.
