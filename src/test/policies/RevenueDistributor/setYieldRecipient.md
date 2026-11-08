# setYieldRecipient scenario plan

Source: [RevenueDistributor](../../../policies/RevenueDistributor.sol).

Scope: RD global yield destination and compatibility with both active routes and pending historical yield.

Co-located getters: yieldRecipient equals the supplied pointer after success and retains its old value on failure. Recompute assetDistributionHash independently for every affected asset; changing the global yieldRecipient changes its encoded hash even when routes are unchanged. Assert getters remain readable while RD disabled/inactive, with fuzzed getter callers.

Default: the acting policy is Kernel-active. Inactivity tests retain valid caller roles/operator binding and active dependencies; snapshot after deactivation, before the attempted action. Getters remain readable. Preserve existing guard precedence unless a row specifies a change.

## Domains and assertions

Own-policy admission: require Kernel-active RevenueDistributor; own inactivity uses `RevenueDistributor_PolicyNotActive(RD)` before body/input/idempotent work. Require own Kernel activity before local enabled state (when required), caller authority, inputs and dependency checks. Successful body scenarios assume Local active=true, except explicit admission failures.

Admin and the current nonzero config operator are separate permitted caller classes; revenue_distributor_admin alone grants no direct RD configuration authority. Fuzz unauthorized callers excluding every granted admin and the current operator; seed former operator, revenue admin, emergency and payout recipient. Configuration guard order: nonReentrant, own Kernel activity, local enabled, caller authority, then inputs. Zero is a permitted fallback only when no Active asset has a positive repurchase share. This is a global role destination; historical configured recipients remain fixed. An unchanged pointer, including zero-to-zero, reverts with RevenueDistributor_SameAddress(recipient) before any candidate or asset-support probe. Validators and writes apply the same rule.

Unchanged means balances, liabilities, route configuration, membership indexes and lifecycle state retain their pre-call values; a reverted transaction commits no events. Check exact error data. Views are permissionless, including while disabled or Kernel-inactive. On a changed-pointer success, the getter equals the requested recipient, YieldRecipientSet is emitted once, custody and raw debt stay unchanged, and all affected entitlements/enumerations reflect the new role address. On same-pointer rejection, no state changes or events occur.

## Authorization

Own Kernel activity and local enablement precede caller authorization and `recipient_` validation. For SYR-A03, use active/enabled RD and independently fuzz the current pointer (zero/nonzero) and `recipient_` (zero, Treasury, valid policy, EOA, incompatible contract, inactive policy and disabled policy). Exclude admin and the current nonzero config operator from the caller generator.

| ID | Caller | Crossed domain | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| SYR-A01 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | RD active/enabled; changed compatible nonzero `recipient_` | Success | Select recipient | Covered: [test][test_givenAdmin_whenYieldRecipientSet], [test][test_givenZeroPointer_whenPermittedCallerSelectsRecipient_emitsAndPreservesState], [test][test_givenYieldPayoutPending_whenYieldRecipientChanges_thenRetryPaysCurrentRecipient], [test][test_givenMultipleActiveAndRetiredYieldDebts_whenRecipientChanges_redirectsOnlyRoleDebt], [test][test_givenAdmin_whenYieldRecipientSet_AdminOnlySeed], [test][test_givenAdmin_whenYieldRecipientSet_OperatorOnlySeed], [test][test_givenAdmin_whenYieldRecipientSet_RolesOverlapSeed], [test][test_givenZeroPointer_whenPermittedCallerSelectsRecipient_emitsAndPreservesState_AdminOnlySeed], [test][test_givenZeroPointer_whenPermittedCallerSelectsRecipient_emitsAndPreservesState_OperatorOnlySeed], [test][test_givenZeroPointer_whenPermittedCallerSelectsRecipient_emitsAndPreservesState_RolesOverlapSeed], [test][test_givenYieldPayoutPending_whenYieldRecipientChanges_thenRetryPaysCurrentRecipient_AdminOnlySeed], [test][test_givenYieldPayoutPending_whenYieldRecipientChanges_thenRetryPaysCurrentRecipient_OperatorOnlySeed], [test][test_givenYieldPayoutPending_whenYieldRecipientChanges_thenRetryPaysCurrentRecipient_RolesOverlapSeed], [test][test_givenMultipleActiveAndRetiredYieldDebts_whenRecipientChanges_redirectsOnlyRoleDebt_AdminOnlySeed], [test][test_givenMultipleActiveAndRetiredYieldDebts_whenRecipientChanges_redirectsOnlyRoleDebt_OperatorOnlySeed], [test][test_givenMultipleActiveAndRetiredYieldDebts_whenRecipientChanges_redirectsOnlyRoleDebt_RolesOverlapSeed] |
| SYR-A03 | Any caller outside the permitted set, fuzz | Active/enabled RD; full input domain above | RevenueDistributor_UnauthorizedConfigOperator(caller) | Unchanged | Covered: [evidence][test_whenUnauthorizedCallerSetsYieldRecipient_reverts], [full matrix][test_givenPolicyActiveEnabledAndCandidate_whenUnauthorizedCallerSetsYieldRecipient_reverts], [seeded identities][test_givenSeededUnauthorizedIdentities_whenYieldRecipientSet_reverts] |

## Lifecycle

For lifecycle rows, fuzz current pointer, active/retired routes, pending yield and `recipient_` across zero, valid and invalid values. Exercise admin and the current config operator separately.

| ID | Caller | Local active | Local enabled | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- |
| SYR-L01 | Fuzz permitted callers and unauthorized callers | true | false | NotEnabled() | Unchanged | Covered: [evidence][test_givenDisabled_whenOperatorSetsYieldRecipient_reverts], [full matrix][test_givenDisabledDistributor_whenPermittedCallerSetsAnyYieldRecipient_reverts]; [full matrix][test_givenInactiveDistributor_whenPermittedCallerSetsAnyYieldRecipient_reverts], [activity precedence][test_givenPolicyActiveDisabledAndCandidate_whenUnauthorizedCallerSetsYieldRecipient_reverts] |
| SYR-L02 | Fuzz permitted callers and unauthorized callers | false | true | RevenueDistributor_PolicyNotActive(RD) | Unchanged | Covered: [evidence][test_givenPolicyInactive_whenOperatorSetsYieldRecipient_reverts], [full matrix][test_givenDisabledDistributor_whenPermittedCallerSetsAnyYieldRecipient_reverts]; [full matrix][test_givenInactiveDistributor_whenPermittedCallerSetsAnyYieldRecipient_reverts], [activity precedence][test_givenPolicyInactiveAndCandidate_whenUnauthorizedCallerSetsYieldRecipient_reverts] |
| SYR-L03 | Fuzz permitted callers and unauthorized callers | false | false | RevenueDistributor_PolicyNotActive(RD) before local enablement and caller checks | Unchanged | Covered: [evidence][test_givenPolicyInactiveAndDisabled_whenYieldRecipientSet_revertsActivityFirst], [activity precedence][test_givenPolicyInactiveAndCandidate_whenUnauthorizedCallerSetsYieldRecipient_reverts] |

## Invalid inputs

Validation has two distinct layers: the candidate address must first be a valid active and enabled recipient policy, then that candidate must support every RD asset that needs repurchase delivery. In the tables below, “asset state on candidate” means the vault registration exposed by the proposed yield recipient; it is distinct from the RD asset lifecycle.

### Invalid candidate recipient

These failures occur before any per-asset registration lookup.

| ID | Caller | Current pointer | `recipient_` candidate | Candidate policy state | Active RD assets | Pending-yield assets | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SYR-I01 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | Fuzz zero/nonzero | Current Treasury | Excluded role address | Fuzz none/zero/positive routes | Fuzz none/one/multiple | RevenueDistributor_InvalidYieldRecipient(recipient) | Unchanged | Covered: [test][test_givenTreasuryAddress_whenYieldRecipientSet_reverts], [test][test_givenAnyPointerAndAssetState_whenExcludedAddressSelected_revertsAndRollsBack], [test][test_givenTreasuryAddress_whenYieldRecipientSet_reverts_AdminOnlySeed], [test][test_givenTreasuryAddress_whenYieldRecipientSet_reverts_OperatorOnlySeed], [test][test_givenTreasuryAddress_whenYieldRecipientSet_reverts_RolesOverlapSeed], [test][test_givenAnyPointerAndAssetState_whenExcludedAddressSelected_revertsAndRollsBack_AdminOnlySeed], [test][test_givenAnyPointerAndAssetState_whenExcludedAddressSelected_revertsAndRollsBack_OperatorOnlySeed], [test][test_givenAnyPointerAndAssetState_whenExcludedAddressSelected_revertsAndRollsBack_RolesOverlapSeed] |
| SYR-I05 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | Fuzz zero/nonzero | EOA | Not a recipient policy | Fuzz none/zero/positive routes | Fuzz none/one/multiple | RevenueDistributor_InvalidYieldRecipient(recipient) | Unchanged | Covered: [test][test_whenEOASelectedAsYieldRecipient_reverts], [test][test_givenAnyPointerAndAssetState_whenExcludedAddressSelected_revertsAndRollsBack], [test][test_whenEOASelectedAsYieldRecipient_reverts_AdminOnlySeed], [test][test_whenEOASelectedAsYieldRecipient_reverts_OperatorOnlySeed], [test][test_whenEOASelectedAsYieldRecipient_reverts_RolesOverlapSeed], [test][test_givenAnyPointerAndAssetState_whenExcludedAddressSelected_revertsAndRollsBack_AdminOnlySeed], [test][test_givenAnyPointerAndAssetState_whenExcludedAddressSelected_revertsAndRollsBack_OperatorOnlySeed], [test][test_givenAnyPointerAndAssetState_whenExcludedAddressSelected_revertsAndRollsBack_RolesOverlapSeed] |
| SYR-I06 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | Zero | Different contract | Lacks ERC-165, IEnabler or IYieldRepurchaseRecipient; exercise each separately | None | None | RevenueDistributor_InvalidYieldRecipient(recipient) | Unchanged | Covered: [test][test_whenCandidateLacksRequiredInterface_reverts], [test][test_whenCandidateLacksRequiredInterface_reverts_AdminOnlySeed], [test][test_whenCandidateLacksRequiredInterface_reverts_OperatorOnlySeed], [test][test_whenCandidateLacksRequiredInterface_reverts_RolesOverlapSeed] |
| SYR-I07 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | Different nonzero pointer | Different recipient | Interface-compatible but Kernel-inactive or locally disabled | Fuzz none/zero/positive routes | Fuzz none/one/multiple | PolicyDependency_NotActive(recipient) | Unchanged; same-pointer inputs use SYR-P03 | Covered: [test][test_whenCandidatePolicyIsInactiveOrDisabled_reverts], [test][test_givenInactiveOrDisabledCandidate_whenSetAsDifferentPointer_revertsAndRollsBack], [test][test_whenCandidatePolicyIsInactiveOrDisabled_reverts_AdminOnlySeed], [test][test_whenCandidatePolicyIsInactiveOrDisabled_reverts_OperatorOnlySeed], [test][test_whenCandidatePolicyIsInactiveOrDisabled_reverts_RolesOverlapSeed], [test][test_givenInactiveOrDisabledCandidate_whenSetAsDifferentPointer_revertsAndRollsBack_AdminOnlySeed], [test][test_givenInactiveOrDisabledCandidate_whenSetAsDifferentPointer_revertsAndRollsBack_OperatorOnlySeed], [test][test_givenInactiveOrDisabledCandidate_whenSetAsDifferentPointer_revertsAndRollsBack_RolesOverlapSeed] |

### Unsupported active-route assets

These rows concern an asset that is `Active` in RevenueDistributor and has nonzero repurchase BPS.
The “candidate registration” column describes the separate vault record returned by the proposed
Yield Recipient. A zero current pointer is impossible in these rows: RevenueDistributor will not
create a positive repurchase route until a nonzero compatible Yield Recipient is selected.

| ID | Caller | Current pointer | `recipient_` | RD asset | Repurchase BPS | Candidate lookup | Candidate registration | Other RD assets | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SYR-I02 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | Nonzero | Zero | Active | Positive | None; zero selects Treasury fallback | Unsupported by definition because no Yield Recipient policy is selected | Fuzz pending-yield assets | RevenueDistributor_YieldRecipientUnavailable(address(0), asset) | Unchanged; later-asset failure rolls back the full call | Covered: [test][test_givenActiveRepurchaseRoute_whenYieldRecipientCleared_reverts], [test][test_givenLaterActiveRepurchaseRoute_whenYieldRecipientCleared_revertsAndRollsBack], [test][test_givenActiveRepurchaseRoute_whenYieldRecipientCleared_reverts_AdminOnlySeed], [test][test_givenActiveRepurchaseRoute_whenYieldRecipientCleared_reverts_OperatorOnlySeed], [test][test_givenActiveRepurchaseRoute_whenYieldRecipientCleared_reverts_RolesOverlapSeed], [test][test_givenLaterActiveRepurchaseRoute_whenYieldRecipientCleared_revertsAndRollsBack_AdminOnlySeed], [test][test_givenLaterActiveRepurchaseRoute_whenYieldRecipientCleared_revertsAndRollsBack_OperatorOnlySeed], [test][test_givenLaterActiveRepurchaseRoute_whenYieldRecipientCleared_revertsAndRollsBack_RolesOverlapSeed] |
| SYR-I09 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | Nonzero | Different nonzero active/enabled compatible policy | Active vault-share token | Positive | Direct `getVaultConfig(asset)` | Missing, disabled, malformed or reverting; no enabled underlying match | Earlier assets supported; fuzz none/one/multiple | RevenueDistributor_YieldRecipientUnavailable(recipient, asset) | New recipient is not selected; all earlier checks leave state unchanged | Covered: [test][test_givenActiveVaultShareRoute_whenUnsupportedYieldRecipientSelected_reverts], [test][test_givenActiveRepurchaseRoute_whenCandidateRegistrationInvalid_revertsAndRollsBack], [test][test_givenActiveVaultShareRoute_whenUnsupportedYieldRecipientSelected_reverts_AdminOnlySeed], [test][test_givenActiveVaultShareRoute_whenUnsupportedYieldRecipientSelected_reverts_OperatorOnlySeed], [test][test_givenActiveVaultShareRoute_whenUnsupportedYieldRecipientSelected_reverts_RolesOverlapSeed], [test][test_givenActiveRepurchaseRoute_whenCandidateRegistrationInvalid_revertsAndRollsBack_AdminOnlySeed], [test][test_givenActiveRepurchaseRoute_whenCandidateRegistrationInvalid_revertsAndRollsBack_OperatorOnlySeed], [test][test_givenActiveRepurchaseRoute_whenCandidateRegistrationInvalid_revertsAndRollsBack_RolesOverlapSeed] |
| SYR-I10 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | Nonzero | Different nonzero active/enabled compatible policy | Active underlying token | Positive | Enumerate `getVaults()`, then inspect matching underlying | No matching vault, or matching vault is disabled, malformed or reverting; no enabled direct match | Earlier assets supported; fuzz none/one/multiple | RevenueDistributor_YieldRecipientUnavailable(recipient, asset) | New recipient is not selected; all earlier checks leave state unchanged | Covered: [test][test_givenActiveUnderlyingRoute_whenUnsupportedRecipientSelected_reverts], [test][test_givenActiveRepurchaseRoute_whenCandidateRegistrationInvalid_revertsAndRollsBack], [test][test_givenActiveUnderlyingRoute_whenUnsupportedRecipientSelected_reverts_AdminOnlySeed], [test][test_givenActiveUnderlyingRoute_whenUnsupportedRecipientSelected_reverts_OperatorOnlySeed], [test][test_givenActiveUnderlyingRoute_whenUnsupportedRecipientSelected_reverts_RolesOverlapSeed], [test][test_givenActiveRepurchaseRoute_whenCandidateRegistrationInvalid_revertsAndRollsBack_AdminOnlySeed], [test][test_givenActiveRepurchaseRoute_whenCandidateRegistrationInvalid_revertsAndRollsBack_OperatorOnlySeed], [test][test_givenActiveRepurchaseRoute_whenCandidateRegistrationInvalid_revertsAndRollsBack_RolesOverlapSeed] |
| SYR-I12 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | Same nonzero | Same nonzero policy | Active vault-share or underlying token, separately | Positive | No candidate lookup | Registration became missing, disabled, malformed or reverting after initial selection | Fuzz none/one/multiple | RevenueDistributor_SameAddress(recipient) | Pointer and all liabilities remain unchanged; no event; same-pointer rejection precedes all probes | Covered: [test][test_givenSameRecipientRegistrationDisabled_whenSetAgain_reverts], [test][test_givenSamePointer_whenDependencyProbesWouldFail_reverts], [test][test_givenSameRecipientRegistrationDisabled_whenSetAgain_reverts_AdminOnlySeed], [test][test_givenSameRecipientRegistrationDisabled_whenSetAgain_reverts_OperatorOnlySeed], [test][test_givenSameRecipientRegistrationDisabled_whenSetAgain_reverts_RolesOverlapSeed], [test][test_givenSamePointer_whenDependencyProbesWouldFail_reverts_AdminOnlySeed], [test][test_givenSamePointer_whenDependencyProbesWouldFail_reverts_OperatorOnlySeed], [test][test_givenSamePointer_whenDependencyProbesWouldFail_reverts_RolesOverlapSeed] |

### Unsupported pending-yield assets

These rows concern an RD liability, not an active route. The asset is `Retired` in
RevenueDistributor, its route has been deleted, and `_pendingYieldRecipient[asset]` is positive.
That live-role debt follows the current Yield Recipient, so a changed nonzero recipient must support
the retired asset before the pointer can move.

| ID | Caller | Current pointer | `recipient_` | RD asset | Pending yield | Candidate lookup | Candidate registration | Active-route precondition | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SYR-I03 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | Nonzero | Different nonzero active/enabled compatible policy | Retired vault-share token | Positive | Direct `getVaultConfig(asset)` | Missing, disabled, malformed or reverting | No earlier incompatible Active positive route | RevenueDistributor_YieldRecipientUnavailable(recipient, asset) | Old recipient remains selected; pending yield is not redirected | Covered: [test][test_givenRetiredAssetWithPendingYield_whenIncompatibleRecipientSelected_reverts], [test][test_givenRetiredPendingYield_whenCandidateRegistrationInvalid_revertsAndRollsBack], [test][test_givenRetiredAssetWithPendingYield_whenIncompatibleRecipientSelected_reverts_AdminOnlySeed], [test][test_givenRetiredAssetWithPendingYield_whenIncompatibleRecipientSelected_reverts_OperatorOnlySeed], [test][test_givenRetiredAssetWithPendingYield_whenIncompatibleRecipientSelected_reverts_RolesOverlapSeed], [test][test_givenRetiredPendingYield_whenCandidateRegistrationInvalid_revertsAndRollsBack_AdminOnlySeed], [test][test_givenRetiredPendingYield_whenCandidateRegistrationInvalid_revertsAndRollsBack_OperatorOnlySeed], [test][test_givenRetiredPendingYield_whenCandidateRegistrationInvalid_revertsAndRollsBack_RolesOverlapSeed] |
| SYR-I13 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | Nonzero | Different nonzero active/enabled compatible policy | Retired underlying token | Positive | Enumerate `getVaults()`, then inspect matching underlying | No matching vault, or matching vault is disabled, malformed or reverting | No earlier incompatible Active positive route | RevenueDistributor_YieldRecipientUnavailable(recipient, asset) | Old recipient remains selected; pending yield is not redirected | Covered: [test][test_givenRetiredUnderlyingWithPendingYield_whenUnsupportedRecipientSelected_reverts], [test][test_givenRetiredPendingYield_whenCandidateRegistrationInvalid_revertsAndRollsBack], [test][test_givenRetiredUnderlyingWithPendingYield_whenUnsupportedRecipientSelected_reverts_AdminOnlySeed], [test][test_givenRetiredUnderlyingWithPendingYield_whenUnsupportedRecipientSelected_reverts_OperatorOnlySeed], [test][test_givenRetiredUnderlyingWithPendingYield_whenUnsupportedRecipientSelected_reverts_RolesOverlapSeed], [test][test_givenRetiredPendingYield_whenCandidateRegistrationInvalid_revertsAndRollsBack_AdminOnlySeed], [test][test_givenRetiredPendingYield_whenCandidateRegistrationInvalid_revertsAndRollsBack_OperatorOnlySeed], [test][test_givenRetiredPendingYield_whenCandidateRegistrationInvalid_revertsAndRollsBack_RolesOverlapSeed] |
| SYR-I14 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | Nonzero | Different nonzero active/enabled compatible policy | Multiple Retired assets | Positive for each | Direct or underlying, separately | Earlier asset supported; later asset unsupported | No incompatible Active positive route | RevenueDistributor_YieldRecipientUnavailable(recipient, laterAsset) | Full call rolls back; no pending liability is redirected | Covered: [test][test_givenMultipleRetiredPendingAssets_whenLaterAssetUnsupported_reverts], [test][test_givenMultipleRetiredUnderlyingAssets_whenLaterAssetUnsupported_revertsAndRollsBack], [test][test_givenMultipleRetiredPendingAssets_whenLaterAssetUnsupported_reverts_AdminOnlySeed], [test][test_givenMultipleRetiredPendingAssets_whenLaterAssetUnsupported_reverts_OperatorOnlySeed], [test][test_givenMultipleRetiredPendingAssets_whenLaterAssetUnsupported_reverts_RolesOverlapSeed], [test][test_givenMultipleRetiredUnderlyingAssets_whenLaterAssetUnsupported_revertsAndRollsBack_AdminOnlySeed], [test][test_givenMultipleRetiredUnderlyingAssets_whenLaterAssetUnsupported_revertsAndRollsBack_OperatorOnlySeed], [test][test_givenMultipleRetiredUnderlyingAssets_whenLaterAssetUnsupported_revertsAndRollsBack_RolesOverlapSeed] |
| SYR-I11 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | Nonzero | Different nonzero active/enabled compatible policy | One Retired unsupported asset | Positive | Direct or underlying, separately | Unsupported | An earlier Active positive-route asset is also unsupported | RevenueDistributor_YieldRecipientUnavailable(recipient, activeAsset) | Unchanged; Active routes are validated before pending assets | Covered: [test][test_givenUnsupportedActiveAndPendingAssets_whenRecipientChanges_revertsForActiveFirst], [test][test_givenUnsupportedActiveAndPendingAssets_whenRecipientChanges_revertsForActiveFirst_AdminOnlySeed], [test][test_givenUnsupportedActiveAndPendingAssets_whenRecipientChanges_revertsForActiveFirst_OperatorOnlySeed], [test][test_givenUnsupportedActiveAndPendingAssets_whenRecipientChanges_revertsForActiveFirst_RolesOverlapSeed] |

### Configured-recipient collision

| ID | Caller | Pointer transition | Candidate policy state | Active RD asset state | Candidate asset support | Collision state | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SYR-I04 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | Zero or old nonzero -> different nonzero recipient | Kernel-active, locally enabled and interface-compatible | Fuzz zero/positive routes | Compatible for every positive route checked earlier | Candidate is already an ordinary configured recipient on an Active asset | RevenueDistributor_DuplicateRecipient(candidate) | Unchanged | Covered: [test][test_givenOrdinaryRecipient_whenSelectedAsYieldRecipient_reverts], [test][test_givenCandidateIsConfiguredOnLaterActiveAsset_whenSelected_revertsAndRollsBack], [test][test_givenCandidateConfiguredOnlyOnRetiredAsset_whenSelected_succeeds], [test][test_givenOrdinaryRecipient_whenSelectedAsYieldRecipient_reverts_AdminOnlySeed], [test][test_givenOrdinaryRecipient_whenSelectedAsYieldRecipient_reverts_OperatorOnlySeed], [test][test_givenOrdinaryRecipient_whenSelectedAsYieldRecipient_reverts_RolesOverlapSeed], [test][test_givenCandidateIsConfiguredOnLaterActiveAsset_whenSelected_revertsAndRollsBack_AdminOnlySeed], [test][test_givenCandidateIsConfiguredOnLaterActiveAsset_whenSelected_revertsAndRollsBack_OperatorOnlySeed], [test][test_givenCandidateIsConfiguredOnLaterActiveAsset_whenSelected_revertsAndRollsBack_RolesOverlapSeed], [test][test_givenCandidateConfiguredOnlyOnRetiredAsset_whenSelected_succeeds_AdminOnlySeed], [test][test_givenCandidateConfiguredOnlyOnRetiredAsset_whenSelected_succeeds_OperatorOnlySeed], [test][test_givenCandidateConfiguredOnlyOnRetiredAsset_whenSelected_succeeds_RolesOverlapSeed] |

Active routes are scanned before pending assets; SYR-I11 makes the resulting error precedence explicit when both are incompatible.

## Valid pointer updates

Exercise admin and the current config operator separately. Pending assets refer to RD liabilities: Active assets may still have routes, while Retired assets have no route but can retain an unpaid yield-recipient bucket.

| ID | Caller | Pointer transition | Candidate policy state | RD asset state | Asset form checked on candidate | Asset state on candidate | Pending-yield state | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SYR-P09 | ADMIN_ROLE holder | Zero -> nonzero recipient | Kernel-active, locally enabled and interface-compatible | No positive Active route | Not applicable | No asset lookup required | None | Success | Pointer equals new recipient; one YieldRecipientSet; liabilities unchanged | Covered: [admin seed][test_givenAdmin_whenYieldRecipientSet], [caller and isolation matrix][test_givenZeroPointer_whenPermittedCallerSelectsRecipient_emitsAndPreservesState] |
| SYR-P10 | ADMIN_ROLE holder | Nonzero -> different nonzero recipient | Kernel-active, locally enabled and interface-compatible | No positive Active route | Not applicable | No asset lookup required | None | Success | Pointer equals new recipient; one YieldRecipientSet; liabilities unchanged | Covered: [evidence][test_givenNoPositiveRoutes_whenNonzeroRecipientChanges_succeeds] |
| SYR-P07 | ADMIN_ROLE holder | Nonzero -> different nonzero recipient | Kernel-active, locally enabled and interface-compatible | Active positive route pays a vault share | Direct vault-share lookup | Enabled registration whose returned vault equals the route asset | None | Success | Pointer equals new recipient; one YieldRecipientSet; configured/Treasury debt unchanged | Covered: [evidence][test_givenActiveVaultShareRoute_whenCompatibleYieldRecipientChanges_succeeds] |
| SYR-P08 | ADMIN_ROLE holder | Nonzero -> different nonzero recipient | Kernel-active, locally enabled and interface-compatible | Active positive route pays a vault underlying | Registered-vault enumeration and underlying match | Enabled matching vault registration | None | Success | Pointer equals new recipient; one YieldRecipientSet; configured/Treasury debt unchanged | Covered: [evidence][test_givenActiveUnderlyingRoute_whenCompatibleRecipientChanges_succeeds] |
| SYR-P02 | ADMIN_ROLE holder | Nonzero -> different nonzero recipient | Kernel-active, locally enabled and interface-compatible | Fuzz none/one/multiple Active assets with zero/positive routes | Direct and underlying lookups separately | Every applicable asset has an enabled matching registration | Fuzz one/multiple Active and Retired assets | Success | Every live-role entitlement moves from old role to new recipient; fixed-address entitlements unaffected; one event | Covered: [active pending seed][test_givenYieldPayoutPending_whenYieldRecipientChanges_thenRetryPaysCurrentRecipient], [full matrix][test_givenMultipleActiveAndRetiredYieldDebts_whenRecipientChanges_redirectsOnlyRoleDebt] |
| SYR-P01 | ADMIN_ROLE holder | Nonzero -> `address(0)` candidate recipient | Treasury fallback; no policy lookup | No positive Active route | Not applicable | Not applicable | Independently fuzz none, one and multiple Active/Retired pending assets | Success | Pointer clears; pending yield follows current Treasury fallback; configured debt unchanged; one event | Covered: [retired pending seed][test_givenRetiredAssetWithPendingYield_whenYieldRecipientCleared_thenTreasuryCanRetry], [full matrix][test_givenAnySupportedPendingYieldSet_whenRecipientCleared_redirectsToTreasury] |
| SYR-P03 | ADMIN_ROLE holder | Same nonzero recipient -> same recipient | Still Kernel-active, locally enabled and interface-compatible | Fuzz none/one/multiple Active assets with zero/positive routes | Direct and underlying lookups separately | Every applicable registration remains enabled and matching | Fuzz none/one/multiple Active and Retired assets; all supported | RevenueDistributor_SameAddress(recipient) before candidate probes | Pointer, hashes, liabilities and indexes unchanged; no YieldRecipientSet | Covered: [test][test_givenSelectedCompatibleRecipient_whenSetAgain_reverts], [test][test_givenSameCompatibleRecipientWithAnyAssetStates_whenSetAgain_reverts], [test][test_givenSamePointer_whenDependencyProbesWouldFail_reverts], [test][test_givenSelectedCompatibleRecipient_whenSetAgain_reverts_AdminOnlySeed], [test][test_givenSelectedCompatibleRecipient_whenSetAgain_reverts_OperatorOnlySeed], [test][test_givenSelectedCompatibleRecipient_whenSetAgain_reverts_RolesOverlapSeed], [test][test_givenSameCompatibleRecipientWithAnyAssetStates_whenSetAgain_reverts_AdminOnlySeed], [test][test_givenSameCompatibleRecipientWithAnyAssetStates_whenSetAgain_reverts_OperatorOnlySeed], [test][test_givenSameCompatibleRecipientWithAnyAssetStates_whenSetAgain_reverts_RolesOverlapSeed], [test][test_givenSamePointer_whenDependencyProbesWouldFail_reverts_AdminOnlySeed], [test][test_givenSamePointer_whenDependencyProbesWouldFail_reverts_OperatorOnlySeed], [test][test_givenSamePointer_whenDependencyProbesWouldFail_reverts_RolesOverlapSeed] |
| SYR-P04 | ADMIN_ROLE holder | Zero -> `address(0)` candidate recipient | Treasury fallback; no policy lookup | No positive Active route | Not applicable | Not applicable | Fuzz none/one/multiple Active and Retired assets | RevenueDistributor_SameAddress(address(0)) before asset probes | Pointer, hashes, liabilities and indexes unchanged; no YieldRecipientSet; pending yield keeps Treasury fallback | Covered: [test][test_givenZeroYieldRecipient_whenSetToZeroAgain_reverts], [test][test_givenZeroPointerAndAnyPendingYieldSet_whenSetToZeroAgain_reverts], [test][test_givenSamePointer_whenDependencyProbesWouldFail_reverts], [test][test_givenZeroYieldRecipient_whenSetToZeroAgain_reverts_AdminOnlySeed], [test][test_givenZeroYieldRecipient_whenSetToZeroAgain_reverts_OperatorOnlySeed], [test][test_givenZeroYieldRecipient_whenSetToZeroAgain_reverts_RolesOverlapSeed], [test][test_givenZeroPointerAndAnyPendingYieldSet_whenSetToZeroAgain_reverts_AdminOnlySeed], [test][test_givenZeroPointerAndAnyPendingYieldSet_whenSetToZeroAgain_reverts_OperatorOnlySeed], [test][test_givenZeroPointerAndAnyPendingYieldSet_whenSetToZeroAgain_reverts_RolesOverlapSeed], [test][test_givenSamePointer_whenDependencyProbesWouldFail_reverts_AdminOnlySeed], [test][test_givenSamePointer_whenDependencyProbesWouldFail_reverts_OperatorOnlySeed], [test][test_givenSamePointer_whenDependencyProbesWouldFail_reverts_RolesOverlapSeed] |

Retired duplicate caller IDs: SYR-A02, SYR-I08, SYR-I15, SYR-I16, SYR-I17, SYR-I18, SYR-I19, SYR-I20, SYR-I21, SYR-I22, SYR-I23, SYR-I24, SYR-I25, SYR-I26. Retained caller families include explicit exclusive-role and overlapping-role seeds.

## Canonical candidate metadata

| ID | Caller | Candidate membership | Required metadata | Validator and execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| SYR-D01 | Admin | Active in intended Kernel | Fuzz malformed kernel() response; seed empty,short,oversized,noncanonical | PolicyDependency_InvalidDependency(candidate) | Unchanged | Covered: [test][test_whenCandidateKernelReadIsMalformed_reverts], [test][test_whenCandidateMetadataBoundaries_reverts], [test][test_whenCandidateKernelReadIsMalformed_reverts_AdminOnlySeed], [test][test_whenCandidateKernelReadIsMalformed_reverts_OperatorOnlySeed], [test][test_whenCandidateKernelReadIsMalformed_reverts_RolesOverlapSeed], [test][test_whenCandidateMetadataBoundaries_reverts_AdminOnlySeed], [test][test_whenCandidateMetadataBoundaries_reverts_OperatorOnlySeed], [test][test_whenCandidateMetadataBoundaries_reverts_RolesOverlapSeed] |
| SYR-D02 | Admin | Active in intended Kernel | Fuzz malformed isEnabled() response; seed empty,short,oversized,noncanonical | PolicyDependency_InvalidDependency(candidate) | Unchanged | Covered: [test][test_whenCandidateEnabledReadIsMalformed_reverts], [test][test_whenCandidateMetadataBoundaries_reverts], [test][test_whenCandidateEnabledReadIsMalformed_reverts_AdminOnlySeed], [test][test_whenCandidateEnabledReadIsMalformed_reverts_OperatorOnlySeed], [test][test_whenCandidateEnabledReadIsMalformed_reverts_RolesOverlapSeed], [test][test_whenCandidateMetadataBoundaries_reverts_AdminOnlySeed], [test][test_whenCandidateMetadataBoundaries_reverts_OperatorOnlySeed], [test][test_whenCandidateMetadataBoundaries_reverts_RolesOverlapSeed] |
| SYR-D03 | Admin | Active in intended Kernel | Reports another Kernel | RevenueDistributor_PolicyDependency_KernelMismatch(recipient,expectedKernel,reportedKernel) before readiness | Unchanged | Covered: [test][test_givenCandidateActiveInConsumerKernel_whenReportedKernelDiffers_reverts], [test][test_givenCandidateActiveInConsumerKernel_whenReportedKernelDiffers_reverts_AdminOnlySeed], [test][test_givenCandidateActiveInConsumerKernel_whenReportedKernelDiffers_reverts_OperatorOnlySeed], [test][test_givenCandidateActiveInConsumerKernel_whenReportedKernelDiffers_reverts_RolesOverlapSeed] |

## Failed candidate probes

| ID | Caller | Required getter / fault | Validator and write outcome | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| SYR-D04 | Admin | Kernel or enabled getter reverts | PolicyDependency_InvalidDependency(candidate) | Pointer unchanged; candidate error does not escape | Covered: [test][test_whenCandidateMetadataReverts_reverts], [test][test_whenCandidateMetadataReverts_reverts_AdminOnlySeed], [test][test_whenCandidateMetadataReverts_reverts_OperatorOnlySeed], [test][test_whenCandidateMetadataReverts_reverts_RolesOverlapSeed] |
| SYR-D05 | Admin | Active positive repurchase route; candidate VaultConfig returns noncanonical bool | RevenueDistributor_YieldRecipientUnavailable(candidate,asset) | Old pointer retained; no decode panic | Covered: [test][test_givenActiveRepurchase_whenCandidateVaultBoolMalformed_reverts], [test][test_givenActiveRepurchase_whenCandidateVaultBoolMalformed_reverts_AdminOnlySeed], [test][test_givenActiveRepurchase_whenCandidateVaultBoolMalformed_reverts_OperatorOnlySeed], [test][test_givenActiveRepurchase_whenCandidateVaultBoolMalformed_reverts_RolesOverlapSeed] |
| SYR-D06 | Admin | Active positive repurchase route; getVaults returns noncanonical address word | RevenueDistributor_YieldRecipientUnavailable(candidate,asset) | Old pointer retained; no decode panic | Covered: [test][test_givenActiveRepurchase_whenCandidateVaultListMalformed_reverts], [test][test_givenActiveRepurchase_whenCandidateVaultListMalformed_reverts_AdminOnlySeed], [test][test_givenActiveRepurchase_whenCandidateVaultListMalformed_reverts_OperatorOnlySeed], [test][test_givenActiveRepurchase_whenCandidateVaultListMalformed_reverts_RolesOverlapSeed] |

[test_givenAdmin_whenYieldRecipientSet]: ./setYieldRecipient.t.sol#L25
[test_givenYieldPayoutPending_whenYieldRecipientChanges_thenRetryPaysCurrentRecipient]: ./setYieldRecipient.t.sol#L549
[test_whenUnauthorizedCallerSetsYieldRecipient_reverts]: ./setYieldRecipient.t.sol#L173
[test_givenDisabled_whenOperatorSetsYieldRecipient_reverts]: ./setYieldRecipient.t.sol#L190
[test_givenPolicyInactive_whenOperatorSetsYieldRecipient_reverts]: ./setYieldRecipient.t.sol#L222
[test_givenRetiredAssetWithPendingYield_whenYieldRecipientCleared_thenTreasuryCanRetry]: ./setYieldRecipient.t.sol#L613
[test_givenTreasuryAddress_whenYieldRecipientSet_reverts]: ./setYieldRecipient.t.sol#L153
[test_givenActiveRepurchaseRoute_whenYieldRecipientCleared_reverts]: ./setYieldRecipient.t.sol#L269
[test_givenRetiredAssetWithPendingYield_whenIncompatibleRecipientSelected_reverts]: ./setYieldRecipient.t.sol#L655
[test_givenOrdinaryRecipient_whenSelectedAsYieldRecipient_reverts]: ./setYieldRecipient.t.sol#L509
[test_whenEOASelectedAsYieldRecipient_reverts]: ./setYieldRecipient.t.sol#L126
[test_givenActiveVaultShareRoute_whenUnsupportedYieldRecipientSelected_reverts]: ./setYieldRecipient.t.sol#L325
[test_givenActiveVaultShareRoute_whenCompatibleYieldRecipientChanges_succeeds]: ./setYieldRecipient.t.sol#L302
[test_givenSelectedCompatibleRecipient_whenSetAgain_reverts]: ./setYieldRecipient.t.sol#L69
[test_givenZeroYieldRecipient_whenSetToZeroAgain_reverts]: ./setYieldRecipient.t.sol#L40
[test_givenPolicyInactiveAndDisabled_whenYieldRecipientSet_revertsActivityFirst]: ./setYieldRecipient.t.sol#L230
[test_whenCandidateLacksRequiredInterface_reverts]: ./setYieldRecipient.t.sol#L362
[test_givenActiveUnderlyingRoute_whenUnsupportedRecipientSelected_reverts]: ./setYieldRecipient.t.sol#L420
[test_givenSameRecipientRegistrationDisabled_whenSetAgain_reverts]: ./setYieldRecipient.t.sol#L448
[test_givenNoPositiveRoutes_whenNonzeroRecipientChanges_succeeds]: ./setYieldRecipient.t.sol#L474
[test_givenActiveUnderlyingRoute_whenCompatibleRecipientChanges_succeeds]: ./setYieldRecipient.t.sol#L489
[test_givenRetiredUnderlyingWithPendingYield_whenUnsupportedRecipientSelected_reverts]: ./setYieldRecipient.t.sol#L698
[test_givenMultipleRetiredPendingAssets_whenLaterAssetUnsupported_reverts]: ./setYieldRecipient.t.sol#L728
[test_givenUnsupportedActiveAndPendingAssets_whenRecipientChanges_revertsForActiveFirst]: ./setYieldRecipient.t.sol#L769
[test_givenActiveRepurchaseRoute_whenCandidateRegistrationInvalid_revertsAndRollsBack]: ./setYieldRecipient.t.sol#L1083
[test_givenPolicyActiveEnabledAndCandidate_whenUnauthorizedCallerSetsYieldRecipient_reverts]: ./setYieldRecipient.t.sol#L805
[test_givenAnyPointerAndAssetState_whenExcludedAddressSelected_revertsAndRollsBack]: ./setYieldRecipient.t.sol#L951
[test_givenAnySupportedPendingYieldSet_whenRecipientCleared_redirectsToTreasury]: ./setYieldRecipient.t.sol#L1415
[test_givenCandidateConfiguredOnlyOnRetiredAsset_whenSelected_succeeds]: ./setYieldRecipient.t.sol#L1275
[test_givenCandidateIsConfiguredOnLaterActiveAsset_whenSelected_revertsAndRollsBack]: ./setYieldRecipient.t.sol#L1231
[test_givenInactiveOrDisabledCandidate_whenSetAsDifferentPointer_revertsAndRollsBack]: ./setYieldRecipient.t.sol#L997
[test_givenLaterActiveRepurchaseRoute_whenYieldRecipientCleared_revertsAndRollsBack]: ./setYieldRecipient.t.sol#L1036
[test_givenMultipleActiveAndRetiredYieldDebts_whenRecipientChanges_redirectsOnlyRoleDebt]: ./setYieldRecipient.t.sol#L1346
[test_givenMultipleRetiredUnderlyingAssets_whenLaterAssetUnsupported_revertsAndRollsBack]: ./setYieldRecipient.t.sol#L1176
[test_givenRetiredPendingYield_whenCandidateRegistrationInvalid_revertsAndRollsBack]: ./setYieldRecipient.t.sol#L1131
[test_givenSameCompatibleRecipientWithAnyAssetStates_whenSetAgain_reverts]: ./setYieldRecipient.t.sol#L1465
[test_givenSeededUnauthorizedIdentities_whenYieldRecipientSet_reverts]: ./setYieldRecipient.t.sol#L899
[test_givenDisabledDistributor_whenPermittedCallerSetsAnyYieldRecipient_reverts]: ./setYieldRecipient.t.sol#L919
[test_givenInactiveDistributor_whenPermittedCallerSetsAnyYieldRecipient_reverts]: ./setYieldRecipient.t.sol#L935
[test_givenZeroPointerAndAnyPendingYieldSet_whenSetToZeroAgain_reverts]: ./setYieldRecipient.t.sol#L1520
[test_givenZeroPointer_whenPermittedCallerSelectsRecipient_emitsAndPreservesState]: ./setYieldRecipient.t.sol#L1303
[test_whenCandidatePolicyIsInactiveOrDisabled_reverts]: ./setYieldRecipient.t.sol#L394
[test_givenSamePointer_whenDependencyProbesWouldFail_reverts]: ./setYieldRecipient.t.sol#L1781
[test_whenCandidateKernelReadIsMalformed_reverts]: ./setYieldRecipient.t.sol#L1642
[test_whenCandidateMetadataBoundaries_reverts]: ./setYieldRecipient.t.sol#L1698
[test_whenCandidateEnabledReadIsMalformed_reverts]: ./setYieldRecipient.t.sol#L1670
[test_givenCandidateActiveInConsumerKernel_whenReportedKernelDiffers_reverts]: ./setYieldRecipient.t.sol#L1751
[test_whenCandidateMetadataReverts_reverts]: ./setYieldRecipient.t.sol#L1824
[test_givenActiveRepurchase_whenCandidateVaultBoolMalformed_reverts]: ./setYieldRecipient.t.sol#L1855
[test_givenActiveRepurchase_whenCandidateVaultListMalformed_reverts]: ./setYieldRecipient.t.sol#L1892
[test_givenAdmin_whenYieldRecipientSet_AdminOnlySeed]: ./setYieldRecipient.t.sol#L2135
[test_givenAdmin_whenYieldRecipientSet_OperatorOnlySeed]: ./setYieldRecipient.t.sol#L2140
[test_givenAdmin_whenYieldRecipientSet_RolesOverlapSeed]: ./setYieldRecipient.t.sol#L2145
[test_givenZeroPointer_whenPermittedCallerSelectsRecipient_emitsAndPreservesState_AdminOnlySeed]: ./setYieldRecipient.t.sol#L2840
[test_givenZeroPointer_whenPermittedCallerSelectsRecipient_emitsAndPreservesState_OperatorOnlySeed]: ./setYieldRecipient.t.sol#L2851
[test_givenZeroPointer_whenPermittedCallerSelectsRecipient_emitsAndPreservesState_RolesOverlapSeed]: ./setYieldRecipient.t.sol#L2862
[test_givenYieldPayoutPending_whenYieldRecipientChanges_thenRetryPaysCurrentRecipient_AdminOnlySeed]: ./setYieldRecipient.t.sol#L2768
[test_givenYieldPayoutPending_whenYieldRecipientChanges_thenRetryPaysCurrentRecipient_OperatorOnlySeed]: ./setYieldRecipient.t.sol#L2779
[test_givenYieldPayoutPending_whenYieldRecipientChanges_thenRetryPaysCurrentRecipient_RolesOverlapSeed]: ./setYieldRecipient.t.sol#L2790
[test_givenMultipleActiveAndRetiredYieldDebts_whenRecipientChanges_redirectsOnlyRoleDebt_AdminOnlySeed]: ./setYieldRecipient.t.sol#L2363
[test_givenMultipleActiveAndRetiredYieldDebts_whenRecipientChanges_redirectsOnlyRoleDebt_OperatorOnlySeed]: ./setYieldRecipient.t.sol#L2375
[test_givenMultipleActiveAndRetiredYieldDebts_whenRecipientChanges_redirectsOnlyRoleDebt_RolesOverlapSeed]: ./setYieldRecipient.t.sol#L2387
[test_givenTreasuryAddress_whenYieldRecipientSet_reverts_AdminOnlySeed]: ./setYieldRecipient.t.sol#L2720
[test_givenTreasuryAddress_whenYieldRecipientSet_reverts_OperatorOnlySeed]: ./setYieldRecipient.t.sol#L2725
[test_givenTreasuryAddress_whenYieldRecipientSet_reverts_RolesOverlapSeed]: ./setYieldRecipient.t.sol#L2730
[test_givenAnyPointerAndAssetState_whenExcludedAddressSelected_revertsAndRollsBack_AdminOnlySeed]: ./setYieldRecipient.t.sol#L2150
[test_givenAnyPointerAndAssetState_whenExcludedAddressSelected_revertsAndRollsBack_OperatorOnlySeed]: ./setYieldRecipient.t.sol#L2165
[test_givenAnyPointerAndAssetState_whenExcludedAddressSelected_revertsAndRollsBack_RolesOverlapSeed]: ./setYieldRecipient.t.sol#L2180
[test_whenEOASelectedAsYieldRecipient_reverts_AdminOnlySeed]: ./setYieldRecipient.t.sol#L2978
[test_whenEOASelectedAsYieldRecipient_reverts_OperatorOnlySeed]: ./setYieldRecipient.t.sol#L2988
[test_whenEOASelectedAsYieldRecipient_reverts_RolesOverlapSeed]: ./setYieldRecipient.t.sol#L2993
[test_whenCandidateLacksRequiredInterface_reverts_AdminOnlySeed]: ./setYieldRecipient.t.sol#L2918
[test_whenCandidateLacksRequiredInterface_reverts_OperatorOnlySeed]: ./setYieldRecipient.t.sol#L2923
[test_whenCandidateLacksRequiredInterface_reverts_RolesOverlapSeed]: ./setYieldRecipient.t.sol#L2928
[test_whenCandidatePolicyIsInactiveOrDisabled_reverts_AdminOnlySeed]: ./setYieldRecipient.t.sol#L2963
[test_whenCandidatePolicyIsInactiveOrDisabled_reverts_OperatorOnlySeed]: ./setYieldRecipient.t.sol#L2968
[test_whenCandidatePolicyIsInactiveOrDisabled_reverts_RolesOverlapSeed]: ./setYieldRecipient.t.sol#L2973
[test_givenInactiveOrDisabledCandidate_whenSetAsDifferentPointer_revertsAndRollsBack_AdminOnlySeed]: ./setYieldRecipient.t.sol#L2294
[test_givenInactiveOrDisabledCandidate_whenSetAsDifferentPointer_revertsAndRollsBack_OperatorOnlySeed]: ./setYieldRecipient.t.sol#L2306
[test_givenInactiveOrDisabledCandidate_whenSetAsDifferentPointer_revertsAndRollsBack_RolesOverlapSeed]: ./setYieldRecipient.t.sol#L2318
[test_givenActiveRepurchaseRoute_whenYieldRecipientCleared_reverts_AdminOnlySeed]: ./setYieldRecipient.t.sol#L1970
[test_givenActiveRepurchaseRoute_whenYieldRecipientCleared_reverts_OperatorOnlySeed]: ./setYieldRecipient.t.sol#L1981
[test_givenActiveRepurchaseRoute_whenYieldRecipientCleared_reverts_RolesOverlapSeed]: ./setYieldRecipient.t.sol#L1992
[test_givenLaterActiveRepurchaseRoute_whenYieldRecipientCleared_revertsAndRollsBack_AdminOnlySeed]: ./setYieldRecipient.t.sol#L2330
[test_givenLaterActiveRepurchaseRoute_whenYieldRecipientCleared_revertsAndRollsBack_OperatorOnlySeed]: ./setYieldRecipient.t.sol#L2341
[test_givenLaterActiveRepurchaseRoute_whenYieldRecipientCleared_revertsAndRollsBack_RolesOverlapSeed]: ./setYieldRecipient.t.sol#L2352
[test_givenActiveVaultShareRoute_whenUnsupportedYieldRecipientSelected_reverts_AdminOnlySeed]: ./setYieldRecipient.t.sol#L2102
[test_givenActiveVaultShareRoute_whenUnsupportedYieldRecipientSelected_reverts_OperatorOnlySeed]: ./setYieldRecipient.t.sol#L2113
[test_givenActiveVaultShareRoute_whenUnsupportedYieldRecipientSelected_reverts_RolesOverlapSeed]: ./setYieldRecipient.t.sol#L2124
[test_givenActiveRepurchaseRoute_whenCandidateRegistrationInvalid_revertsAndRollsBack_AdminOnlySeed]: ./setYieldRecipient.t.sol#L1931
[test_givenActiveRepurchaseRoute_whenCandidateRegistrationInvalid_revertsAndRollsBack_OperatorOnlySeed]: ./setYieldRecipient.t.sol#L1944
[test_givenActiveRepurchaseRoute_whenCandidateRegistrationInvalid_revertsAndRollsBack_RolesOverlapSeed]: ./setYieldRecipient.t.sol#L1957
[test_givenActiveUnderlyingRoute_whenUnsupportedRecipientSelected_reverts_AdminOnlySeed]: ./setYieldRecipient.t.sol#L2069
[test_givenActiveUnderlyingRoute_whenUnsupportedRecipientSelected_reverts_OperatorOnlySeed]: ./setYieldRecipient.t.sol#L2080
[test_givenActiveUnderlyingRoute_whenUnsupportedRecipientSelected_reverts_RolesOverlapSeed]: ./setYieldRecipient.t.sol#L2091
[test_givenSameRecipientRegistrationDisabled_whenSetAgain_reverts_AdminOnlySeed]: ./setYieldRecipient.t.sol#L2672
[test_givenSameRecipientRegistrationDisabled_whenSetAgain_reverts_OperatorOnlySeed]: ./setYieldRecipient.t.sol#L2683
[test_givenSameRecipientRegistrationDisabled_whenSetAgain_reverts_RolesOverlapSeed]: ./setYieldRecipient.t.sol#L2694
[test_givenSamePointer_whenDependencyProbesWouldFail_reverts_AdminOnlySeed]: ./setYieldRecipient.t.sol#L2642
[test_givenSamePointer_whenDependencyProbesWouldFail_reverts_OperatorOnlySeed]: ./setYieldRecipient.t.sol#L2652
[test_givenSamePointer_whenDependencyProbesWouldFail_reverts_RolesOverlapSeed]: ./setYieldRecipient.t.sol#L2662
[test_givenRetiredAssetWithPendingYield_whenIncompatibleRecipientSelected_reverts_AdminOnlySeed]: ./setYieldRecipient.t.sol#L2498
[test_givenRetiredAssetWithPendingYield_whenIncompatibleRecipientSelected_reverts_OperatorOnlySeed]: ./setYieldRecipient.t.sol#L2509
[test_givenRetiredAssetWithPendingYield_whenIncompatibleRecipientSelected_reverts_RolesOverlapSeed]: ./setYieldRecipient.t.sol#L2520
[test_givenRetiredPendingYield_whenCandidateRegistrationInvalid_revertsAndRollsBack_AdminOnlySeed]: ./setYieldRecipient.t.sol#L2531
[test_givenRetiredPendingYield_whenCandidateRegistrationInvalid_revertsAndRollsBack_OperatorOnlySeed]: ./setYieldRecipient.t.sol#L2544
[test_givenRetiredPendingYield_whenCandidateRegistrationInvalid_revertsAndRollsBack_RolesOverlapSeed]: ./setYieldRecipient.t.sol#L2557
[test_givenRetiredUnderlyingWithPendingYield_whenUnsupportedRecipientSelected_reverts_AdminOnlySeed]: ./setYieldRecipient.t.sol#L2570
[test_givenRetiredUnderlyingWithPendingYield_whenUnsupportedRecipientSelected_reverts_OperatorOnlySeed]: ./setYieldRecipient.t.sol#L2581
[test_givenRetiredUnderlyingWithPendingYield_whenUnsupportedRecipientSelected_reverts_RolesOverlapSeed]: ./setYieldRecipient.t.sol#L2592
[test_givenMultipleRetiredPendingAssets_whenLaterAssetUnsupported_reverts_AdminOnlySeed]: ./setYieldRecipient.t.sol#L2399
[test_givenMultipleRetiredPendingAssets_whenLaterAssetUnsupported_reverts_OperatorOnlySeed]: ./setYieldRecipient.t.sol#L2410
[test_givenMultipleRetiredPendingAssets_whenLaterAssetUnsupported_reverts_RolesOverlapSeed]: ./setYieldRecipient.t.sol#L2421
[test_givenMultipleRetiredUnderlyingAssets_whenLaterAssetUnsupported_revertsAndRollsBack_AdminOnlySeed]: ./setYieldRecipient.t.sol#L2432
[test_givenMultipleRetiredUnderlyingAssets_whenLaterAssetUnsupported_revertsAndRollsBack_OperatorOnlySeed]: ./setYieldRecipient.t.sol#L2443
[test_givenMultipleRetiredUnderlyingAssets_whenLaterAssetUnsupported_revertsAndRollsBack_RolesOverlapSeed]: ./setYieldRecipient.t.sol#L2454
[test_givenUnsupportedActiveAndPendingAssets_whenRecipientChanges_revertsForActiveFirst_AdminOnlySeed]: ./setYieldRecipient.t.sol#L2735
[test_givenUnsupportedActiveAndPendingAssets_whenRecipientChanges_revertsForActiveFirst_OperatorOnlySeed]: ./setYieldRecipient.t.sol#L2746
[test_givenUnsupportedActiveAndPendingAssets_whenRecipientChanges_revertsForActiveFirst_RolesOverlapSeed]: ./setYieldRecipient.t.sol#L2757
[test_givenOrdinaryRecipient_whenSelectedAsYieldRecipient_reverts_AdminOnlySeed]: ./setYieldRecipient.t.sol#L2465
[test_givenOrdinaryRecipient_whenSelectedAsYieldRecipient_reverts_OperatorOnlySeed]: ./setYieldRecipient.t.sol#L2476
[test_givenOrdinaryRecipient_whenSelectedAsYieldRecipient_reverts_RolesOverlapSeed]: ./setYieldRecipient.t.sol#L2487
[test_givenCandidateIsConfiguredOnLaterActiveAsset_whenSelected_revertsAndRollsBack_AdminOnlySeed]: ./setYieldRecipient.t.sol#L2261
[test_givenCandidateIsConfiguredOnLaterActiveAsset_whenSelected_revertsAndRollsBack_OperatorOnlySeed]: ./setYieldRecipient.t.sol#L2272
[test_givenCandidateIsConfiguredOnLaterActiveAsset_whenSelected_revertsAndRollsBack_RolesOverlapSeed]: ./setYieldRecipient.t.sol#L2283
[test_givenCandidateConfiguredOnlyOnRetiredAsset_whenSelected_succeeds_AdminOnlySeed]: ./setYieldRecipient.t.sol#L2228
[test_givenCandidateConfiguredOnlyOnRetiredAsset_whenSelected_succeeds_OperatorOnlySeed]: ./setYieldRecipient.t.sol#L2239
[test_givenCandidateConfiguredOnlyOnRetiredAsset_whenSelected_succeeds_RolesOverlapSeed]: ./setYieldRecipient.t.sol#L2250
[test_givenSelectedCompatibleRecipient_whenSetAgain_reverts_AdminOnlySeed]: ./setYieldRecipient.t.sol#L2705
[test_givenSelectedCompatibleRecipient_whenSetAgain_reverts_OperatorOnlySeed]: ./setYieldRecipient.t.sol#L2710
[test_givenSelectedCompatibleRecipient_whenSetAgain_reverts_RolesOverlapSeed]: ./setYieldRecipient.t.sol#L2715
[test_givenSameCompatibleRecipientWithAnyAssetStates_whenSetAgain_reverts_AdminOnlySeed]: ./setYieldRecipient.t.sol#L2603
[test_givenSameCompatibleRecipientWithAnyAssetStates_whenSetAgain_reverts_OperatorOnlySeed]: ./setYieldRecipient.t.sol#L2616
[test_givenSameCompatibleRecipientWithAnyAssetStates_whenSetAgain_reverts_RolesOverlapSeed]: ./setYieldRecipient.t.sol#L2629
[test_givenZeroYieldRecipient_whenSetToZeroAgain_reverts_AdminOnlySeed]: ./setYieldRecipient.t.sol#L2873
[test_givenZeroYieldRecipient_whenSetToZeroAgain_reverts_OperatorOnlySeed]: ./setYieldRecipient.t.sol#L2878
[test_givenZeroYieldRecipient_whenSetToZeroAgain_reverts_RolesOverlapSeed]: ./setYieldRecipient.t.sol#L2883
[test_givenZeroPointerAndAnyPendingYieldSet_whenSetToZeroAgain_reverts_AdminOnlySeed]: ./setYieldRecipient.t.sol#L2801
[test_givenZeroPointerAndAnyPendingYieldSet_whenSetToZeroAgain_reverts_OperatorOnlySeed]: ./setYieldRecipient.t.sol#L2814
[test_givenZeroPointerAndAnyPendingYieldSet_whenSetToZeroAgain_reverts_RolesOverlapSeed]: ./setYieldRecipient.t.sol#L2827
[test_whenCandidateKernelReadIsMalformed_reverts_AdminOnlySeed]: ./setYieldRecipient.t.sol#L2903
[test_whenCandidateKernelReadIsMalformed_reverts_OperatorOnlySeed]: ./setYieldRecipient.t.sol#L2908
[test_whenCandidateKernelReadIsMalformed_reverts_RolesOverlapSeed]: ./setYieldRecipient.t.sol#L2913
[test_whenCandidateMetadataBoundaries_reverts_AdminOnlySeed]: ./setYieldRecipient.t.sol#L2933
[test_whenCandidateMetadataBoundaries_reverts_OperatorOnlySeed]: ./setYieldRecipient.t.sol#L2938
[test_whenCandidateMetadataBoundaries_reverts_RolesOverlapSeed]: ./setYieldRecipient.t.sol#L2943
[test_whenCandidateEnabledReadIsMalformed_reverts_AdminOnlySeed]: ./setYieldRecipient.t.sol#L2888
[test_whenCandidateEnabledReadIsMalformed_reverts_OperatorOnlySeed]: ./setYieldRecipient.t.sol#L2893
[test_whenCandidateEnabledReadIsMalformed_reverts_RolesOverlapSeed]: ./setYieldRecipient.t.sol#L2898
[test_givenCandidateActiveInConsumerKernel_whenReportedKernelDiffers_reverts_AdminOnlySeed]: ./setYieldRecipient.t.sol#L2195
[test_givenCandidateActiveInConsumerKernel_whenReportedKernelDiffers_reverts_OperatorOnlySeed]: ./setYieldRecipient.t.sol#L2206
[test_givenCandidateActiveInConsumerKernel_whenReportedKernelDiffers_reverts_RolesOverlapSeed]: ./setYieldRecipient.t.sol#L2217
[test_whenCandidateMetadataReverts_reverts_AdminOnlySeed]: ./setYieldRecipient.t.sol#L2948
[test_whenCandidateMetadataReverts_reverts_OperatorOnlySeed]: ./setYieldRecipient.t.sol#L2953
[test_whenCandidateMetadataReverts_reverts_RolesOverlapSeed]: ./setYieldRecipient.t.sol#L2958
[test_givenActiveRepurchase_whenCandidateVaultBoolMalformed_reverts_AdminOnlySeed]: ./setYieldRecipient.t.sol#L2003
[test_givenActiveRepurchase_whenCandidateVaultBoolMalformed_reverts_OperatorOnlySeed]: ./setYieldRecipient.t.sol#L2014
[test_givenActiveRepurchase_whenCandidateVaultBoolMalformed_reverts_RolesOverlapSeed]: ./setYieldRecipient.t.sol#L2025
[test_givenActiveRepurchase_whenCandidateVaultListMalformed_reverts_AdminOnlySeed]: ./setYieldRecipient.t.sol#L2036
[test_givenActiveRepurchase_whenCandidateVaultListMalformed_reverts_OperatorOnlySeed]: ./setYieldRecipient.t.sol#L2047
[test_givenActiveRepurchase_whenCandidateVaultListMalformed_reverts_RolesOverlapSeed]: ./setYieldRecipient.t.sol#L2058
[test_givenPolicyActiveDisabledAndCandidate_whenUnauthorizedCallerSetsYieldRecipient_reverts]: ./setYieldRecipient.t.sol#L837
[test_givenPolicyInactiveAndCandidate_whenUnauthorizedCallerSetsYieldRecipient_reverts]: ./setYieldRecipient.t.sol#L866
