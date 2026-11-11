# BurnerLoansYieldClaimerTask.claimYield coverage plan

Source: [claimYield](../../../policies/burnerloans/BurnerLoansYieldClaimerTask.sol#L215). Coverage is recorded in the Test column with passing focused tests and reciprocal scenario comments.

Check the preview in the existing action cases below. Expected behavior remains fixed during implementation; update the Test column as coverage is verified.

## Domains and notation

Scenario scope: `BLYC-CLAIM-YIELD` identifies this contract/function.

Own-policy admission: require Kernel-active BurnerLoansYieldClaimerTask; own inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansYieldClaimerTask)` before body/input/idempotent work. Successful body scenarios assume Local active=true, except explicit admission failures.

Implemented admission: local claimer inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansYieldClaimerTask)`; unavailable Core uses `PolicyDependency_NotActive(Core)`. Local disablement retains `NotEnabled()`. Own-policy activity is checked before local enablement.

Permissionless public caller incl HEART/unrelated. Output mode false uses DM buffered maxClaimYield; shares true request=min(heldAssets,max(heldAssets+borrowed−liabilities,0)). Asset units are underlying; return output may be separate share token with different decimals.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Task interaction setup

Task defaults execution budget constructor-selected; minimumGasToAttempt250000; gasReserve100000; pre-cursor buffer50000. Loop visits <=assetCount attempts; stop if gasleft<=minimum or after asset lookup gasleft<=reserve+50000, without advancing current cursor. Advance cursor BEFORE bounded claim attempt so caught per-asset failure/OOG does not strand traversal. Copies at most4bytes per failure. A later unbounded registry read failure propagates through selftask and rolls back earlier claims/cursor from that selftask; outer execute reports it.

## Authorization

The external caller is permissionless; the Task's own BL_YIELD_CLAIMER_ROLE at Core is a separate settlement prerequisite, not a role required of the external caller. Preview caller and claim caller are independently fuzzed. Role-bearing and ordinary callers receive the same routing behavior.

| ID | Caller | Fixed operation prerequisites | Execution / return | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLYC-CLAIM-YIELD-A01 | Independently fuzz any external caller, including zero, EOAs and contracts, with or without protocol roles | Task/Core active and enabled; registered solvent asset with positive yield; Task holds settlement role | Caller admitted; return independently expected output token and amount | Exact direct delivery to the configured yield recipient; external caller acquires no entitlement from initiating the claim | Covered: [test][test_givenOneUnitYield_whenAnyCallerClaims], [test][test_whenPermissionlessCallerSeeds], [test][test_givenAuthoritativeSettlementOutput_whenClaimed] |

## Lifecycle

Permissionless caller; positive supported yield request, solvent compatible DM/custody, registered market and compatible output mode. Lifecycle axes vary independently. Do not conflate custody support errors with admission. Current validation order is claimer enabled, claimer active, Core active, Core enabled.

| ID | Caller | Local active | Local enabled | Core active | Core enabled | Execution | Effects | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLYC-CLAIM-YIELD-L01 | Fuzz all callers | true | true | true | true | `Claim succeeds` | Exact yield routing; no pending entry | Both follow the same function-specific caller/input validation and quote outcome; no writes | Covered: [test][test_givenOneUnitYield_whenAnyCallerClaims], [test][test_whenPermissionlessCallerSeeds], [test][test_givenReEnabledAndReactivated_whenClaimed] |
| BLYC-CLAIM-YIELD-D01 | Fuzz all callers | true | true | true | false | `PolicyDependency_NotActive(Core)` | Unchanged; no committed claim logs | Same PolicyDependency_NotActive(Core); reject before presenting an executable quote | Covered: [test][test_givenUnavailableCore_whenClaimed_reverts] |
| BLYC-CLAIM-YIELD-D02 | Fuzz all callers | true | true | false | true | `PolicyDependency_NotActive(Core)` | Unchanged; no committed claim logs | Same PolicyDependency_NotActive(Core); reject before presenting an executable quote | Covered: [test][test_givenUnavailableCore_whenClaimed_reverts] |
| BLYC-CLAIM-YIELD-D03 | Fuzz all callers | true | true | false | false | `PolicyDependency_NotActive(Core)` | Unchanged; no committed claim logs | Same PolicyDependency_NotActive(Core); reject before presenting an executable quote | Covered: [test][test_givenUnavailableCore_whenClaimed_reverts] |
| BLYC-CLAIM-YIELD-L02 | Fuzz all callers | true | false | true | true | `NotEnabled()` | Unchanged; no committed claim logs | Same NotEnabled(); reject before presenting an executable quote | Covered: [test][test_givenDisabledTask_whenClaimed_reverts] |
| BLYC-CLAIM-YIELD-L03 | Fuzz all callers | true | false | true | false | `NotEnabled()` | Unchanged; no committed claim logs | Same NotEnabled(); reject before presenting an executable quote | Covered: [test][test_givenDisabledTask_whenClaimed_reverts] |
| BLYC-CLAIM-YIELD-L04 | Fuzz all callers | true | false | false | true | `NotEnabled()` | Unchanged; no committed claim logs | Same NotEnabled(); reject before presenting an executable quote | Covered: [test][test_givenDisabledTask_whenClaimed_reverts] |
| BLYC-CLAIM-YIELD-L05 | Fuzz all callers | true | false | false | false | `NotEnabled()` | Unchanged; no committed claim logs | Same NotEnabled(); reject before presenting an executable quote | Covered: [test][test_givenDisabledTask_whenClaimed_reverts] |
| BLYC-CLAIM-YIELD-L06 | Fuzz all callers | false | true | true | true | `BurnerLoans_PolicyNotActive(BurnerLoansYieldClaimerTask)` | Unchanged; no committed claim logs | Same BurnerLoans_PolicyNotActive(BurnerLoansYieldClaimerTask); reject before presenting an executable quote | Covered: [test][test_givenInactiveTask_whenClaimed_reverts] |
| BLYC-CLAIM-YIELD-L07 | Fuzz all callers | false | true | true | false | `BurnerLoans_PolicyNotActive(BurnerLoansYieldClaimerTask)` | Unchanged; no committed claim logs | Same BurnerLoans_PolicyNotActive(BurnerLoansYieldClaimerTask); reject before presenting an executable quote | Covered: [test][test_givenInactiveTask_whenClaimed_reverts] |
| BLYC-CLAIM-YIELD-L08 | Fuzz all callers | false | true | false | true | `BurnerLoans_PolicyNotActive(BurnerLoansYieldClaimerTask)` | Unchanged; no committed claim logs | Same BurnerLoans_PolicyNotActive(BurnerLoansYieldClaimerTask); reject before presenting an executable quote | Covered: [test][test_givenInactiveTask_whenClaimed_reverts] |
| BLYC-CLAIM-YIELD-L09 | Fuzz all callers | false | true | false | false | `BurnerLoans_PolicyNotActive(BurnerLoansYieldClaimerTask)` | Unchanged; no committed claim logs | Same BurnerLoans_PolicyNotActive(BurnerLoansYieldClaimerTask); reject before presenting an executable quote | Covered: [test][test_givenInactiveTask_whenClaimed_reverts] |
| BLYC-CLAIM-YIELD-L10 | Fuzz all callers | false | false | true | true | `BurnerLoans_PolicyNotActive(BurnerLoansYieldClaimerTask)` | Unchanged; no committed claim logs | Same BurnerLoans_PolicyNotActive(BurnerLoansYieldClaimerTask); reject before presenting an executable quote | Covered: [test][test_givenInactiveDisabledTask_whenClaimed_reverts] |
| BLYC-CLAIM-YIELD-L11 | Fuzz all callers | false | false | true | false | `BurnerLoans_PolicyNotActive(BurnerLoansYieldClaimerTask)` | Unchanged; no committed claim logs | Same BurnerLoans_PolicyNotActive(BurnerLoansYieldClaimerTask); reject before presenting an executable quote | Covered: [test][test_givenInactiveDisabledTask_whenClaimed_reverts] |
| BLYC-CLAIM-YIELD-L12 | Fuzz all callers | false | false | false | true | `BurnerLoans_PolicyNotActive(BurnerLoansYieldClaimerTask)` | Unchanged; no committed claim logs | Same BurnerLoans_PolicyNotActive(BurnerLoansYieldClaimerTask); reject before presenting an executable quote | Covered: [test][test_givenInactiveDisabledTask_whenClaimed_reverts] |
| BLYC-CLAIM-YIELD-L13 | Fuzz all callers | false | false | false | false | `BurnerLoans_PolicyNotActive(BurnerLoansYieldClaimerTask)` | Unchanged; no committed claim logs | Same BurnerLoans_PolicyNotActive(BurnerLoansYieldClaimerTask); reject before presenting an executable quote | Covered: [test][test_givenInactiveDisabledTask_whenClaimed_reverts] |

## Numeric boundaries and arithmetic

Fixed for this table: Accounting / events: No zero-output event; no custody liability change.

| ID | Caller | Numeric input / arithmetic condition | Execution / return | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- |
| BLYC-CLAIM-YIELD-N01 | Fuzz all callers | request positive, output0 due sub-share rounding; repeated calls; later yield growth | Return token,0 allowed then later output transferable | Quote token and zero output successfully, matching the allowed zero-output action; later yield growth changes both quote and claim | Covered: [test][test_givenSubShareSurplus_whenClaimedRepeatedly] |

## Successful execution

| ID | Caller | Operation / pre-state | Execution / return | Accounting / events | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLYC-CLAIM-YIELD-P01 | Fuzz all callers | Custody assets+borrowed<liabilities; other inputs valid | BurnerLoansCore_Insolvent(asset,liabilities,assets,borrowed) | No claim, route delivery or accounting change | Same solvency error and arguments; no writes | Covered: [test][test_givenInsolventCustody_whenClaimed_reverts] |
| BLYC-CLAIM-YIELD-P05 | Fuzz all callers | Custody assets+borrowed=liabilities | Return expected output token and zero amount | No Core settlement or YieldClaimed event | Quote zero; do not reject solvent equality | Covered: [test][test_givenZeroYieldAndRevokedRole_whenClaimed], [test][test_givenDirectCustodyDonation_whenYieldClaimed_thenOperatorSharesBoundOutput] |
| BLYC-CLAIM-YIELD-P06 | Fuzz all callers | Underlying mode; available yield after DepositManager buffer=1 raw unit | Return token and 1 | Direct DepositManager delivery exactly once; liabilities unchanged | Quote exactly 1; no writes | Covered: [test][test_givenOneUnitYield_whenAnyCallerClaims] |
| BLYC-CLAIM-YIELD-P07 | Fuzz all callers | Share mode; positive surplus converting to one output share | Return share token and 1 share | One direct output delivery; native share decimals | Quote exactly 1 share; no writes | Covered: [test][test_givenSubShareSurplus_whenClaimedRepeatedly] |
| BLYC-CLAIM-YIELD-P02 | Fuzz all callers | Zero request; configured withdrawal mode remains supported | Return expected token,0 after live mode validation | No Core call or YieldClaimed event | Same token,0; validate mode before quote | Covered: [test][test_givenZeroYieldAndRevokedRole_whenClaimed], [test][test_givenDirectCustodyDonation_whenYieldClaimed_thenOperatorSharesBoundOutput] |
| BLYC-CLAIM-YIELD-I01 | Fuzz all callers | Zero request; DepositManager now requires shares but configured mode=false | Exact DepositManager unsupported-withdrawal-mode error | No Core call, transfer or logs | Same mode validation error despite zero yield | Covered: [test][test_givenZeroYieldAndUnsupportedMode_whenClaimed_reverts] |
| BLYC-CLAIM-YIELD-P03 | Fuzz all callers | Output direct underlying, vaultshares, ERC7575 external shares same/different decimals; fees flag/Yflag independent | Route by Yflag only to distributor or currentTreasury | Direct DM→recipient; exact positive YieldClaimed at Core; otherasset unaffected | Compare output token/amount in its own decimals and live yield recipient; preview writes nothing; action delivers once directly from DM; fee flag does not change yield route | Covered: [test][test_givenExternalShares_whenClaimed], [test][test_givenUnderlyingOutput_whenYieldRoutingChanges], [test][test_givenVaultShares_whenYieldRoutingChanges], [test][test_givenTreasuryUpgraded_whenClaimed] |
| BLYC-CLAIM-YIELD-P04 | Fuzz all callers | Positive yield request; claimer settlement role revoked | ROLES_RequireRole(BL_YIELD_CLAIMER_ROLE) | No claim or delivery | Same required role rejection before quote | Covered: [test][test_givenPositiveYieldAndRevokedRole_whenClaimed_reverts] |
| BLYC-CLAIM-YIELD-P08 | Fuzz all callers | Zero request; claimer settlement role revoked | Return expected token,0; no settlement needed | No Core settlement or claim event | Quote the same harmless zero result; no settlement-role requirement on zero work | Covered: [test][test_givenZeroYieldAndRevokedRole_whenClaimed] |

## Shared assertions

Port live recipient-change after failed claim, production custody solvency, direct one-unit yield and external share output fixtures. A representative collateral-token callback attempts an otherwise-valid guarded Core action; mandatory transfer failure rolls back the claim. Routing and payout recovery belong to Custody tests. No governance grant to arbitrary public caller.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

## Transfer callbacks and reentrancy

Arm callbacks only after setup. Fund and authorize each nested route so it passes its public caller/input checks and reaches the named guard; a role or allowance failure is not reentrancy proof. Use one representative token-transfer callback, with nonzero pre-existing accounting and an unrelated entity. Read-only callbacks may observe intermediate state and must not be treated as final-accounting assertions. Keep caught and propagated outcomes as separate named tests.

| ID | Outer caller | Callback point | Authorized nested route / handling | Execution | Accounting / rollback | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLYC-CLAIM-YIELD-C01 | Permissionless caller | DM/vault redemption and direct output delivery to Treasury or RevenueDistributor; no Custody yield balance | Otherwise-valid authorized public action reaching guarded Core settlement; callback catches the guard rejection | Nested call rejects ReentrancyGuardReentrantCall(); outer operation succeeds | Claim delivers once to current yield route; no new Custody pending-yield obligation; collateral liabilities unchanged | Quote before arming transfer callback; no token/vault/receipt transfer or callback; caught action agrees under stable economics; propagated execution failure is not predicted | Covered: [test][test_givenCaughtTokenCallback_whenClaimed] |
| BLYC-CLAIM-YIELD-C02 | Permissionless caller | DM/vault redemption and direct output delivery to Treasury or RevenueDistributor; no Custody yield balance | Otherwise-valid authorized public action reaching guarded Core settlement; token propagates the guard rejection | Exact propagated token/dependency error rejects outer operation | Full pre-call rollback of affected positions, debt, claims, token/receipt balances, allowances, reserves, indexes, approvals and committed logs, including earlier subcalls | Quote before arming transfer callback; no token/vault/receipt transfer or callback; caught action agrees under stable economics; propagated execution failure is not predicted | Covered: [test][test_givenPropagatedTokenCallback_whenClaimed_reverts] |

## Additional admission coverage

| ID | Caller | Pre-state | Expected behavior | Test |
| --- | --- | --- | --- | --- |
| BLYC-CLAIM-YIELD-D04 | Fuzz caller | Positive yield; DepositManager Kernel-inactive | PolicyDependency_NotActive(DepositManager) on preview and execution; no settlement | Covered: [test][test_givenPositiveYieldAndDepositManagerInactive_whenClaimed_reverts] |

## Zero-request dependency independence

| ID | Caller | Pre-state | Preview / execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLYC-CLAIM-YIELD-P09 | Fuzz all callers | Zero yield; Payout paused or Kernel-inactive; claimer settlement role revoked | Quote and claim return the same valid withdrawal token and zero amount; quote recipient=0 and executable=true | No Payout call, Core settlement, transfer or logs; liabilities unchanged | Covered: [test][test_givenZeroYieldAndUnavailablePayout_whenClaimed] |

[test_givenAuthoritativeSettlementOutput_whenClaimed]: claimYieldForwarding.t.sol#L12
[test_givenCaughtTokenCallback_whenClaimed]: claimYieldCallback.t.sol#L39
[test_givenDisabledTask_whenClaimed_reverts]: claimYield.t.sol#L163
[test_givenExternalShares_whenClaimed]: claimYieldSharesIntegration.t.sol#L61
[test_givenInactiveTask_whenClaimed_reverts]: claimYield.t.sol#L206
[test_givenInsolventCustody_whenClaimed_reverts]: claimYield.t.sol#L140
[test_givenOneUnitYield_whenAnyCallerClaims]: claimYield.t.sol#L72
[test_givenPositiveYieldAndRevokedRole_whenClaimed_reverts]: claimYield.t.sol#L124
[test_givenPropagatedTokenCallback_whenClaimed_reverts]: claimYieldCallback.t.sol#L76
[test_givenReEnabledAndReactivated_whenClaimed]: claimYield.t.sol#L268
[test_givenSubShareSurplus_whenClaimedRepeatedly]: claimYieldSharesIntegration.t.sol#L22
[test_givenTreasuryUpgraded_whenClaimed]: claimYieldSharesIntegration.t.sol#L191
[test_givenUnavailableCore_whenClaimed_reverts]: claimYield.t.sol#L226
[test_givenUnderlyingOutput_whenYieldRoutingChanges]: claimYieldSharesIntegration.t.sol#L115
[test_givenVaultShares_whenYieldRoutingChanges]: claimYieldSharesIntegration.t.sol#L160
[test_givenZeroYieldAndRevokedRole_whenClaimed]: claimYield.t.sol#L109
[test_givenZeroYieldAndUnsupportedMode_whenClaimed_reverts]: claimYieldSharesIntegration.t.sol#L138
[test_whenPermissionlessCallerSeeds]: claimYield.t.sol#L251
[test_givenDirectCustodyDonation_whenYieldClaimed_thenOperatorSharesBoundOutput]: claimYield.t.sol#L277
[test_givenZeroYieldAndUnavailablePayout_whenClaimed]: claimYield.t.sol#L47
[test_givenInactiveDisabledTask_whenClaimed_reverts]: claimYield.t.sol#L179
[test_givenPositiveYieldAndDepositManagerInactive_whenClaimed_reverts]: claimYield.t.sol#L22
