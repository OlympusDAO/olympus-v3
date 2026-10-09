# setYieldRecipient scenario plan

Scope: RD global yield destination and compatibility with both active routes and pending historical yield.

Co-located getters: yieldRecipient equals the supplied pointer after success and retains its old value on failure. Recompute assetDistributionHash independently for every affected asset; changing the global yieldRecipient changes its encoded hash even when routes are unchanged. Assert getters remain readable while RD disabled/inactive, with fuzzed getter callers.

Default: the acting policy is Kernel-active. Inactivity tests retain valid caller roles/operator binding and active dependencies; snapshot after deactivation, before the attempted action. Getters remain readable. Preserve existing guard precedence unless a row specifies a change.

## Domains and assertions

Admin and the current nonzero config operator are separate permitted caller classes; revenue_distributor_admin alone grants no direct RD configuration authority. Fuzz unauthorized callers excluding every granted admin and the current operator; seed former operator, revenue admin, emergency and payout recipient. No dual-role case is required. Configuration guard order: nonReentrant, caller, local enabled, Kernel active, then inputs. Zero is a permitted fallback only when no Active asset has a positive repurchase share. This is a global role destination; historical configured recipients remain fixed. A same-pointer call must still re-evaluate the candidate and every applicable active-route and pending-asset compatibility check. If those checks pass, it is a no-op with no event.

Unchanged means balances, liabilities, route configuration, membership indexes and lifecycle state retain their pre-call values; a reverted transaction commits no events. Check exact error data. Views are permissionless, including while disabled or Kernel-inactive. On a changed-pointer success, the getter equals the requested recipient, YieldRecipientSet is emitted once, custody and raw debt stay unchanged, and all affected entitlements/enumerations reflect the new role address. On a validated same-pointer success, no state changes and no event is emitted.

## Authorization

Authorization is checked before RD lifecycle and `recipient_` validation. For SYR-A03, independently fuzz RD Kernel state (active/inactive), RD local state (enabled/disabled), the current pointer (zero/nonzero) and `recipient_` (zero, Treasury, valid policy, EOA, incompatible contract, inactive policy and disabled policy). Exclude admin and the current nonzero config operator from the caller generator.

| ID | Caller | Crossed domain | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| SYR-A01 | Admin | RD active/enabled; changed compatible nonzero `recipient_` | Success | Select recipient | Covered: [evidence][test_givenAdmin_whenYieldRecipientSet], [full result][test_givenZeroPointer_whenPermittedCallerSelectsRecipient_emitsAndPreservesState] |
| SYR-A02 | Current config operator | RD active/enabled; changed compatible nonzero `recipient_` | Success | Select recipient | Covered: [pending seed][test_givenYieldPayoutPending_whenYieldRecipientChanges_thenRetryPaysCurrentRecipient], [full result][test_givenZeroPointer_whenPermittedCallerSelectsRecipient_emitsAndPreservesState], [multi-asset matrix][test_givenMultipleActiveAndRetiredYieldDebts_whenRecipientChanges_redirectsOnlyRoleDebt] |
| SYR-A03 | Any caller outside the permitted set, fuzz | Full authorization domain above | RevenueDistributor_UnauthorizedConfigOperator(caller) | Unchanged | Covered: [evidence][test_whenUnauthorizedCallerSetsYieldRecipient_reverts], [full matrix][test_givenAnyLifecycleAndCandidate_whenUnauthorizedCallerSetsYieldRecipient_reverts], [seeded identities][test_givenSeededUnauthorizedIdentities_whenYieldRecipientSet_reverts] |

## Lifecycle

For lifecycle rows, fuzz current pointer, active/retired routes, pending yield and `recipient_` across zero, valid and invalid values. Exercise admin and the current config operator separately.

| ID | RD Kernel | RD local | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| SYR-L01 | Active | Disabled | NotEnabled() | Unchanged | Covered: [evidence][test_givenDisabled_whenOperatorSetsYieldRecipient_reverts], [full matrix][test_givenUnavailableDistributor_whenPermittedCallerSetsAnyYieldRecipient_reverts] |
| SYR-L02 | Inactive | Enabled | RevenueDistributor_PolicyInactive() | Unchanged | Covered: [evidence][test_givenPolicyInactive_whenOperatorSetsYieldRecipient_reverts], [full matrix][test_givenUnavailableDistributor_whenPermittedCallerSetsAnyYieldRecipient_reverts] |
| SYR-L03 | Inactive | Disabled | NotEnabled() before activity error | Unchanged | Covered: [evidence][test_givenPolicyInactiveAndDisabled_whenYieldRecipientSet_revertsNotEnabledFirst] |

## Invalid inputs

Validation has two distinct layers: the candidate address must first be a valid active and enabled recipient policy, then that candidate must support every RD asset that needs repurchase delivery. In the tables below, “asset state on candidate” means the vault registration exposed by the proposed yield recipient; it is distinct from the RD asset lifecycle.

### Invalid candidate recipient

These failures occur before any per-asset registration lookup.

| ID | Caller | Current pointer | `recipient_` candidate | Candidate policy state | Active RD assets | Pending-yield assets | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SYR-I01 | Admin; operator separately | Fuzz zero/nonzero | Current Treasury | Excluded role address | Fuzz none/zero/positive routes | Fuzz none/one/multiple | RevenueDistributor_InvalidYieldRecipient(recipient) | Unchanged | Covered: [seed][test_givenTreasuryAddress_whenYieldRecipientSet_reverts], [full matrix][test_givenAnyPointerAndAssetState_whenExcludedAddressSelected_revertsAndRollsBack] |
| SYR-I05 | Admin; operator separately | Fuzz zero/nonzero | EOA | Not a recipient policy | Fuzz none/zero/positive routes | Fuzz none/one/multiple | RevenueDistributor_InvalidYieldRecipient(recipient) | Unchanged | Covered: [EOA fuzz][test_whenEOASelectedAsYieldRecipient_reverts], [full matrix][test_givenAnyPointerAndAssetState_whenExcludedAddressSelected_revertsAndRollsBack] |
| SYR-I06 | Admin; operator separately | Zero | Different contract | Lacks ERC-165, IEnabler or IYieldRepurchaseRecipient; exercise each separately | None | None | RevenueDistributor_InvalidYieldRecipient(recipient) | Unchanged | Covered: [evidence][test_whenCandidateLacksRequiredInterface_reverts] |
| SYR-I07 | Admin; current config operator separately | Different nonzero pointer; same pointer separately | Different recipient or current recipient | Interface-compatible but Kernel-inactive or locally disabled | Fuzz none/zero/positive routes | Fuzz none/one/multiple | RevenueDistributor_InvalidYieldRecipient(recipient) | Unchanged; same-pointer input is re-evaluated | Covered: [same disabled seed][test_givenSelectedRecipientBecomesDisabled_whenSetAgain_reverts], [different seed][test_whenCandidatePolicyIsInactiveOrDisabled_reverts], [full matrix][test_givenInactiveOrDisabledCandidate_whenSetAsSameOrDifferentPointer_revertsAndRollsBack] |

### Unsupported active-route assets

These rows concern an asset that is `Active` in RevenueDistributor and has nonzero repurchase BPS.
The “candidate registration” column describes the separate vault record returned by the proposed
Yield Recipient. A zero current pointer is impossible in these rows: RevenueDistributor will not
create a positive repurchase route until a nonzero compatible Yield Recipient is selected.

| ID | Caller | Current pointer | `recipient_` | RD asset | Repurchase BPS | Candidate lookup | Candidate registration | Other RD assets | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SYR-I02 | Admin; operator separately | Nonzero | Zero | Active | Positive | None; zero selects Treasury fallback | Unsupported by definition because no Yield Recipient policy is selected | Fuzz pending-yield assets | RevenueDistributor_YieldRecipientUnavailable(address(0), asset) | Unchanged; later-asset failure rolls back the full call | Covered: [seed][test_givenActiveRepurchaseRoute_whenYieldRecipientCleared_reverts], [later-asset matrix][test_givenLaterActiveRepurchaseRoute_whenYieldRecipientCleared_revertsAndRollsBack] |
| SYR-I09 | Admin; current config operator separately | Nonzero | Different nonzero active/enabled compatible policy | Active vault-share token | Positive | Direct `getVaultConfig(asset)` | Missing, disabled, malformed or reverting; no enabled underlying match | Earlier assets supported; fuzz none/one/multiple | RevenueDistributor_YieldRecipientUnavailable(recipient, asset) | New recipient is not selected; all earlier checks leave state unchanged | Covered: [missing seed][test_givenActiveVaultShareRoute_whenUnsupportedYieldRecipientSelected_reverts], [failure matrix][test_givenActiveRepurchaseRoute_whenCandidateRegistrationInvalid_revertsAndRollsBack] |
| SYR-I10 | Admin; current config operator separately | Nonzero | Different nonzero active/enabled compatible policy | Active underlying token | Positive | Enumerate `getVaults()`, then inspect matching underlying | No matching vault, or matching vault is disabled, malformed or reverting; no enabled direct match | Earlier assets supported; fuzz none/one/multiple | RevenueDistributor_YieldRecipientUnavailable(recipient, asset) | New recipient is not selected; all earlier checks leave state unchanged | Covered: [missing seed][test_givenActiveUnderlyingRoute_whenUnsupportedRecipientSelected_reverts], [failure matrix][test_givenActiveRepurchaseRoute_whenCandidateRegistrationInvalid_revertsAndRollsBack] |
| SYR-I12 | Admin; current config operator separately | Same nonzero | Same nonzero policy | Active vault-share or underlying token, separately | Positive | Repeat the applicable direct or underlying lookup | Registration became missing, disabled, malformed or reverting after initial selection | Fuzz none/one/multiple | RevenueDistributor_YieldRecipientUnavailable(recipient, asset) | Pointer and all liabilities remain unchanged; no event; same-pointer input is re-evaluated | Covered: [disabled direct seed][test_givenSameRecipientRegistrationDisabled_whenSetAgain_reverts], [full matrix][test_givenActiveRepurchaseRoute_whenCandidateRegistrationInvalid_revertsAndRollsBack] |

### Unsupported pending-yield assets

These rows concern an RD liability, not an active route. The asset is `Retired` in
RevenueDistributor, its route has been deleted, and `_pendingYieldRecipient[asset]` is positive.
That live-role debt follows the current Yield Recipient, so a changed nonzero recipient must support
the retired asset before the pointer can move.

| ID | Caller | Current pointer | `recipient_` | RD asset | Pending yield | Candidate lookup | Candidate registration | Active-route precondition | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SYR-I03 | Admin; operator separately | Nonzero | Different nonzero active/enabled compatible policy | Retired vault-share token | Positive | Direct `getVaultConfig(asset)` | Missing, disabled, malformed or reverting | No earlier incompatible Active positive route | RevenueDistributor_YieldRecipientUnavailable(recipient, asset) | Old recipient remains selected; pending yield is not redirected | Covered: [missing seed][test_givenRetiredAssetWithPendingYield_whenIncompatibleRecipientSelected_reverts], [failure matrix][test_givenRetiredPendingYield_whenCandidateRegistrationInvalid_revertsAndRollsBack] |
| SYR-I13 | Admin; operator separately | Nonzero | Different nonzero active/enabled compatible policy | Retired underlying token | Positive | Enumerate `getVaults()`, then inspect matching underlying | No matching vault, or matching vault is disabled, malformed or reverting | No earlier incompatible Active positive route | RevenueDistributor_YieldRecipientUnavailable(recipient, asset) | Old recipient remains selected; pending yield is not redirected | Covered: [missing seed][test_givenRetiredUnderlyingWithPendingYield_whenUnsupportedRecipientSelected_reverts], [failure matrix][test_givenRetiredPendingYield_whenCandidateRegistrationInvalid_revertsAndRollsBack] |
| SYR-I14 | Admin; operator separately | Nonzero | Different nonzero active/enabled compatible policy | Multiple Retired assets | Positive for each | Direct or underlying, separately | Earlier asset supported; later asset unsupported | No incompatible Active positive route | RevenueDistributor_YieldRecipientUnavailable(recipient, laterAsset) | Full call rolls back; no pending liability is redirected | Covered: [direct vault shares][test_givenMultipleRetiredPendingAssets_whenLaterAssetUnsupported_reverts], [underlying matrix][test_givenMultipleRetiredUnderlyingAssets_whenLaterAssetUnsupported_revertsAndRollsBack] |
| SYR-I11 | Admin; operator separately | Nonzero | Different nonzero active/enabled compatible policy | One Retired unsupported asset | Positive | Direct or underlying, separately | Unsupported | An earlier Active positive-route asset is also unsupported | RevenueDistributor_YieldRecipientUnavailable(recipient, activeAsset) | Unchanged; Active routes are validated before pending assets | Covered: [evidence][test_givenUnsupportedActiveAndPendingAssets_whenRecipientChanges_revertsForActiveFirst] |

### Configured-recipient collision

| ID | Caller | Pointer transition | Candidate policy state | Active RD asset state | Candidate asset support | Collision state | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SYR-I04 | Admin; operator separately | Zero or old nonzero -> different nonzero recipient | Kernel-active, locally enabled and interface-compatible | Fuzz zero/positive routes | Compatible for every positive route checked earlier | Candidate is already an ordinary configured recipient on an Active asset | RevenueDistributor_DuplicateRecipient(candidate) | Unchanged | Covered: [first collision][test_givenOrdinaryRecipient_whenSelectedAsYieldRecipient_reverts], [later collision][test_givenCandidateIsConfiguredOnLaterActiveAsset_whenSelected_revertsAndRollsBack], [retired-only control][test_givenCandidateConfiguredOnlyOnRetiredAsset_whenSelected_succeeds] |

Active routes are scanned before pending assets; SYR-I11 makes the resulting error precedence explicit when both are incompatible.

## Valid pointer updates

Exercise admin and the current config operator separately. Pending assets refer to RD liabilities: Active assets may still have routes, while Retired assets have no route but can retain an unpaid yield-recipient bucket.

| ID | Pointer transition | Candidate policy state | RD asset state | Asset form checked on candidate | Asset state on candidate | Pending-yield state | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SYR-P09 | Zero -> nonzero recipient | Kernel-active, locally enabled and interface-compatible | No positive Active route | Not applicable | No asset lookup required | None | Success | Pointer equals new recipient; one YieldRecipientSet; liabilities unchanged | Covered: [admin seed][test_givenAdmin_whenYieldRecipientSet], [caller and isolation matrix][test_givenZeroPointer_whenPermittedCallerSelectsRecipient_emitsAndPreservesState] |
| SYR-P10 | Nonzero -> different nonzero recipient | Kernel-active, locally enabled and interface-compatible | No positive Active route | Not applicable | No asset lookup required | None | Success | Pointer equals new recipient; one YieldRecipientSet; liabilities unchanged | Covered: [evidence][test_givenNoPositiveRoutes_whenNonzeroRecipientChanges_succeeds] |
| SYR-P07 | Nonzero -> different nonzero recipient | Kernel-active, locally enabled and interface-compatible | Active positive route pays a vault share | Direct vault-share lookup | Enabled registration whose returned vault equals the route asset | None | Success | Pointer equals new recipient; one YieldRecipientSet; configured/Treasury debt unchanged | Covered: [evidence][test_givenActiveVaultShareRoute_whenCompatibleYieldRecipientChanges_succeeds] |
| SYR-P08 | Nonzero -> different nonzero recipient | Kernel-active, locally enabled and interface-compatible | Active positive route pays a vault underlying | Registered-vault enumeration and underlying match | Enabled matching vault registration | None | Success | Pointer equals new recipient; one YieldRecipientSet; configured/Treasury debt unchanged | Covered: [evidence][test_givenActiveUnderlyingRoute_whenCompatibleRecipientChanges_succeeds] |
| SYR-P02 | Nonzero -> different nonzero recipient | Kernel-active, locally enabled and interface-compatible | Fuzz none/one/multiple Active assets with zero/positive routes | Direct and underlying lookups separately | Every applicable asset has an enabled matching registration | Fuzz one/multiple Active and Retired assets | Success | Every live-role entitlement moves from old role to new recipient; fixed-address entitlements unaffected; one event | Covered: [active pending seed][test_givenYieldPayoutPending_whenYieldRecipientChanges_thenRetryPaysCurrentRecipient], [full matrix][test_givenMultipleActiveAndRetiredYieldDebts_whenRecipientChanges_redirectsOnlyRoleDebt] |
| SYR-P01 | Nonzero -> `address(0)` candidate recipient | Treasury fallback; no policy lookup | No positive Active route | Not applicable | Not applicable | Independently fuzz none, one and multiple Active/Retired pending assets | Success | Pointer clears; pending yield follows current Treasury fallback; configured debt unchanged; one event | Covered: [retired pending seed][test_givenRetiredAssetWithPendingYield_whenYieldRecipientCleared_thenTreasuryCanRetry], [full matrix][test_givenAnySupportedPendingYieldSet_whenRecipientCleared_redirectsToTreasury] |
| SYR-P03 | Same nonzero recipient -> same recipient | Still Kernel-active, locally enabled and interface-compatible | Fuzz none/one/multiple Active assets with zero/positive routes | Direct and underlying lookups separately | Every applicable registration remains enabled and matching | Fuzz none/one/multiple Active and Retired assets; all supported | Success after full revalidation; no-op | Pointer, hashes, liabilities and indexes unchanged; no YieldRecipientSet | Covered: [direct seed][test_givenSelectedCompatibleRecipient_whenSetAgain_noOps], [full matrix][test_givenSameCompatibleRecipientWithAnyAssetStates_whenSetAgain_noOps] |
| SYR-P04 | Zero -> `address(0)` candidate recipient | Treasury fallback; no policy lookup | No positive Active route | Not applicable | Not applicable | Fuzz none/one/multiple Active and Retired assets | Success after active-route validation; no-op | Pointer, hashes, liabilities and indexes unchanged; no YieldRecipientSet; pending yield keeps Treasury fallback | Covered: [empty seed][test_givenZeroYieldRecipient_whenSetToZeroAgain_noOps], [full matrix][test_givenZeroPointerAndAnyPendingYieldSet_whenSetToZeroAgain_noOps] |

[test_givenAdmin_whenYieldRecipientSet]: ./setYieldRecipient.t.sol#L23
[test_givenYieldPayoutPending_whenYieldRecipientChanges_thenRetryPaysCurrentRecipient]: ./setYieldRecipient.t.sol#L475
[test_whenUnauthorizedCallerSetsYieldRecipient_reverts]: ./setYieldRecipient.t.sol#L132
[test_givenDisabled_whenOperatorSetsYieldRecipient_reverts]: ./setYieldRecipient.t.sol#L149
[test_givenPolicyInactive_whenOperatorSetsYieldRecipient_reverts]: ./setYieldRecipient.t.sol#L182
[test_givenRetiredAssetWithPendingYield_whenYieldRecipientCleared_thenTreasuryCanRetry]: ./setYieldRecipient.t.sol#L535
[test_givenTreasuryAddress_whenYieldRecipientSet_reverts]: ./setYieldRecipient.t.sol#L118
[test_givenActiveRepurchaseRoute_whenYieldRecipientCleared_reverts]: ./setYieldRecipient.t.sol#L230
[test_givenRetiredAssetWithPendingYield_whenIncompatibleRecipientSelected_reverts]: ./setYieldRecipient.t.sol#L578
[test_givenOrdinaryRecipient_whenSelectedAsYieldRecipient_reverts]: ./setYieldRecipient.t.sol#L440
[test_whenEOASelectedAsYieldRecipient_reverts]: ./setYieldRecipient.t.sol#L98
[test_givenSelectedRecipientBecomesDisabled_whenSetAgain_reverts]: ./setYieldRecipient.t.sol#L79
[test_givenActiveVaultShareRoute_whenUnsupportedYieldRecipientSelected_reverts]: ./setYieldRecipient.t.sol#L281
[test_givenActiveVaultShareRoute_whenCompatibleYieldRecipientChanges_succeeds]: ./setYieldRecipient.t.sol#L258
[test_givenSelectedCompatibleRecipient_whenSetAgain_noOps]: ./setYieldRecipient.t.sol#L50
[test_givenZeroYieldRecipient_whenSetToZeroAgain_noOps]: ./setYieldRecipient.t.sol#L33
[test_givenPolicyInactiveAndDisabled_whenYieldRecipientSet_revertsNotEnabledFirst]: ./setYieldRecipient.t.sol#L191
[test_whenCandidateLacksRequiredInterface_reverts]: ./setYieldRecipient.t.sol#L314
[test_givenActiveUnderlyingRoute_whenUnsupportedRecipientSelected_reverts]: ./setYieldRecipient.t.sol#L362
[test_givenSameRecipientRegistrationDisabled_whenSetAgain_reverts]: ./setYieldRecipient.t.sol#L384
[test_givenNoPositiveRoutes_whenNonzeroRecipientChanges_succeeds]: ./setYieldRecipient.t.sol#L405
[test_givenActiveUnderlyingRoute_whenCompatibleRecipientChanges_succeeds]: ./setYieldRecipient.t.sol#L420
[test_givenRetiredUnderlyingWithPendingYield_whenUnsupportedRecipientSelected_reverts]: ./setYieldRecipient.t.sol#L617
[test_givenMultipleRetiredPendingAssets_whenLaterAssetUnsupported_reverts]: ./setYieldRecipient.t.sol#L643
[test_givenUnsupportedActiveAndPendingAssets_whenRecipientChanges_revertsForActiveFirst]: ./setYieldRecipient.t.sol#L678
[test_givenActiveRepurchaseRoute_whenCandidateRegistrationInvalid_revertsAndRollsBack]: ./setYieldRecipient.t.sol#L936
[test_givenAnyLifecycleAndCandidate_whenUnauthorizedCallerSetsYieldRecipient_reverts]: ./setYieldRecipient.t.sol#L710
[test_givenAnyPointerAndAssetState_whenExcludedAddressSelected_revertsAndRollsBack]: ./setYieldRecipient.t.sol#L814
[test_givenAnySupportedPendingYieldSet_whenRecipientCleared_redirectsToTreasury]: ./setYieldRecipient.t.sol#L1245
[test_givenCandidateConfiguredOnlyOnRetiredAsset_whenSelected_succeeds]: ./setYieldRecipient.t.sol#L1117
[test_givenCandidateIsConfiguredOnLaterActiveAsset_whenSelected_revertsAndRollsBack]: ./setYieldRecipient.t.sol#L1077
[test_givenInactiveOrDisabledCandidate_whenSetAsSameOrDifferentPointer_revertsAndRollsBack]: ./setYieldRecipient.t.sol#L856
[test_givenLaterActiveRepurchaseRoute_whenYieldRecipientCleared_revertsAndRollsBack]: ./setYieldRecipient.t.sol#L893
[test_givenMultipleActiveAndRetiredYieldDebts_whenRecipientChanges_redirectsOnlyRoleDebt]: ./setYieldRecipient.t.sol#L1180
[test_givenMultipleRetiredUnderlyingAssets_whenLaterAssetUnsupported_revertsAndRollsBack]: ./setYieldRecipient.t.sol#L1026
[test_givenRetiredPendingYield_whenCandidateRegistrationInvalid_revertsAndRollsBack]: ./setYieldRecipient.t.sol#L985
[test_givenSameCompatibleRecipientWithAnyAssetStates_whenSetAgain_noOps]: ./setYieldRecipient.t.sol#L1295
[test_givenSeededUnauthorizedIdentities_whenYieldRecipientSet_reverts]: ./setYieldRecipient.t.sol#L752
[test_givenUnavailableDistributor_whenPermittedCallerSetsAnyYieldRecipient_reverts]: ./setYieldRecipient.t.sol#L772
[test_givenZeroPointerAndAnyPendingYieldSet_whenSetToZeroAgain_noOps]: ./setYieldRecipient.t.sol#L1340
[test_givenZeroPointer_whenPermittedCallerSelectsRecipient_emitsAndPreservesState]: ./setYieldRecipient.t.sol#L1141
[test_whenCandidatePolicyIsInactiveOrDisabled_reverts]: ./setYieldRecipient.t.sol#L342
