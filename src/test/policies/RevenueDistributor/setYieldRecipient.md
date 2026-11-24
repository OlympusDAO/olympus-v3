# setYieldRecipient scenario plan

Source: [RevenueDistributor](../../../policies/RevenueDistributor.sol).

Scope: RD global yield destination and compatibility with both active routes and pending historical yield.

Co-located getters: yieldRecipient equals the supplied pointer after success and retains its old value on failure. Recompute assetDistributionHash independently for every affected asset; changing the global yieldRecipient changes its encoded hash even when routes are unchanged. Assert getters remain readable while RD disabled/inactive, with fuzzed getter callers.

Default: the acting policy is Kernel-active. Inactivity tests retain valid caller roles/operator binding and active dependencies; snapshot after deactivation, before the attempted action. Getters remain readable. Preserve existing guard precedence unless a row specifies a change.

## Domains and assertions

Own-policy admission: require Kernel-active RevenueDistributor; own inactivity uses `RevenueDistributor_PolicyNotActive(RD)` before body/input/idempotent work. Require own Kernel activity before local enabled state (when required), caller authority, inputs and dependency checks. Successful body scenarios assume Local active=true, except explicit admission failures.

Only ADMIN may replace the global yield-recipient identity. A selected config operator, former operator, revenue_distributor_admin, emergency or payout recipient without ADMIN is unauthorized. Fuzz unauthorized callers excluding every granted ADMIN holder, including the selected operator. Configuration guard order: nonReentrant, own Kernel activity, local enabled, caller authority, then inputs. Zero is a permitted fallback only when no Active asset has a positive repurchase share. This is a global role destination; historical configured recipients remain fixed. An unchanged pointer, including zero-to-zero, reverts with RevenueDistributor_SameAddress(recipient) before any candidate or asset-support probe. Validators and writes apply the same rule.

Unchanged means balances, liabilities, route configuration, membership indexes and lifecycle state retain their pre-call values; a reverted transaction commits no events. Check exact error data. Getters are permissionless, including while disabled or Kernel-inactive. The permissionless validateSetYieldRecipient validator retains its own active/enabled admission and candidate validation; successful validation does not grant write authority. On a changed-pointer success, the getter equals the requested recipient, YieldRecipientSet is emitted once, custody and raw debt stay unchanged, and all affected entitlements/enumerations reflect the new role address. On same-pointer rejection, no state changes or events occur.

## Authorization

Acceptance is ADMIN-only; production still permits the selected operator pending implementation.
Authorization cases cover ADMIN/operator overlap and unauthorized caller classes once. Candidate,
asset and liability cases use ADMIN; their input domains and assertions are retained.

Own Kernel activity and local enablement precede caller authorization and `recipient_` validation. For SYR-A03, use active/enabled RD and independently fuzz the current pointer (zero/nonzero) and `recipient_` (zero, Treasury, valid policy, EOA, incompatible contract, inactive policy and disabled policy). Exclude only granted ADMIN holders from the caller generator; seed operator-only and proposer-only callers, including unauthorized same-pointer attempts.

| ID | Caller | Crossed domain | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| SYR-A01 | Fuzz ADMIN-only and ADMIN also selected as config operator; seed both | RD active/enabled; changed compatible nonzero `recipient_` | Success | Select recipient | Covered: [test][test_givenAdmin_whenYieldRecipientSet], [test][test_givenZeroPointer_whenPermittedCallerSelectsRecipient_emitsAndPreservesState], [test][test_givenYieldPayoutPending_whenYieldRecipientChanges_thenRetryPaysCurrentRecipient], [test][test_givenMultipleActiveAndRetiredYieldDebts_whenRecipientChanges_redirectsOnlyRoleDebt], [test][test_givenAdmin_whenYieldRecipientSet_AdminOnlySeed], [test][test_givenZeroPointer_whenPermittedCallerSelectsRecipient_emitsAndPreservesState_AdminOnlySeed], [test][test_givenYieldPayoutPending_whenYieldRecipientChanges_thenRetryPaysCurrentRecipient_AdminOnlySeed], [test][test_givenMultipleActiveAndRetiredYieldDebts_whenRecipientChanges_redirectsOnlyRoleDebt_AdminOnlySeed], [direct ADMIN][test_givenAdmin_whenRecipientSelected_preservesDirectGovernance], [ADMIN/operator overlap][test_givenAdminAlsoSelectedOperator_whenRecipientSelected], [operator seeds][test_givenAdmin_whenOperatorSelectionSeeds_preservesDirectGovernance] |
| SYR-A03 | Any caller outside the permitted set, fuzz | Active/enabled RD; full input domain above | ROLES_RequireRole(ADMIN_ROLE) | Unchanged | Covered: [evidence][test_whenUnauthorizedCallerSetsYieldRecipient_reverts], [full matrix][test_givenPolicyActiveEnabledAndCandidate_whenUnauthorizedCallerSetsYieldRecipient_reverts], [seeded identities][test_givenSeededUnauthorizedIdentities_whenYieldRecipientSet_reverts], [selected operator][test_givenSelectedOperatorWithoutAdmin_whenRecipientRotated_reverts], [proposer][test_givenRevenueProposerWithoutAdmin_whenRecipientRotated_reverts], [unauthorized no-op][test_whenCallerHasNoAdmin_whenRecipientUnchanged_reverts], [caller seeds][test_whenUnauthorizedCallerSeeds_whenRecipientUnchanged_reverts] |
| SYR-V01 | Fuzz any caller | Active/enabled RD; compatible changed recipient; validateSetYieldRecipient only | Success, read-only; write remains ADMIN-only | Pointer/funds/routes unchanged | Covered: [validator][test_whenAnyCallerValidatesRecipient_preservesReadOnlySemantics] |

## Lifecycle

For lifecycle rows, fuzz current pointer, active/retired routes, pending yield and `recipient_` across zero, valid and invalid values. Caller variations are covered under Authorization; these validation cases use ADMIN.

| ID | Caller | Local active | Local enabled | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- |
| SYR-L01 | Fuzz permitted callers and unauthorized callers | true | false | NotEnabled() | Unchanged | Covered: [evidence][test_givenDisabled_whenAdminSetsYieldRecipient_reverts], [full matrix][test_givenDisabledDistributor_whenPermittedCallerSetsAnyYieldRecipient_reverts]; [full matrix][test_givenInactiveDistributor_whenPermittedCallerSetsAnyYieldRecipient_reverts], [activity precedence][test_givenPolicyActiveDisabledAndCandidate_whenUnauthorizedCallerSetsYieldRecipient_reverts], [selected operator][test_givenDisabled_whenSelectedOperatorRotates_revertsBeforeAuthority] |
| SYR-L02 | Fuzz permitted callers and unauthorized callers | false | true | RevenueDistributor_PolicyNotActive(RD) | Unchanged | Covered: [evidence][test_givenPolicyInactive_whenAdminSetsYieldRecipient_reverts], [full matrix][test_givenDisabledDistributor_whenPermittedCallerSetsAnyYieldRecipient_reverts]; [full matrix][test_givenInactiveDistributor_whenPermittedCallerSetsAnyYieldRecipient_reverts], [activity precedence][test_givenPolicyInactiveAndCandidate_whenUnauthorizedCallerSetsYieldRecipient_reverts], [selected operator states][test_givenInactive_whenSelectedOperatorRotates_revertsBeforeAuthority], [state seeds][test_givenInactive_whenEnabledSeeds_revertsBeforeAuthority] |
| SYR-L03 | Fuzz permitted callers and unauthorized callers | false | false | RevenueDistributor_PolicyNotActive(RD) before local enablement and caller checks | Unchanged | Covered: [evidence][test_givenPolicyInactiveAndDisabled_whenYieldRecipientSet_revertsActivityFirst], [activity precedence][test_givenPolicyInactiveAndCandidate_whenUnauthorizedCallerSetsYieldRecipient_reverts], [selected operator states][test_givenInactive_whenSelectedOperatorRotates_revertsBeforeAuthority], [state seeds][test_givenInactive_whenEnabledSeeds_revertsBeforeAuthority] |

## Invalid inputs

Validation has two distinct layers: the candidate address must first be a valid active and enabled recipient policy, then that candidate must support every RD asset that needs repurchase delivery. In the tables below, “asset state on candidate” means the vault registration exposed by the proposed yield recipient; it is distinct from the RD asset lifecycle.

### Invalid candidate recipient

These failures occur before any per-asset registration lookup.

| ID | Caller | Current pointer | `recipient_` candidate | Candidate policy state | Active RD assets | Pending-yield assets | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SYR-I01 | ADMIN | Fuzz zero/nonzero | Current Treasury | Excluded role address | Fuzz none/zero/positive routes | Fuzz none/one/multiple | RevenueDistributor_InvalidYieldRecipient(recipient) | Unchanged | Covered: [test][test_givenTreasuryAddress_whenYieldRecipientSet_reverts], [test][test_givenAnyPointerAndAssetState_whenExcludedAddressSelected_revertsAndRollsBack], [test][test_givenTreasuryAddress_whenYieldRecipientSet_reverts_AdminOnlySeed], [test][test_givenAnyPointerAndAssetState_whenExcludedAddressSelected_revertsAndRollsBack_AdminOnlySeed] |
| SYR-I05 | ADMIN | Fuzz zero/nonzero | EOA | Not a recipient policy | Fuzz none/zero/positive routes | Fuzz none/one/multiple | RevenueDistributor_InvalidYieldRecipient(recipient) | Unchanged | Covered: [test][test_whenEOASelectedAsYieldRecipient_reverts], [test][test_givenAnyPointerAndAssetState_whenExcludedAddressSelected_revertsAndRollsBack], [test][test_whenEOASelectedAsYieldRecipient_reverts_AdminOnlySeed], [test][test_givenAnyPointerAndAssetState_whenExcludedAddressSelected_revertsAndRollsBack_AdminOnlySeed] |
| SYR-I06 | ADMIN | Zero | Different contract | Lacks ERC-165, IEnabler or IYieldRepurchaseRecipient; exercise each separately | None | None | RevenueDistributor_InvalidYieldRecipient(recipient) | Unchanged | Covered: [test][test_whenCandidateLacksRequiredInterface_reverts], [test][test_whenCandidateLacksRequiredInterface_reverts_AdminOnlySeed] |
| SYR-I07 | ADMIN | Different nonzero pointer | Different recipient | Interface-compatible but Kernel-inactive or locally disabled | Fuzz none/zero/positive routes | Fuzz none/one/multiple | PolicyDependency_NotActive(recipient) | Unchanged; same-pointer inputs use SYR-P03 | Covered: [test][test_whenCandidatePolicyIsInactiveOrDisabled_reverts], [test][test_givenInactiveOrDisabledCandidate_whenSetAsDifferentPointer_revertsAndRollsBack], [test][test_whenCandidatePolicyIsInactiveOrDisabled_reverts_AdminOnlySeed], [test][test_givenInactiveOrDisabledCandidate_whenSetAsDifferentPointer_revertsAndRollsBack_AdminOnlySeed] |

### Unsupported active-route assets

These rows concern an asset that is `Active` in RevenueDistributor and has nonzero repurchase BPS.
The “candidate registration” column describes the separate vault record returned by the proposed
Yield Recipient. A zero current pointer is impossible in these rows: RevenueDistributor will not
create a positive repurchase route until a nonzero compatible Yield Recipient is selected.

| ID | Caller | Current pointer | `recipient_` | RD asset | Repurchase BPS | Candidate lookup | Candidate registration | Other RD assets | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SYR-I02 | ADMIN | Nonzero | Zero | Active | Positive | None; zero selects Treasury fallback | Unsupported by definition because no Yield Recipient policy is selected | Fuzz pending-yield assets | RevenueDistributor_YieldRecipientUnavailable(address(0), asset) | Unchanged; later-asset failure rolls back the full call | Covered: [test][test_givenActiveRepurchaseRoute_whenYieldRecipientCleared_reverts], [test][test_givenLaterActiveRepurchaseRoute_whenYieldRecipientCleared_revertsAndRollsBack], [test][test_givenActiveRepurchaseRoute_whenYieldRecipientCleared_reverts_AdminOnlySeed], [test][test_givenLaterActiveRepurchaseRoute_whenYieldRecipientCleared_revertsAndRollsBack_AdminOnlySeed] |
| SYR-I09 | ADMIN | Nonzero | Different nonzero active/enabled compatible policy | Active vault-share token | Positive | Direct `getVaultConfig(asset)` | Missing, disabled, malformed or reverting; no enabled underlying match | Earlier assets supported; fuzz none/one/multiple | RevenueDistributor_YieldRecipientUnavailable(recipient, asset) | New recipient is not selected; all earlier checks leave state unchanged | Covered: [test][test_givenActiveVaultShareRoute_whenUnsupportedYieldRecipientSelected_reverts], [test][test_givenActiveRepurchaseRoute_whenCandidateRegistrationInvalid_revertsAndRollsBack], [test][test_givenActiveVaultShareRoute_whenUnsupportedYieldRecipientSelected_reverts_AdminOnlySeed], [test][test_givenActiveRepurchaseRoute_whenCandidateRegistrationInvalid_revertsAndRollsBack_AdminOnlySeed] |
| SYR-I10 | ADMIN | Nonzero | Different nonzero active/enabled compatible policy | Active underlying token | Positive | Enumerate `getVaults()`, then inspect matching underlying | No matching vault, or matching vault is disabled, malformed or reverting; no enabled direct match | Earlier assets supported; fuzz none/one/multiple | RevenueDistributor_YieldRecipientUnavailable(recipient, asset) | New recipient is not selected; all earlier checks leave state unchanged | Covered: [test][test_givenActiveUnderlyingRoute_whenUnsupportedRecipientSelected_reverts], [test][test_givenActiveRepurchaseRoute_whenCandidateRegistrationInvalid_revertsAndRollsBack], [test][test_givenActiveUnderlyingRoute_whenUnsupportedRecipientSelected_reverts_AdminOnlySeed], [test][test_givenActiveRepurchaseRoute_whenCandidateRegistrationInvalid_revertsAndRollsBack_AdminOnlySeed] |

### Unsupported pending-yield assets

These rows concern an RD liability, not an active route. The asset is `Retired` in
RevenueDistributor, its route has been deleted, and `_pendingYieldRecipient[asset]` is positive.
That live-role debt follows the current Yield Recipient, so a changed nonzero recipient must support
the retired asset before the pointer can move.

| ID | Caller | Current pointer | `recipient_` | RD asset | Pending yield | Candidate lookup | Candidate registration | Active-route precondition | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SYR-I03 | ADMIN | Nonzero | Different nonzero active/enabled compatible policy | Retired vault-share token | Positive | Direct `getVaultConfig(asset)` | Missing, disabled, malformed or reverting | No earlier incompatible Active positive route | RevenueDistributor_YieldRecipientUnavailable(recipient, asset) | Old recipient remains selected; pending yield is not redirected | Covered: [test][test_givenRetiredAssetWithPendingYield_whenIncompatibleRecipientSelected_reverts], [test][test_givenRetiredPendingYield_whenCandidateRegistrationInvalid_revertsAndRollsBack], [test][test_givenRetiredAssetWithPendingYield_whenIncompatibleRecipientSelected_reverts_AdminOnlySeed], [test][test_givenRetiredPendingYield_whenCandidateRegistrationInvalid_revertsAndRollsBack_AdminOnlySeed] |
| SYR-I13 | ADMIN | Nonzero | Different nonzero active/enabled compatible policy | Retired underlying token | Positive | Enumerate `getVaults()`, then inspect matching underlying | No matching vault, or matching vault is disabled, malformed or reverting | No earlier incompatible Active positive route | RevenueDistributor_YieldRecipientUnavailable(recipient, asset) | Old recipient remains selected; pending yield is not redirected | Covered: [test][test_givenRetiredUnderlyingWithPendingYield_whenUnsupportedRecipientSelected_reverts], [test][test_givenRetiredPendingYield_whenCandidateRegistrationInvalid_revertsAndRollsBack], [test][test_givenRetiredUnderlyingWithPendingYield_whenUnsupportedRecipientSelected_reverts_AdminOnlySeed], [test][test_givenRetiredPendingYield_whenCandidateRegistrationInvalid_revertsAndRollsBack_AdminOnlySeed] |
| SYR-I14 | ADMIN | Nonzero | Different nonzero active/enabled compatible policy | Multiple Retired assets | Positive for each | Direct or underlying, separately | Earlier asset supported; later asset unsupported | No incompatible Active positive route | RevenueDistributor_YieldRecipientUnavailable(recipient, laterAsset) | Full call rolls back; no pending liability is redirected | Covered: [test][test_givenMultipleRetiredPendingAssets_whenLaterAssetUnsupported_reverts], [test][test_givenMultipleRetiredUnderlyingAssets_whenLaterAssetUnsupported_revertsAndRollsBack], [test][test_givenMultipleRetiredPendingAssets_whenLaterAssetUnsupported_reverts_AdminOnlySeed], [test][test_givenMultipleRetiredUnderlyingAssets_whenLaterAssetUnsupported_revertsAndRollsBack_AdminOnlySeed] |
| SYR-I11 | ADMIN | Nonzero | Different nonzero active/enabled compatible policy | One Retired unsupported asset | Positive | Direct or underlying, separately | Unsupported | An earlier Active positive-route asset is also unsupported | RevenueDistributor_YieldRecipientUnavailable(recipient, activeAsset) | Unchanged; Active routes are validated before pending assets | Covered: [test][test_givenUnsupportedActiveAndPendingAssets_whenRecipientChanges_revertsForActiveFirst], [test][test_givenUnsupportedActiveAndPendingAssets_whenRecipientChanges_revertsForActiveFirst_AdminOnlySeed] |

### Configured-recipient collision

| ID | Caller | Pointer transition | Candidate policy state | Active RD asset state | Candidate asset support | Collision state | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SYR-I04 | ADMIN | Zero or old nonzero -> different nonzero recipient | Kernel-active, locally enabled and interface-compatible | Fuzz zero/positive routes | Compatible for every positive route checked earlier | Candidate is already an ordinary configured recipient on an Active asset | RevenueDistributor_DuplicateRecipient(candidate) | Unchanged | Covered: [test][test_givenOrdinaryRecipient_whenSelectedAsYieldRecipient_reverts], [test][test_givenCandidateIsConfiguredOnLaterActiveAsset_whenSelected_revertsAndRollsBack], [test][test_givenCandidateConfiguredOnlyOnRetiredAsset_whenSelected_succeeds], [test][test_givenOrdinaryRecipient_whenSelectedAsYieldRecipient_reverts_AdminOnlySeed], [test][test_givenCandidateIsConfiguredOnLaterActiveAsset_whenSelected_revertsAndRollsBack_AdminOnlySeed], [test][test_givenCandidateConfiguredOnlyOnRetiredAsset_whenSelected_succeeds_AdminOnlySeed] |

Active routes are scanned before pending assets; SYR-I11 makes the resulting error precedence explicit when both are incompatible.

## Valid pointer updates

Caller variations are covered under Authorization; these validation cases use ADMIN. Pending assets refer to RD liabilities: Active assets may still have routes, while Retired assets have no route but can retain an unpaid yield-recipient bucket.

| ID | Caller | Pointer transition | Candidate policy state | RD asset state | Asset form checked on candidate | Asset state on candidate | Pending-yield state | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SYR-P09 | ADMIN_ROLE holder | Zero -> nonzero recipient | Kernel-active, locally enabled and interface-compatible | No positive Active route | Not applicable | No asset lookup required | None | Success | Pointer equals new recipient; one YieldRecipientSet; liabilities unchanged | Covered: [admin seed][test_givenAdmin_whenYieldRecipientSet], [caller and isolation matrix][test_givenZeroPointer_whenPermittedCallerSelectsRecipient_emitsAndPreservesState] |
| SYR-P10 | ADMIN_ROLE holder | Nonzero -> different nonzero recipient | Kernel-active, locally enabled and interface-compatible | No positive Active route | Not applicable | No asset lookup required | None | Success | Pointer equals new recipient; one YieldRecipientSet; liabilities unchanged | Covered: [evidence][test_givenNoPositiveRoutes_whenNonzeroRecipientChanges_succeeds] |
| SYR-P07 | ADMIN_ROLE holder | Nonzero -> different nonzero recipient | Kernel-active, locally enabled and interface-compatible | Active positive route pays a vault share | Direct vault-share lookup | Enabled registration whose returned vault equals the route asset | None | Success | Pointer equals new recipient; one YieldRecipientSet; configured/Treasury debt unchanged | Covered: [evidence][test_givenActiveVaultShareRoute_whenCompatibleYieldRecipientChanges_succeeds] |
| SYR-P08 | ADMIN_ROLE holder | Nonzero -> different nonzero recipient | Kernel-active, locally enabled and interface-compatible | Active positive route pays a vault underlying | Registered-vault enumeration and underlying match | Enabled matching vault registration | None | Success | Pointer equals new recipient; one YieldRecipientSet; configured/Treasury debt unchanged | Covered: [evidence][test_givenActiveUnderlyingRoute_whenCompatibleRecipientChanges_succeeds] |
| SYR-P12 | ADMIN_ROLE holder | Nonzero -> different nonzero recipient | Kernel-active, locally enabled and interface-compatible | Active positive route pays a separate vault share token | Enumerate a canonical list of 2,046 registered vaults | First vault accepts the share token, which differs from the vault and underlying addresses | None | Success | Pointer equals new recipient and emits YieldRecipientSet | Covered: [test][test_givenSeparateShareRoute_whenCompatibleRecipientReturnsLargeVaultList] |
| SYR-P02 | ADMIN_ROLE holder | Nonzero -> different nonzero recipient | Kernel-active, locally enabled and interface-compatible | Fuzz none/one/multiple Active assets with zero/positive routes | Direct and underlying lookups separately | Every applicable asset has an enabled matching registration | Fuzz one/multiple Active and Retired assets | Success | Every live-role entitlement moves from old role to new recipient; fixed-address entitlements unaffected; one event | Covered: [active pending seed][test_givenYieldPayoutPending_whenYieldRecipientChanges_thenRetryPaysCurrentRecipient], [full matrix][test_givenMultipleActiveAndRetiredYieldDebts_whenRecipientChanges_redirectsOnlyRoleDebt] |
| SYR-P01 | ADMIN_ROLE holder | Nonzero -> `address(0)` candidate recipient | Treasury fallback; no policy lookup | No positive Active route | Not applicable | Not applicable | Independently fuzz none, one and multiple Active/Retired pending assets | Success | Pointer clears; pending yield follows current Treasury fallback; configured debt unchanged; one event | Covered: [retired pending seed][test_givenRetiredAssetWithPendingYield_whenYieldRecipientCleared_thenTreasuryCanRetry], [full matrix][test_givenAnySupportedPendingYieldSet_whenRecipientCleared_redirectsToTreasury] |
| SYR-P03 | ADMIN_ROLE holder | Same nonzero recipient -> same recipient | Selected nonzero policy; metadata may remain valid or become invalid/reverting | Fuzz none/one/multiple Active assets with zero/positive routes | Direct and underlying lookups separately | Registration may remain valid or become missing, disabled, malformed or reverting | Fuzz none/one/multiple Active and Retired assets; all supported | RevenueDistributor_SameAddress(recipient) before candidate probes | Pointer, hashes, liabilities and indexes unchanged; no YieldRecipientSet | Covered: [test][test_givenSelectedCompatibleRecipient_whenSetAgain_reverts], [test][test_givenSameCompatibleRecipientWithAnyAssetStates_whenSetAgain_reverts], [test][test_givenSamePointer_whenDependencyProbesWouldFail_reverts], [test][test_givenSelectedCompatibleRecipient_whenSetAgain_reverts_AdminOnlySeed], [test][test_givenSameCompatibleRecipientWithAnyAssetStates_whenSetAgain_reverts_AdminOnlySeed], [test][test_givenSamePointer_whenDependencyProbesWouldFail_reverts_AdminOnlySeed], [disabled registration][test_givenSameRecipientRegistrationDisabled_whenSetAgain_reverts], [seed][test_givenSameRecipientRegistrationDisabled_whenSetAgain_reverts_AdminOnlySeed] |
| SYR-P04 | ADMIN_ROLE holder | Zero -> `address(0)` candidate recipient | Treasury fallback; no policy lookup | No positive Active route | Not applicable | Not applicable | Fuzz none/one/multiple Active and Retired assets | RevenueDistributor_SameAddress(address(0)) before asset probes | Pointer, hashes, liabilities and indexes unchanged; no YieldRecipientSet; pending yield keeps Treasury fallback | Covered: [test][test_givenZeroYieldRecipient_whenSetToZeroAgain_reverts], [test][test_givenZeroPointerAndAnyPendingYieldSet_whenSetToZeroAgain_reverts], [test][test_givenSamePointer_whenDependencyProbesWouldFail_reverts], [test][test_givenZeroYieldRecipient_whenSetToZeroAgain_reverts_AdminOnlySeed], [test][test_givenZeroPointerAndAnyPendingYieldSet_whenSetToZeroAgain_reverts_AdminOnlySeed], [test][test_givenSamePointer_whenDependencyProbesWouldFail_reverts_AdminOnlySeed] |

Retired duplicate caller IDs: SYR-A02, SYR-I08, SYR-I15, SYR-I16, SYR-I17, SYR-I18, SYR-I19, SYR-I20, SYR-I21, SYR-I22, SYR-I23, SYR-I24, SYR-I25, SYR-I26. Caller overlap is retained in Authorization; duplicate caller-only seed wrappers are removed. SYR-I12 is consolidated into SYR-P03. Temporary review IDs SYR-A04, SYR-A05, SYR-A06, SYR-P11, SYR-L04 and SYR-L05 were consolidated into the existing authorization/lifecycle rows.

## Canonical candidate metadata

| ID | Caller | Candidate membership | Required metadata | Validator and execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| SYR-D01 | Admin | Active in intended Kernel | Fuzz malformed kernel() response; seed empty,short,oversized,noncanonical | PolicyDependency_InvalidDependency(candidate) | Unchanged | Covered: [test][test_whenCandidateKernelReadIsMalformed_reverts], [test][test_whenCandidateMetadataBoundaries_reverts], [test][test_whenCandidateKernelReadIsMalformed_reverts_AdminOnlySeed], [test][test_whenCandidateMetadataBoundaries_reverts_AdminOnlySeed] |
| SYR-D02 | Admin | Active in intended Kernel | Fuzz malformed isEnabled() response; seed empty,short,oversized,noncanonical | PolicyDependency_InvalidDependency(candidate) | Unchanged | Covered: [test][test_whenCandidateEnabledReadIsMalformed_reverts], [test][test_whenCandidateMetadataBoundaries_reverts], [test][test_whenCandidateEnabledReadIsMalformed_reverts_AdminOnlySeed], [test][test_whenCandidateMetadataBoundaries_reverts_AdminOnlySeed] |
| SYR-D03 | Admin | Active in intended Kernel | Reports another Kernel | RevenueDistributor_PolicyDependency_KernelMismatch(recipient,expectedKernel,reportedKernel) before readiness | Unchanged | Covered: [test][test_givenCandidateActiveInConsumerKernel_whenReportedKernelDiffers_reverts], [test][test_givenCandidateActiveInConsumerKernel_whenReportedKernelDiffers_reverts_AdminOnlySeed] |

## Failed candidate probes

| ID | Caller | Required getter / fault | Validator and write outcome | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| SYR-D04 | Admin | Kernel or enabled getter reverts | PolicyDependency_InvalidDependency(candidate) | Pointer unchanged; candidate error does not escape | Covered: [test][test_whenCandidateMetadataReverts_reverts], [test][test_whenCandidateMetadataReverts_reverts_AdminOnlySeed] |
| SYR-D05 | Admin | Active positive repurchase route; candidate VaultConfig returns noncanonical bool | RevenueDistributor_YieldRecipientUnavailable(candidate,asset) | Old pointer retained; no decode panic | Covered: [test][test_givenActiveRepurchase_whenCandidateVaultBoolMalformed_reverts], [test][test_givenActiveRepurchase_whenCandidateVaultBoolMalformed_reverts_AdminOnlySeed] |
| SYR-D06 | Admin | Active positive repurchase route; getVaults returns noncanonical address word | RevenueDistributor_YieldRecipientUnavailable(candidate,asset) | Old pointer retained; no decode panic | Covered: [test][test_givenActiveRepurchase_whenCandidateVaultListMalformed_reverts], [test][test_givenActiveRepurchase_whenCandidateVaultListMalformed_reverts_AdminOnlySeed] |

## Callbacks

| ID | Caller | Local active | Local enabled | Boundary | Expected outcome | Test |
| --- | --- | --- | --- | --- | --- | --- |
| SYR-C01 | Callback with ADMIN | true | true | Authorized nested rotation during token payout | Existing reentrancy error before role/input checks; outer accounting once or rolls back as specified | Covered: [authorized otherwise-valid callback][test_givenAuthorizedRecipientCallback_whenPointerRotationAttempted_outerDistributionPaysOnce] |

[test_givenAdmin_whenYieldRecipientSet]: ./setYieldRecipient.t.sol#L34
[test_givenYieldPayoutPending_whenYieldRecipientChanges_thenRetryPaysCurrentRecipient]: ./setYieldRecipient.t.sol#L560
[test_whenUnauthorizedCallerSetsYieldRecipient_reverts]: ./setYieldRecipient.t.sol#L164
[test_givenDisabled_whenAdminSetsYieldRecipient_reverts]: ./setYieldRecipient.t.sol#L175
[test_givenPolicyInactive_whenAdminSetsYieldRecipient_reverts]: ./setYieldRecipient.t.sol#L207
[test_givenRetiredAssetWithPendingYield_whenYieldRecipientCleared_thenTreasuryCanRetry]: ./setYieldRecipient.t.sol#L622
[test_givenTreasuryAddress_whenYieldRecipientSet_reverts]: ./setYieldRecipient.t.sol#L148
[test_givenActiveRepurchaseRoute_whenYieldRecipientCleared_reverts]: ./setYieldRecipient.t.sol#L254
[test_givenRetiredAssetWithPendingYield_whenIncompatibleRecipientSelected_reverts]: ./setYieldRecipient.t.sol#L664
[test_givenOrdinaryRecipient_whenSelectedAsYieldRecipient_reverts]: ./setYieldRecipient.t.sol#L522
[test_whenEOASelectedAsYieldRecipient_reverts]: ./setYieldRecipient.t.sol#L123
[test_givenActiveVaultShareRoute_whenUnsupportedYieldRecipientSelected_reverts]: ./setYieldRecipient.t.sol#L308
[test_givenActiveVaultShareRoute_whenCompatibleYieldRecipientChanges_succeeds]: ./setYieldRecipient.t.sol#L285
[test_givenSelectedCompatibleRecipient_whenSetAgain_reverts]: ./setYieldRecipient.t.sol#L70
[test_givenZeroYieldRecipient_whenSetToZeroAgain_reverts]: ./setYieldRecipient.t.sol#L45
[test_givenPolicyInactiveAndDisabled_whenYieldRecipientSet_revertsActivityFirst]: ./setYieldRecipient.t.sol#L215
[test_whenCandidateLacksRequiredInterface_reverts]: ./setYieldRecipient.t.sol#L343
[test_givenActiveUnderlyingRoute_whenUnsupportedRecipientSelected_reverts]: ./setYieldRecipient.t.sol#L397
[test_givenSameRecipientRegistrationDisabled_whenSetAgain_reverts]: ./setYieldRecipient.t.sol#L423
[test_givenNoPositiveRoutes_whenNonzeroRecipientChanges_succeeds]: ./setYieldRecipient.t.sol#L447
[test_givenActiveUnderlyingRoute_whenCompatibleRecipientChanges_succeeds]: ./setYieldRecipient.t.sol#L462
[test_givenSeparateShareRoute_whenCompatibleRecipientReturnsLargeVaultList]: ./setYieldRecipient.t.sol#L478
[test_givenRetiredUnderlyingWithPendingYield_whenUnsupportedRecipientSelected_reverts]: ./setYieldRecipient.t.sol#L705
[test_givenMultipleRetiredPendingAssets_whenLaterAssetUnsupported_reverts]: ./setYieldRecipient.t.sol#L733
[test_givenUnsupportedActiveAndPendingAssets_whenRecipientChanges_revertsForActiveFirst]: ./setYieldRecipient.t.sol#L772
[test_givenActiveRepurchaseRoute_whenCandidateRegistrationInvalid_revertsAndRollsBack]: ./setYieldRecipient.t.sol#L1068
[test_givenPolicyActiveEnabledAndCandidate_whenUnauthorizedCallerSetsYieldRecipient_reverts]: ./setYieldRecipient.t.sol#L806
[test_givenAnyPointerAndAssetState_whenExcludedAddressSelected_revertsAndRollsBack]: ./setYieldRecipient.t.sol#L942
[test_givenAnySupportedPendingYieldSet_whenRecipientCleared_redirectsToTreasury]: ./setYieldRecipient.t.sol#L1386
[test_givenCandidateConfiguredOnlyOnRetiredAsset_whenSelected_succeeds]: ./setYieldRecipient.t.sol#L1252
[test_givenCandidateIsConfiguredOnLaterActiveAsset_whenSelected_revertsAndRollsBack]: ./setYieldRecipient.t.sol#L1210
[test_givenInactiveOrDisabledCandidate_whenSetAsDifferentPointer_revertsAndRollsBack]: ./setYieldRecipient.t.sol#L986
[test_givenLaterActiveRepurchaseRoute_whenYieldRecipientCleared_revertsAndRollsBack]: ./setYieldRecipient.t.sol#L1023
[test_givenMultipleActiveAndRetiredYieldDebts_whenRecipientChanges_redirectsOnlyRoleDebt]: ./setYieldRecipient.t.sol#L1319
[test_givenMultipleRetiredUnderlyingAssets_whenLaterAssetUnsupported_revertsAndRollsBack]: ./setYieldRecipient.t.sol#L1157
[test_givenRetiredPendingYield_whenCandidateRegistrationInvalid_revertsAndRollsBack]: ./setYieldRecipient.t.sol#L1114
[test_givenSameCompatibleRecipientWithAnyAssetStates_whenSetAgain_reverts]: ./setYieldRecipient.t.sol#L1435
[test_givenSeededUnauthorizedIdentities_whenYieldRecipientSet_reverts]: ./setYieldRecipient.t.sol#L895
[test_givenDisabledDistributor_whenPermittedCallerSetsAnyYieldRecipient_reverts]: ./setYieldRecipient.t.sol#L910
[test_givenInactiveDistributor_whenPermittedCallerSetsAnyYieldRecipient_reverts]: ./setYieldRecipient.t.sol#L926
[test_givenZeroPointerAndAnyPendingYieldSet_whenSetToZeroAgain_reverts]: ./setYieldRecipient.t.sol#L1488
[test_givenZeroPointer_whenPermittedCallerSelectsRecipient_emitsAndPreservesState]: ./setYieldRecipient.t.sol#L1278
[test_whenCandidatePolicyIsInactiveOrDisabled_reverts]: ./setYieldRecipient.t.sol#L373
[test_givenSamePointer_whenDependencyProbesWouldFail_reverts]: ./setYieldRecipient.t.sol#L1702
[test_whenCandidateKernelReadIsMalformed_reverts]: ./setYieldRecipient.t.sol#L1608
[test_whenCandidateMetadataBoundaries_reverts]: ./setYieldRecipient.t.sol#L1660
[test_whenCandidateEnabledReadIsMalformed_reverts]: ./setYieldRecipient.t.sol#L1634
[test_givenCandidateActiveInConsumerKernel_whenReportedKernelDiffers_reverts]: ./setYieldRecipient.t.sol#L1674
[test_whenCandidateMetadataReverts_reverts]: ./setYieldRecipient.t.sol#L1743
[test_givenActiveRepurchase_whenCandidateVaultBoolMalformed_reverts]: ./setYieldRecipient.t.sol#L1772
[test_givenActiveRepurchase_whenCandidateVaultListMalformed_reverts]: ./setYieldRecipient.t.sol#L1807
[test_givenAdmin_whenYieldRecipientSet_AdminOnlySeed]: ./setYieldRecipient.t.sol#L1892
[test_givenZeroPointer_whenPermittedCallerSelectsRecipient_emitsAndPreservesState_AdminOnlySeed]: ./setYieldRecipient.t.sol#L2078
[test_givenYieldPayoutPending_whenYieldRecipientChanges_thenRetryPaysCurrentRecipient_AdminOnlySeed]: ./setYieldRecipient.t.sol#L2058
[test_givenMultipleActiveAndRetiredYieldDebts_whenRecipientChanges_redirectsOnlyRoleDebt_AdminOnlySeed]: ./setYieldRecipient.t.sol#L1954
[test_givenTreasuryAddress_whenYieldRecipientSet_reverts_AdminOnlySeed]: ./setYieldRecipient.t.sol#L2044
[test_givenAnyPointerAndAssetState_whenExcludedAddressSelected_revertsAndRollsBack_AdminOnlySeed]: ./setYieldRecipient.t.sol#L1897
[test_whenEOASelectedAsYieldRecipient_reverts_AdminOnlySeed]: ./setYieldRecipient.t.sol#L2122
[test_whenCandidateLacksRequiredInterface_reverts_AdminOnlySeed]: ./setYieldRecipient.t.sol#L2102
[test_whenCandidatePolicyIsInactiveOrDisabled_reverts_AdminOnlySeed]: ./setYieldRecipient.t.sol#L2117
[test_givenInactiveOrDisabledCandidate_whenSetAsDifferentPointer_revertsAndRollsBack_AdminOnlySeed]: ./setYieldRecipient.t.sol#L1935
[test_givenActiveRepurchaseRoute_whenYieldRecipientCleared_reverts_AdminOnlySeed]: ./setYieldRecipient.t.sol#L1855
[test_givenLaterActiveRepurchaseRoute_whenYieldRecipientCleared_revertsAndRollsBack_AdminOnlySeed]: ./setYieldRecipient.t.sol#L1945
[test_givenActiveVaultShareRoute_whenUnsupportedYieldRecipientSelected_reverts_AdminOnlySeed]: ./setYieldRecipient.t.sol#L1883
[test_givenActiveRepurchaseRoute_whenCandidateRegistrationInvalid_revertsAndRollsBack_AdminOnlySeed]: ./setYieldRecipient.t.sol#L1844
[test_givenActiveUnderlyingRoute_whenUnsupportedRecipientSelected_reverts_AdminOnlySeed]: ./setYieldRecipient.t.sol#L1876
[test_givenSameRecipientRegistrationDisabled_whenSetAgain_reverts_AdminOnlySeed]: ./setYieldRecipient.t.sol#L2032
[test_givenSamePointer_whenDependencyProbesWouldFail_reverts_AdminOnlySeed]: ./setYieldRecipient.t.sol#L2027
[test_givenRetiredAssetWithPendingYield_whenIncompatibleRecipientSelected_reverts_AdminOnlySeed]: ./setYieldRecipient.t.sol#L1987
[test_givenRetiredPendingYield_whenCandidateRegistrationInvalid_revertsAndRollsBack_AdminOnlySeed]: ./setYieldRecipient.t.sol#L1996
[test_givenRetiredUnderlyingWithPendingYield_whenUnsupportedRecipientSelected_reverts_AdminOnlySeed]: ./setYieldRecipient.t.sol#L2007
[test_givenMultipleRetiredPendingAssets_whenLaterAssetUnsupported_reverts_AdminOnlySeed]: ./setYieldRecipient.t.sol#L1964
[test_givenMultipleRetiredUnderlyingAssets_whenLaterAssetUnsupported_revertsAndRollsBack_AdminOnlySeed]: ./setYieldRecipient.t.sol#L1971
[test_givenUnsupportedActiveAndPendingAssets_whenRecipientChanges_revertsForActiveFirst_AdminOnlySeed]: ./setYieldRecipient.t.sol#L2049
[test_givenOrdinaryRecipient_whenSelectedAsYieldRecipient_reverts_AdminOnlySeed]: ./setYieldRecipient.t.sol#L1980
[test_givenCandidateIsConfiguredOnLaterActiveAsset_whenSelected_revertsAndRollsBack_AdminOnlySeed]: ./setYieldRecipient.t.sol#L1926
[test_givenCandidateConfiguredOnlyOnRetiredAsset_whenSelected_succeeds_AdminOnlySeed]: ./setYieldRecipient.t.sol#L1919
[test_givenSelectedCompatibleRecipient_whenSetAgain_reverts_AdminOnlySeed]: ./setYieldRecipient.t.sol#L2039
[test_givenSameCompatibleRecipientWithAnyAssetStates_whenSetAgain_reverts_AdminOnlySeed]: ./setYieldRecipient.t.sol#L2016
[test_givenZeroYieldRecipient_whenSetToZeroAgain_reverts_AdminOnlySeed]: ./setYieldRecipient.t.sol#L2087
[test_givenZeroPointerAndAnyPendingYieldSet_whenSetToZeroAgain_reverts_AdminOnlySeed]: ./setYieldRecipient.t.sol#L2067
[test_whenCandidateKernelReadIsMalformed_reverts_AdminOnlySeed]: ./setYieldRecipient.t.sol#L2097
[test_whenCandidateMetadataBoundaries_reverts_AdminOnlySeed]: ./setYieldRecipient.t.sol#L2107
[test_whenCandidateEnabledReadIsMalformed_reverts_AdminOnlySeed]: ./setYieldRecipient.t.sol#L2092
[test_givenCandidateActiveInConsumerKernel_whenReportedKernelDiffers_reverts_AdminOnlySeed]: ./setYieldRecipient.t.sol#L1910
[test_whenCandidateMetadataReverts_reverts_AdminOnlySeed]: ./setYieldRecipient.t.sol#L2112
[test_givenActiveRepurchase_whenCandidateVaultBoolMalformed_reverts_AdminOnlySeed]: ./setYieldRecipient.t.sol#L1862
[test_givenActiveRepurchase_whenCandidateVaultListMalformed_reverts_AdminOnlySeed]: ./setYieldRecipient.t.sol#L1869
[test_givenPolicyActiveDisabledAndCandidate_whenUnauthorizedCallerSetsYieldRecipient_reverts]: ./setYieldRecipient.t.sol#L833
[test_givenPolicyInactiveAndCandidate_whenUnauthorizedCallerSetsYieldRecipient_reverts]: ./setYieldRecipient.t.sol#L862

[test_givenSelectedOperatorWithoutAdmin_whenRecipientRotated_reverts]: ./setYieldRecipient.t.sol#L2127
[test_givenRevenueProposerWithoutAdmin_whenRecipientRotated_reverts]: ./setYieldRecipient.t.sol#L2137
[test_whenCallerHasNoAdmin_whenRecipientUnchanged_reverts]: ./setYieldRecipient.t.sol#L2149
[test_givenAdmin_whenRecipientSelected_preservesDirectGovernance]: ./setYieldRecipient.t.sol#L2158
[test_givenAdminAlsoSelectedOperator_whenRecipientSelected]: ./setYieldRecipient.t.sol#L2182
[test_givenDisabled_whenSelectedOperatorRotates_revertsBeforeAuthority]: ./setYieldRecipient.t.sol#L2213
[test_givenInactive_whenSelectedOperatorRotates_revertsBeforeAuthority]: ./setYieldRecipient.t.sol#L2222
[test_whenAnyCallerValidatesRecipient_preservesReadOnlySemantics]: ./setYieldRecipient.t.sol#L2234

[test_givenAdmin_whenOperatorSelectionSeeds_preservesDirectGovernance]: ./setYieldRecipient.t.sol#L2192
[test_givenInactive_whenEnabledSeeds_revertsBeforeAuthority]: ./setYieldRecipient.t.sol#L2206
[test_whenUnauthorizedCallerSeeds_whenRecipientUnchanged_reverts]: ./setYieldRecipient.t.sol#L2199

[test_givenAuthorizedRecipientCallback_whenPointerRotationAttempted_outerDistributionPaysOnce]: ./distribute.t.sol#L176
