# BurnerLoansCore.rescue coverage plan

Source: [rescue](../../../policies/burnerloans/BurnerLoansCore.sol#L1248). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

Coverage records implemented scenario domains and assertions. Test pass/fail results are separate from coverage.

Check the preview in the existing action cases below. Expected behavior remains fixed during implementation; update the Test column as coverage is verified.

## Domains and notation

Scenario scope: `BLCORE-RESCUE` identifies this contract/function.

Core rescues its entire directly held ERC20 balance; no ordinary pending payout reserve belongs to Core. Receipt-token collateral is economically managed custody, so tests distinguish accidental ERC20 balances from collateral receipt balances rather than claiming all holdings are harmless surplus. Permission is selected Config by address OR ADMIN. No Config lifecycle/interface/Kernel checks; Core itself must be active, but may be locally disabled. Execution checks the guard, permission, own activity and inputs in that order. Preview omits permission and retains the other checks.

Unchanged means Core/DM/Inventory/Custody balances, loans, pending obligations and logs unchanged. Invalid input rows use active Core and idle guard. Fuzz equivalent permitted caller classes independently of balances and destinations.

## Authorization

| ID | Caller | Input | Execution | Effects | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCORE-RESCUE-A01 | Fuzz caller excluding selected Config and every ADMIN holder | Valid or invalid inputs | NotAuthorised() | Unchanged | Permissionless quote for valid inputs; invalid inputs reach their own validation | Covered: [test][test_givenUnauthorized_whenRescued_reverts], [test][test_givenUnauthorized_whenPreviewed] |

## Lifecycle

| ID | Caller | Local active | Local enabled | Execution | Effects | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCORE-RESCUE-L01 | Fuzz selected Config or ADMIN_ROLE holder; guarantee Config-only, ADMIN-only and overlap seeds | true | true | Success with valid inputs | Function-specific effects on success; otherwise Unchanged | Any viewer quotes the current direct balance; retain lifecycle and busy-settlement checks, with no transfer | Covered: [test][test_givenAuthorized_whenRescued], [test][test_givenConfigAlsoAdmin_whenRescued] |
| BLCORE-RESCUE-L02 | Fuzz selected Config or ADMIN_ROLE holder; guarantee Config-only, ADMIN-only and overlap seeds | true | false | Success with valid inputs | Function-specific effects on success; otherwise Unchanged | Any viewer quotes the current direct balance; retain lifecycle and busy-settlement checks, with no transfer | Covered: [test][test_givenAuthorized_whenRescued] |
| BLCORE-RESCUE-L03 | Fuzz selected Config or ADMIN_ROLE holder; guarantee Config-only, ADMIN-only and overlap seeds | false | true | BurnerLoans_PolicyNotActive(BurnerLoansCore) | Function-specific effects on success; otherwise Unchanged | BurnerLoans_PolicyNotActive(BurnerLoansCore) before token/destination reads; same as rescue under permitted caller | Covered: [test][test_givenCoreInactive_whenRescued_reverts] |
| BLCORE-RESCUE-L04 | Fuzz selected Config or ADMIN_ROLE holder; guarantee Config-only, ADMIN-only and overlap seeds | false | false | BurnerLoans_PolicyNotActive(BurnerLoansCore) | Function-specific effects on success; otherwise Unchanged | BurnerLoans_PolicyNotActive(BurnerLoansCore) before token/destination reads; same as rescue under permitted caller | Covered: [test][test_givenCoreInactive_whenRescued_reverts] |

## Invalid token and destination inputs

| ID | Caller | Input | Execution | Effects | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCORE-RESCUE-I01 | Fuzz selected Config or ADMIN_ROLE holder; guarantee Config-only, ADMIN-only and overlap seeds | token=0; destination valid | BurnerLoans_InvalidAsset(0) | Unchanged | Same token/destination error; fuzz caller; no writes | Covered: [test][test_givenTokenWithoutCode_whenRescued_reverts] |
| BLCORE-RESCUE-I02 | Fuzz selected Config or ADMIN_ROLE holder; guarantee Config-only, ADMIN-only and overlap seeds | token is nonzero EOA; destination valid | BurnerLoans_InvalidAsset(token) | Unchanged | Same token/destination error; fuzz caller; no writes | Covered: [test][test_givenTokenWithoutCode_whenRescued_reverts] |
| BLCORE-RESCUE-I03 | Fuzz selected Config or ADMIN_ROLE holder; guarantee Config-only, ADMIN-only and overlap seeds | Deployed token; destination=zero | BurnerLoans_InvalidRescueDestination(destination) | Unchanged | Same token/destination error; fuzz caller; no writes | Covered: [test][test_givenZeroDestination_whenRescued_reverts] |
| BLCORE-RESCUE-I04 | Fuzz selected Config or ADMIN_ROLE holder; guarantee Config-only, ADMIN-only and overlap seeds | Deployed token; destination=Core | BurnerLoans_InvalidRescueDestination(destination) | Unchanged | Same token/destination error; fuzz caller; no writes | Covered: [test][test_givenCoreDestination_whenRescued_reverts] |
| BLCORE-RESCUE-I05 | Fuzz selected Config or ADMIN_ROLE holder; guarantee Config-only, ADMIN-only and overlap seeds | Deployed token; destination=token | BurnerLoans_InvalidRescueDestination(destination) | Unchanged | Same token/destination error; fuzz caller; no writes | Covered: [test][test_givenTokenDestination_whenRescued_reverts] |
| BLCORE-RESCUE-I06 | Fuzz selected Config or ADMIN_ROLE holder; guarantee Config-only, ADMIN-only and overlap seeds | Deployed token; destination=selected Custody | BurnerLoans_InvalidRescueDestination(destination) | Unchanged | Same token/destination error; fuzz caller; no writes | Covered: [test][test_givenPayoutDestination_whenRescued_reverts] |
| BLCORE-RESCUE-I07 | Fuzz selected Config or ADMIN_ROLE holder; guarantee Config-only, ADMIN-only and overlap seeds | Deployed token; destination=selected Config | BurnerLoans_InvalidRescueDestination(destination) | Unchanged | Same token/destination error; fuzz caller; no writes | Covered: [test][test_givenConfigDestination_whenRescued_reverts] |
| BLCORE-RESCUE-I08 | Fuzz selected Config or ADMIN_ROLE holder; guarantee Config-only, ADMIN-only and overlap seeds | Deployed token; destination=Kernel | BurnerLoans_InvalidRescueDestination(destination) | Unchanged | Same token/destination error; fuzz caller; no writes | Covered: [test][test_givenKernelDestination_whenRescued_reverts] |

## Balances and successful recovery

| ID | Caller | Core balance | Execution | Effects | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCORE-RESCUE-P01 | Fuzz selected Config or ADMIN_ROLE holder; guarantee Config-only, ADMIN-only and overlap seeds | 0 | No-op | No transfer or AssetRescued event; no DM/Inventory/Custody call | Quote 0; balance unchanged; rescue is also a no-op | Covered: [test][test_givenAuthorized_whenRescued], [test][test_whenSurplusBoundarySeeds] |
| BLCORE-RESCUE-P02 | Fuzz selected Config or ADMIN_ROLE holder; guarantee Config-only, ADMIN-only and overlap seeds | Fuzz 1..MAX256; seed 1,MAX256 with representable token supply | Transfer entire balance | Core balance zero; recipient +B; AssetRescued(token,destination,B); other custody/accounting untouched | Quote independent direct Core balance B; actual rescued amount=B at unchanged balance; preview moves nothing | Covered: [test][test_givenAuthorized_whenRescued], [test][test_whenSurplusBoundarySeeds], [test][test_givenConfigAlsoAdmin_whenRescued] |

## Transfer failure and callbacks

| ID | Caller | Fault | Execution | Effects | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCORE-RESCUE-C01 | Fuzz selected Config or ADMIN_ROLE holder; guarantee Config-only, ADMIN-only and overlap seeds | Mandatory outgoing transfer raises configured token error | Exact injected error | Full rollback | Same pre-transfer guards, including busy-settlement rejection; read-only quote does not exercise token callbacks | Covered: [test][test_givenTransferFailure_whenRescued_reverts] |
| BLCORE-RESCUE-C02 | Fuzz selected Config or ADMIN_ROLE holder; guarantee Config-only, ADMIN-only and overlap seeds | Token calls an independently authorized guarded Core action; catches rejection | Outer success; nested ReentrancyGuardReentrantCall() | One rescue only | Same pre-transfer guards, including busy-settlement rejection; read-only quote does not exercise token callbacks | Covered: [test][test_givenAuthorizedCallback_whenCaughtRescue], [test][test_givenBusyCore_whenPreviewed_reverts] |
| BLCORE-RESCUE-C03 | Fuzz selected Config or ADMIN_ROLE holder; guarantee Config-only, ADMIN-only and overlap seeds | Token propagates authorized nested guard rejection | ReentrancyGuardReentrantCall() | Full rollback | Same pre-transfer guards, including busy-settlement rejection; read-only quote does not exercise token callbacks | Covered: [test][test_givenAuthorizedCallback_whenPropagatedRescue] |

## Shared assertions

Core preview is permissionless and validates lifecycle, settlement-busy, token and destination conditions and quotes the current direct balance without writes. Config.rescue forwards only to Core; CustodyConfigTimelock.queueRescue targets Custody independently. Core tests must not expect a Custody transfer.

## Permissionless recovery quote

| ID | Quote requester | Core active | Core enabled | Balance / condition | Preview / execution | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCORE-RESCUE-A02 | Fuzz all addresses | true | true | Full uint256 direct token balance; seeds 0,1,MAX256 | Exact balance quote without authority or writes; unauthorized rescue still rejects | Covered: [test][test_whenAnyViewerQuotesRecovery], [test][test_whenRecoveryQuoteBalanceBoundaries] |
| BLCORE-RESCUE-A03 | Fuzz unrelated addresses | true | false | Positive direct balance | Quote and authorized recovery remain available while Core is paused | Covered: [test][test_givenPausedCore_whenAnyViewerQuotesRecovery] |

[test_givenAuthorizedCallback_whenCaughtRescue]: rescue.t.sol#L248
[test_givenAuthorizedCallback_whenPropagatedRescue]: rescue.t.sol#L263
[test_givenAuthorized_whenRescued]: rescue.t.sol#L45
[test_givenBusyCore_whenPreviewed_reverts]: rescue.t.sol#L274
[test_givenConfigAlsoAdmin_whenRescued]: rescue.t.sol#L87
[test_givenConfigDestination_whenRescued_reverts]: rescue.t.sol#L183
[test_givenCoreDestination_whenRescued_reverts]: rescue.t.sol#L129
[test_givenCoreInactive_whenRescued_reverts]: rescue.t.sol#L92
[test_givenKernelDestination_whenRescued_reverts]: rescue.t.sol#L201
[test_givenPayoutDestination_whenRescued_reverts]: rescue.t.sol#L165
[test_givenTokenDestination_whenRescued_reverts]: rescue.t.sol#L147
[test_givenTokenWithoutCode_whenRescued_reverts]: rescue.t.sol#L219
[test_givenTransferFailure_whenRescued_reverts]: rescue.t.sol#L232
[test_givenUnauthorized_whenPreviewed]: rescue.t.sol#L28
[test_givenUnauthorized_whenRescued_reverts]: rescue.t.sol#L20
[test_givenZeroDestination_whenRescued_reverts]: rescue.t.sol#L111
[test_whenSurplusBoundarySeeds]: rescue.t.sol#L80
[test_whenAnyViewerQuotesRecovery]: ./rescue.t.sol#L288
[test_whenRecoveryQuoteBalanceBoundaries]: ./rescue.t.sol#L305
[test_givenPausedCore_whenAnyViewerQuotesRecovery]: ./rescue.t.sol#L312
