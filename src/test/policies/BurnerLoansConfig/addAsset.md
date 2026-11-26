# BurnerLoansConfig.addAsset coverage plan

Source: [addAsset](../../../policies/burnerloans/BurnerLoansConfig.sol#L212). Planning only; all rewritten scenarios are **Unmapped**.

## Domains and notation

Scenario scope: `BLCFG-ADD-ASSET` identifies this contract/function.

Own-policy admission: require Kernel-active BurnerLoansConfig; own inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansConfig)` before body/input/idempotent work. Apply existing reentrancy guards, own Kernel activity, required local enablement, then caller authorization. Successful body scenarios assume Local active=true, except explicit admission failures.

Implemented listing admission: Config must be locally enabled and Kernel-active, the caller must hold ADMIN_ROLE, and the selected Core must be Kernel-active and locally enabled. Require Config activity, local enablement and caller authorization before Core availability and operation inputs. Use BurnerLoans_PolicyNotActive(BurnerLoansConfig) for inactive Config and PolicyDependency_NotActive(Core) for inactive or disabled Core. The current spike enforces these early activity/Core gates.

Core can be enabled with an empty asset registry, so requiring operational Core does not create a listing/activation cycle. The existing setAssetFeeConfig/setAssetRiskConfig servicing lifecycle remains as specified in their own plans; this Core availability requirement applies to adding a new asset.

Input types: `debtCapOhm_` and maxKeeperReward are uint128; risk/fee BPS fields are uint16; termLength/maxMaturityHorizon are uint48; token decimals are uint8. MAX8/16/48/128 mean each type's maximum. `debtCapOhm_` uses OHM decimals; maxKeeperReward uses underlying collateral units; terms/horizons are seconds; BPS use denominator 10000. The initial debt cap may be zero or exceed Inventory's global debt cap; future borrowing still applies both caps.

Defaults: asset is a new nonzero ERC20 distinct from OHM with 18 decimals; Config/Core active and enabled; ADMIN caller; selected Risk/Inventory/Custody bindings compatible. PRICE approves the asset; DepositManager active/enabled and asset plus Core operator deposit period 1 configured/enabled. Risk defaults are LTV=7500, multiplier=12000, keeper BPS=100, reward=1, term=30 days, horizon=90 days. Fee defaults are base=100, kink=5000, pre=200, post=300. Direct custody defaults to withdrawAsShares_=false.

Unchanged means no Core asset registration, FLOAN market/next-ID change, configuration change, token movement, position/debt/Inventory/provider claim change, receipt change or committed logs. Fixed table prerequisites remain as above unless explicitly varied.

Use real selected Risk validators to prove bounds and exact errors; avoid a permissive mock returning success for invalid configurations. These values and errors are shared with [setAssetRiskConfig](./setAssetRiskConfig.md), [setAssetFeeConfig](./setAssetFeeConfig.md) and the dedicated Risk validator plans. Listing checks price approval, not price freshness or a nonzero quoted price.

## Authorization

ROLES initialized; operation inputs valid. Unauthorized seeds include selected nonzero configOperator without ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE-only holder, borrower, unrelated EOA and contract caller. Config operator authority does not authorize this ADMIN-only listing action.

| ID | Caller | Local active | Local enabled | Core active | Core enabled | Execution | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCFG-ADD-ASSET-A01 | Fuzz ADMIN_ROLE holder | true | true | true | true | Admitted; execute function-specific input cases | Covered: [test][test_givenDirectCustody_whenAdminListsAsset], [test][test_givenSynchronousShares_whenAdminListsAsset] |
| BLCFG-ADD-ASSET-A02 | Fuzz callers excluding every ADMIN_ROLE holder | true | true | true | true | ROLES_RequireRole(ADMIN_ROLE) before Core/input validation | Covered: [test][test_whenCallerIsNotAdmin_reverts] |
| BLCFG-ADD-ASSET-A03 | Fuzz callers excluding every ADMIN_ROLE holder | true | true | true | false | ROLES_RequireRole(ADMIN_ROLE) before Core/input validation | Covered: [test][test_whenCallerIsNotAdmin_reverts] |
| BLCFG-ADD-ASSET-A04 | Fuzz callers excluding every ADMIN_ROLE holder | true | true | false | true | ROLES_RequireRole(ADMIN_ROLE) before Core/input validation | Covered: [test][test_whenCallerIsNotAdmin_reverts] |
| BLCFG-ADD-ASSET-A05 | Fuzz callers excluding every ADMIN_ROLE holder | true | true | false | false | ROLES_RequireRole(ADMIN_ROLE) before Core/input validation | Covered: [test][test_whenCallerIsNotAdmin_reverts] |

## Lifecycle

Use positive otherwise-valid inputs and retain initialized ROLES after deactivation. Repeat unavailable-Core cases with asset=0 to show Core admission wins over input validation. Disabled Config rejects non-admin callers before role lookup; the authorization table separately proves non-admin rejection while Config is enabled.

| ID | Caller | Local active | Local enabled | Core active | Core enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLCFG-ADD-ASSET-L01 | Fuzz all callers | false | false | false | false | BurnerLoans_PolicyNotActive(BurnerLoansConfig) before authorization | Unchanged on rejection; no listing or logs | Covered: [test][test_givenInactiveDisabled_whenAssetAdded_reverts] |
| BLCFG-ADD-ASSET-L02 | Fuzz all callers | false | false | false | true | BurnerLoans_PolicyNotActive(BurnerLoansConfig) before authorization | Unchanged on rejection; no listing or logs | Covered: [test][test_givenInactiveDisabled_whenAssetAdded_reverts] |
| BLCFG-ADD-ASSET-L03 | Fuzz all callers | false | false | true | false | BurnerLoans_PolicyNotActive(BurnerLoansConfig) before authorization | Unchanged on rejection; no listing or logs | Covered: [test][test_givenInactiveDisabled_whenAssetAdded_reverts] |
| BLCFG-ADD-ASSET-L04 | Fuzz all callers | false | false | true | true | BurnerLoans_PolicyNotActive(BurnerLoansConfig) before authorization | Unchanged on rejection; no listing or logs | Covered: [test][test_givenInactiveDisabled_whenAssetAdded_reverts] |
| BLCFG-ADD-ASSET-L05 | Fuzz ADMIN_ROLE holder | false | true | false | false | BurnerLoans_PolicyNotActive(BurnerLoansConfig) | Unchanged on rejection; no listing or logs | Covered: [test][test_givenInactiveEnabled_whenAssetAdded_reverts] |
| BLCFG-ADD-ASSET-L06 | Fuzz ADMIN_ROLE holder | false | true | false | true | BurnerLoans_PolicyNotActive(BurnerLoansConfig) | Unchanged on rejection; no listing or logs | Covered: [test][test_givenInactiveEnabled_whenAssetAdded_reverts] |
| BLCFG-ADD-ASSET-L07 | Fuzz ADMIN_ROLE holder | false | true | true | false | BurnerLoans_PolicyNotActive(BurnerLoansConfig) | Unchanged on rejection; no listing or logs | Covered: [test][test_givenInactiveEnabled_whenAssetAdded_reverts] |
| BLCFG-ADD-ASSET-L08 | Fuzz ADMIN_ROLE holder | false | true | true | true | BurnerLoans_PolicyNotActive(BurnerLoansConfig) | Unchanged on rejection; no listing or logs | Covered: [test][test_givenInactiveEnabled_whenAssetAdded_reverts] |
| BLCFG-ADD-ASSET-L09 | Fuzz all callers | true | false | false | false | NotEnabled() before authorization | Unchanged on rejection; no listing or logs | Covered: [test][test_givenDisabled_whenAssetAdded_reverts] |
| BLCFG-ADD-ASSET-L10 | Fuzz all callers | true | false | false | true | NotEnabled() before authorization | Unchanged on rejection; no listing or logs | Covered: [test][test_givenDisabled_whenAssetAdded_reverts] |
| BLCFG-ADD-ASSET-L11 | Fuzz all callers | true | false | true | false | NotEnabled() before authorization | Unchanged on rejection; no listing or logs | Covered: [test][test_givenDisabled_whenAssetAdded_reverts] |
| BLCFG-ADD-ASSET-L12 | Fuzz all callers | true | false | true | true | NotEnabled() before authorization | Unchanged on rejection; no listing or logs | Covered: [test][test_givenDisabled_whenAssetAdded_reverts] |
| BLCFG-ADD-ASSET-D01 | Fuzz ADMIN_ROLE holder | true | true | false | false | PolicyDependency_NotActive(Core) | Unchanged on rejection; no listing or logs | Covered: [test][test_givenCoreInactiveDisabled_whenAssetAdded_reverts] |
| BLCFG-ADD-ASSET-D02 | Fuzz ADMIN_ROLE holder | true | true | false | true | PolicyDependency_NotActive(Core) | Unchanged on rejection; no listing or logs | Covered: [test][test_givenCoreInactiveEnabled_whenAssetAdded_reverts] |
| BLCFG-ADD-ASSET-D03 | Fuzz ADMIN_ROLE holder | true | true | true | false | PolicyDependency_NotActive(Core) | Unchanged on rejection; no listing or logs | Covered: [test][test_givenCoreActiveDisabled_whenAssetAdded_reverts] |
| BLCFG-ADD-ASSET-L13 | Fuzz ADMIN_ROLE holder | true | true | true | true | Admitted; execute successful/input rows | Unchanged on rejection; no listing or logs | Covered: [test][test_givenDirectCustody_whenAdminListsAsset], [test][test_givenSynchronousShares_whenAdminListsAsset] |

## Dependency lifecycle

| ID | Caller | DepositManager active | DepositManager enabled | Asset / Core period condition | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCFG-ADD-ASSET-D04 | ADMIN_ROLE holder | true | false | Asset/period configured and enabled | BurnerLoansCore_InvalidDepositManager(DM) | Unchanged | Covered: [test][test_givenDepositManagerDisabled_whenAssetAdded_reverts] |
| BLCFG-ADD-ASSET-D05 | ADMIN_ROLE holder | true | true | Core operator period 1 disabled | BurnerLoansCore_InvalidDepositManager(DM) | Unchanged | Covered: [test][test_givenCorePeriodDisabled_whenAssetAdded_reverts] |

## Invalid inputs

Config/Core and caller admission pass. Each row isolates the named fault; earlier token/risk/PRICE/DepositManager/mode checks pass for fee failures. All errors are exact; every rejection has Unchanged effects.

Collateral metadata failures use BurnerLoans_InvalidCollateralAsset(asset), including zero, unsupported decimals and a failed decimals read. Missing DepositManager registration uses the planned BurnerLoans_AssetNotRegisteredInDepositManager(asset,DM); registration requires both the asset and Core’s deposit period 1 to exist. A configured but disabled period remains a distinct state, covered above. These selector changes are required behavior for implementation; they do not change the existing guard order.

### Asset, token and dependency inputs

| ID | Caller | Invalid input / dependency fault | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCFG-ADD-ASSET-I01 | ADMIN_ROLE holder | asset=0; not registered | BurnerLoans_InvalidCollateralAsset(asset) | Unchanged | Covered: [test][test_whenCollateralIsZero_reverts] |
| BLCFG-ADD-ASSET-I02 | ADMIN_ROLE holder | asset=OHM; not registered | BurnerLoans_InvalidCollateralAsset(asset) | Unchanged | Covered: [test][test_whenCollateralIsOhm_reverts] |
| BLCFG-ADD-ASSET-I03 | ADMIN_ROLE holder | Token decimals in 37..MAX8; seed 37,MAX8 | BurnerLoans_InvalidCollateralAsset(asset) | Unchanged | Covered: [test][test_whenCollateralDecimalsUnsupported_reverts], [test][test_whenUnsupportedDecimalEndpointsSeeded_reverts] |
| BLCFG-ADD-ASSET-I04 | ADMIN_ROLE holder | Token decimals getter reverts, or returns 0, 1, 31, 33, 64 or 65,536 bytes | BurnerLoans_InvalidCollateralAsset(asset) | Unchanged | Covered: [test][test_givenDecimalsReadFails_whenAssetAdded_reverts], [test][test_givenMalformedDecimals_whenAssetAdded_reverts] |
| BLCFG-ADD-ASSET-I05 | ADMIN_ROLE holder | Token/risk valid; PRICE approval=false | IBurnerLoansRisk.BurnerLoans_InvalidPrice() | Unchanged | Covered: [test][test_givenRiskRejectsPriceSupport_whenAssetAdded_reverts] |
| BLCFG-ADD-ASSET-I06 | ADMIN_ROLE holder | DepositManager asset unconfigured | BurnerLoans_AssetNotRegisteredInDepositManager(asset,DM) | Unchanged | Covered: [test][test_givenAssetNotRegisteredInDepositManager_whenAssetAdded_reverts] |
| BLCFG-ADD-ASSET-I07 | ADMIN_ROLE holder | Core operator period 1 absent; unrelated operator period present | BurnerLoans_AssetNotRegisteredInDepositManager(asset,DM) | Unchanged | Covered: [test][test_givenCorePeriodAbsent_whenAssetAdded_reverts] |

### Risk configuration

Valid risk domain: maxLtvBps in 1..10000, backingMultiplierBps in 10000..50000, keeperRewardBps in 0..10000, maxKeeperReward in 0..MAX128, termLength in 1..365 days, maxMaturityHorizon in termLength+1..366 days. Fuzz fields independently within those constraints; guarantee each endpoint and maxKeeperReward=0,1,MAX128. Defaults for isolated faults: LTV=7500, backing multiplier=12000, keeper BPS=100, max reward=1, term=30 days, horizon=90 days. For TERM-HIGH, an in-range horizon cannot exceed a MAX48 term; the earlier term-bound rejection is the expected path, so a later term/horizon relationship need not be valid.

| ID | Caller | Invalid field / fuzz domain / seeds | Exact execution error | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCFG-ADD-ASSET-I08 | ADMIN_ROLE holder | maxLtvBps=0 | `IBurnerLoansRisk.BurnerLoans_InvalidBps(0)` | Unchanged; no committed logs | Covered: [test][test_whenZeroLtv_reverts] |
| BLCFG-ADD-ASSET-I09 | ADMIN_ROLE holder | maxLtvBps in 10001..MAX16; seed 10001,MAX16 | `IBurnerLoansRisk.BurnerLoans_InvalidBps(maxLtvBps)` | Unchanged; no committed logs | Covered: [test][test_whenLtvAboveMaximum_reverts], [test][test_whenLtvAboveMaximumEndpointsSeeded_reverts] |
| BLCFG-ADD-ASSET-I10 | ADMIN_ROLE holder | backingMultiplierBps in 0..9999; seed 0,1,9999 | `IBurnerLoansErrors.BurnerLoans_InvalidParam()` | Unchanged; no committed logs | Covered: [test][test_whenBackingBelowMinimum_reverts], [test][test_whenBackingBelowMinimumEndpointsSeeded_reverts] |
| BLCFG-ADD-ASSET-I11 | ADMIN_ROLE holder | backingMultiplierBps in 50001..MAX16; seed 50001,MAX16 | `IBurnerLoansErrors.BurnerLoans_InvalidParam()` | Unchanged; no committed logs | Covered: [test][test_whenBackingAboveMaximum_reverts], [test][test_whenBackingAboveMaximumEndpointsSeeded_reverts] |
| BLCFG-ADD-ASSET-I12 | ADMIN_ROLE holder | keeperRewardBps in 10001..MAX16; seed 10001,MAX16 | `IBurnerLoansRisk.BurnerLoans_InvalidBps(keeperRewardBps)` | Unchanged; no committed logs | Covered: [test][test_whenKeeperBpsAboveMaximum_reverts], [test][test_whenKeeperBpsAboveMaximumEndpointsSeeded_reverts] |
| BLCFG-ADD-ASSET-I13 | ADMIN_ROLE holder | termLength=0; horizon=90 days | `IBurnerLoansErrors.BurnerLoans_InvalidParam()` | Unchanged; no committed logs | Covered: [test][test_whenZeroTerm_reverts] |
| BLCFG-ADD-ASSET-I14 | ADMIN_ROLE holder | termLength in 365 days+1..MAX48; seed lower bound,MAX48; horizon=366 days | `IBurnerLoansErrors.BurnerLoans_InvalidParam()` | Unchanged; no committed logs | Covered: [test][test_whenTermAboveMaximum_reverts], [test][test_whenTermAboveMaximumEndpointsSeeded_reverts] |
| BLCFG-ADD-ASSET-I15 | ADMIN_ROLE holder | maxMaturityHorizon=0; termLength=30 days | `IBurnerLoansErrors.BurnerLoans_InvalidParam()` | Unchanged; no committed logs | Covered: [test][test_whenZeroHorizon_reverts] |
| BLCFG-ADD-ASSET-I16 | ADMIN_ROLE holder | termLength in 2..365 days; maxMaturityHorizon in 1..termLength-1; seed 1,termLength-1 | `IBurnerLoansErrors.BurnerLoans_InvalidParam()` | Unchanged; no committed logs | Covered: [test][test_whenHorizonBelowTerm_reverts], [test][test_whenHorizonRelationBoundariesSeeded_reverts] |
| BLCFG-ADD-ASSET-I17 | ADMIN_ROLE holder | maxMaturityHorizon=termLength; fuzz termLength in 1..365 days; seed 1,365 days | `IBurnerLoansErrors.BurnerLoans_InvalidParam()` | Unchanged; no committed logs | Covered: [test][test_whenHorizonEqualsTerm_reverts], [test][test_whenHorizonRelationBoundariesSeeded_reverts] |
| BLCFG-ADD-ASSET-I18 | ADMIN_ROLE holder | maxMaturityHorizon in 366 days+1..MAX48; seed lower bound,MAX48; valid termLength | `IBurnerLoansErrors.BurnerLoans_InvalidParam()` | Unchanged; no committed logs | Covered: [test][test_whenHorizonAboveMaximum_reverts], [test][test_whenHorizonAboveMaximumEndpointsSeeded_reverts] |

### Fee configuration

Valid fee domain: baseFeeBps, preKinkSlopeBps and postKinkSlopeBps each in 0..10000; their sum is <=10000; kinkBps in 0..9999, with kink=0 allowed only when both slopes are zero. Fuzz base first, then pre within the remaining budget, then post within the remaining budget; choose kink=0..9999 for zero slopes and 1..9999 otherwise. Guarantee zero, one, exact BPS-cap and kink=9999 seeds. Defaults for isolated faults: base=100, kink=5000, pre=200, post=300. Slopes need not be monotonic; seed pre>post as a valid example.

| ID | Caller | Invalid field / fuzz domain / seeds | Exact execution error | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCFG-ADD-ASSET-I19 | ADMIN_ROLE holder | baseFeeBps in 10001..MAX16; seed 10001,MAX16 | `IBurnerLoansRisk.BurnerLoans_InvalidBps(baseFeeBps)` | Unchanged; no committed logs | Covered: [test][test_whenBaseFeeAboveMaximum_reverts], [test][test_whenBaseFeeAboveMaximumEndpointsSeeded_reverts] |
| BLCFG-ADD-ASSET-I20 | ADMIN_ROLE holder | preKinkSlopeBps in 10001..MAX16; seed 10001,MAX16 | `IBurnerLoansRisk.BurnerLoans_InvalidBps(preKinkSlopeBps)` | Unchanged; no committed logs | Covered: [test][test_whenPreKinkSlopeAboveMaximum_reverts], [test][test_whenPreKinkSlopeAboveMaximumEndpointsSeeded_reverts] |
| BLCFG-ADD-ASSET-I21 | ADMIN_ROLE holder | postKinkSlopeBps in 10001..MAX16; seed 10001,MAX16 | `IBurnerLoansRisk.BurnerLoans_InvalidBps(postKinkSlopeBps)` | Unchanged; no committed logs | Covered: [test][test_whenPostKinkSlopeAboveMaximum_reverts], [test][test_whenPostKinkSlopeAboveMaximumEndpointsSeeded_reverts] |
| BLCFG-ADD-ASSET-I22 | ADMIN_ROLE holder | kinkBps in 10000..MAX16; seed 10000,MAX16; other BPS fields valid | `IBurnerLoansRisk.BurnerLoans_InvalidFeeConfig()` | Unchanged; no committed logs | Covered: [test][test_whenKinkAtOrAboveMaximum_reverts], [test][test_whenKinkAtOrAboveMaximumEndpointsSeeded_reverts] |
| BLCFG-ADD-ASSET-I23 | ADMIN_ROLE holder | kinkBps=0; preKinkSlopeBps in 1..10000; postKinkSlopeBps=0; baseFeeBps=0 | `IBurnerLoansRisk.BurnerLoans_InvalidFeeConfig()` | Unchanged; no committed logs | Covered: [test][test_whenZeroKinkAndPositivePreSlope_reverts] |
| BLCFG-ADD-ASSET-I24 | ADMIN_ROLE holder | kinkBps=0; preKinkSlopeBps=0; postKinkSlopeBps in 1..10000; baseFeeBps=0 | `IBurnerLoansRisk.BurnerLoans_InvalidFeeConfig()` | Unchanged; no committed logs | Covered: [test][test_whenZeroKinkAndPositivePostSlope_reverts] |
| BLCFG-ADD-ASSET-I25 | ADMIN_ROLE holder | Each component in 0..10000; kinkBps in 1..9999; sum=base+pre+post in 10001..30000; seed totals 10001,30000 and single-slope tuples (5000,5001,0), (5000,0,5001) | `IBurnerLoansRisk.BurnerLoans_InvalidFeeConfig()` | Unchanged; no committed logs | Covered: [test][test_whenTotalAboveMaximum_reverts], [test][test_whenTotalFeeOverflowBoundariesSeeded_reverts] |

### Custody and output mode

| ID | Caller | Custody | withdrawAsShares_ | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCFG-ADD-ASSET-I26 | ADMIN_ROLE holder | Asynchronous redemption vault | false | AssetManager_RequiresWithdrawAsShares(asset,vault) | Unchanged | Covered: [test][test_givenAsynchronousVault_whenUnderlyingListed_reverts] |
| BLCFG-ADD-ASSET-I27 | ADMIN_ROLE holder | Vault explicitly requires share withdrawal | false | AssetManager_RequiresWithdrawAsShares(asset,vault) | Unchanged | Covered: [test][test_givenExplicitSharesVault_whenUnderlyingListed_reverts] |
| BLCFG-ADD-ASSET-I28 | ADMIN_ROLE holder | Direct custody; no vault | true | AssetManager_VaultRequired(asset) | Unchanged | Covered: [test][test_givenDirectCustody_whenSharesRequested_reverts] |

## Validation precedence

| ID | Caller | Competing inputs | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCFG-ADD-ASSET-I29 | ADMIN_ROLE holder | Already registered asset; also LTV=0 and baseFeeBps=MAX16 | BurnerLoans_AssetAlreadyConfigured(asset) before struct validation | Unchanged | Covered: [test][test_givenExistingAssetAndInvalidStruct_whenAdded_reverts], [test][test_givenExistingAssetWithOriginationsDisabled_whenAddedAgain_reverts] |
| BLCFG-ADD-ASSET-I30 | ADMIN_ROLE holder | New valid token; LTV=0 and baseFeeBps=MAX16 | IBurnerLoansRisk.BurnerLoans_InvalidBps(0) | Unchanged; no fee validator or market creation | Covered: [test][test_givenInvalidRiskAndFee_whenAdded] |
| BLCFG-ADD-ASSET-I31 | ADMIN_ROLE holder | Direct custody with shares=true; baseFeeBps=MAX16; risk and support valid | AssetManager_VaultRequired(asset) | Unchanged; no fee validator or market creation | Covered: [test][test_givenDirectCustody_whenSharesRequested_reverts] |

## Successful execution

Fuzz a nonzero ADMIN_ROLE caller and debtCapOhm_ independently in 0..MAX128, guaranteeing 0,1,MAX128. Other prerequisites pass. Each success creates exactly one FLOAN market with facility=Core, manager=Config, collateral/debt tokens exact, canonical schema/data, principal cap and risk/fee fields equal to inputs. Core registers the asset once; originations=true. Assert AssetRegistered from Core, then AssetAdded, AssetFeeConfigSet and AssetOriginationsSet(asset,true) from Config. No collateral/OHM transfers, fee collection, debt creation, provider-claim change or position migration occurs. Compare every getter field to inputs and isolate unrelated existing markets/positions.

| ID | Caller | Custody | withdrawAsShares_ | Risk inputs | Fee inputs | Execution / proof | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCFG-ADD-ASSET-P01 | Fuzz ADMIN_ROLE holder | Direct custody | false | Fixed valid defaults | Fixed valid defaults | Success; no vault required; asset getters match exact inputs | Covered: [test][test_givenDirectCustody_whenAdminListsAsset] |
| BLCFG-ADD-ASSET-P02 | Fuzz ADMIN_ROLE holder | Synchronous redeemable vault | false | Fixed valid defaults | Fixed valid defaults | Success; canonical mode returns underlying on future exits | Covered: [test][test_givenSynchronousVault_whenUnderlyingModeListed] |
| BLCFG-ADD-ASSET-P03 | Fuzz ADMIN_ROLE holder | Synchronous vault | true | Fixed valid defaults | Fixed valid defaults | Success; canonical mode preserves share withdrawal | Covered: [test][test_givenSynchronousShares_whenAdminListsAsset] |
| BLCFG-ADD-ASSET-P04 | Fuzz ADMIN_ROLE holder | Asynchronous redemption vault | true | Fixed valid defaults | Fixed valid defaults | Success; no underlying redemption attempted during listing | Covered: [test][test_givenAsynchronousVault_whenSharesListed] |
| BLCFG-ADD-ASSET-P05 | Fuzz ADMIN_ROLE holder | Vault explicitly requires shares | true | Fixed valid defaults | Fixed valid defaults | Success; required output mode stored | Covered: [test][test_givenExplicitSharesVault_whenSharesListed] |
| BLCFG-ADD-ASSET-P06 | Fuzz ADMIN_ROLE holder | Direct custody | false | Independent full valid risk domain above; all endpoint seeds | Fixed valid defaults | Success; every risk field and debt cap preserved exactly | Covered: [test][test_whenMaximumRiskListed], [test][test_whenMinimumRiskListed], [test][test_whenFullRiskDomainListed], [test][test_whenListingCapBoundariesSeeded] |
| BLCFG-ADD-ASSET-P07 | Fuzz ADMIN_ROLE holder | Direct custody | false | Fixed valid defaults | Independent full valid fee domain above; include pre>post, zero kink with zero slopes and exact fee cap | Success; exact four-field fee getter and encoded market data | Covered: [test][test_whenFullFeeDomainListed], [test][test_whenSingleSlopeMaximumsSeeded] |
| BLCFG-ADD-ASSET-P08 | Fuzz ADMIN_ROLE holder | Synchronous vault | Fuzz false/true independently | Independent full valid risk domain | Independent full valid fee domain | Success; config generators independent of output mode and caller | Covered: [test][test_whenIndependentRiskFeeAndVaultModeListed] |
| BLCFG-ADD-ASSET-P09 | Fuzz ADMIN_ROLE holder | Direct custody | false | Fixed valid defaults | Fixed valid defaults | Success with PRICE-approved asset and zero/stale quote; listing must not read live health prices | Covered: [test][test_givenApprovedZeroPrice_whenListed], [test][test_givenStalePrice_whenListed] |
| BLCFG-ADD-ASSET-P10 | Fuzz ADMIN_ROLE holder | Direct custody | false | Fixed valid defaults | Fixed valid defaults | Fuzz token decimals 0..36; seed 0,1,6,18,36; two assets retain their distinct decimals and market IDs | Covered: [test][test_whenSupportedDecimalDomainListed], [test][test_whenSupportedDecimalBoundariesSeeded] |

## Valid configuration boundary examples

These are deterministic seeds alongside the valid fuzz domains, not substitutes for interval coverage. Core/Config admission and all custody prerequisites pass.

| ID | Caller | Risk example | Fee example | Execution / proof | Test |
| --- | --- | --- | --- | --- | --- |
| BLCFG-ADD-ASSET-P11 | ADMIN_ROLE holder | LTV=10000, multiplier=50000, keeper BPS=10000, reward=MAX128, term=365 days, horizon=366 days | Fixed valid defaults | Success; no narrowing or extra reward cap | Covered: [test][test_whenMaximumRiskListed] |
| BLCFG-ADD-ASSET-P12 | ADMIN_ROLE holder | LTV=1, multiplier=10000, keeper BPS=0, reward=0, term=1 second, horizon=2 seconds | Fixed valid defaults | Success; each minimum stored exactly | Covered: [test][test_whenMinimumRiskListed] |
| BLCFG-ADD-ASSET-P13 | ADMIN_ROLE holder | Fixed valid defaults | base in 0..10000; kink=pre=post=0; seed base 0,1,10000 | Success; zero-kink flat curve accepted | Covered: [test][test_whenFlatFeeListed], [test][test_whenFlatFeeBoundariesSeeded] |
| BLCFG-ADD-ASSET-P14 | ADMIN_ROLE holder | Fixed valid defaults | base=1000,kink=9999,pre=7000,post=2000; sum=10000 | Success; exact aggregate cap and decreasing slopes accepted | Covered: [test][test_whenDecreasingSlopesAtTotalCapListed] |

## Atomic rollback and callbacks

Keep listing admission and input validation valid; force the named late failure. For callbacks use a separate registered asset for the outer Core settlement, and an independent new asset for nested addAsset.

| ID | Caller | Route / fault | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCFG-ADD-ASSET-C01 | ADMIN_ROLE holder | Core.selected Config changed after prior activation; this Config still active/permitted; FLOAN creation reaches Core.registerMarket | NotAuthorised() | No orphan market, next-ID consumption, registry or logs | Covered: [test][test_givenCoreSelectsOtherConfig_whenAdded] |
| BLCFG-ADD-ASSET-C02 | ADMIN_ROLE callback contract | Existing guarded Core settlement calls token; token invokes addAsset then catches its late registration guard error | Nested ReentrancyGuardReentrantCall(); outer settlement succeeds once | Nested listing fully rolled back; only outer settlement effects commit | Covered: [test][test_givenCollateralCallback_whenNestedListingCaught] |
| BLCFG-ADD-ASSET-C03 | ADMIN_ROLE callback contract | Same route; token bubbles the nested guard error verbatim | ReentrancyGuardReentrantCall() | Full outer and nested rollback; no orphan market or logs | Covered: [test][test_givenCollateralCallback_whenNestedListingPropagated] |

## Shared assertions

This function performs no ERC20 transfer and cannot discover conditional transfer fees or blacklisting at listing time. Real custody actions retain their exact-transfer tests. Getter/encoding checks cover isAssetConfigured, marketId, getAssetConfig and getAssetFeeConfig independently of return values. Boundary seeds cover numeric type maxima through either accepted domains or the individually named rejection case.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

## Atomic market creation and registration

ADMIN caller; Config/Core active/enabled; Risk validation and collateral support pass. Risk configOperator is independently zero or a controller distinct from Config and BLCT. No ADMIN role is granted to Config on Risk.

| ID | Caller | Boundary / fault | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCFG-ADD-ASSET-D06 | Fuzz ADMIN_ROLE holder | Successful createMarket then Core.registerMarket | Success | FLOAN manager=Config, facility=Core; exact canonical risk/fee/term/cap/mode; Core records same ID/mode once; Risk operator untouched | Covered: [test][test_givenDirectCustody_whenAdminListsAsset], [test][test_givenSynchronousShares_whenAdminListsAsset] |
| BLCFG-ADD-ASSET-D07 | Fuzz ADMIN_ROLE holder | Core.registerMarket reverts after FLOAN.createMarket succeeds | Exact injected Core error | No orphan market, market-ID consumption, registry entry or committed event | Covered: [test][test_givenRegistrationFailsAfterMarketCreation_whenAdded] |

[test_whenCallerIsNotAdmin_reverts]: ./addAsset.t.sol#L105
[test_givenDisabled_whenAssetAdded_reverts]: ./addAsset.t.sol#L123
[test_givenInactiveEnabled_whenAssetAdded_reverts]: ./addAsset.t.sol#L157
[test_givenCoreInactiveDisabled_whenAssetAdded_reverts]: ./addAsset.t.sol#L174
[test_givenCoreInactiveEnabled_whenAssetAdded_reverts]: ./addAsset.t.sol#L193
[test_givenCoreActiveDisabled_whenAssetAdded_reverts]: ./addAsset.t.sol#L211
[test_whenCollateralIsZero_reverts]: ./addAsset.t.sol#L229
[test_whenCollateralIsOhm_reverts]: ./addAsset.t.sol#L245
[test_whenCollateralDecimalsUnsupported_reverts]: ./addAsset.t.sol#L261
[test_givenDecimalsReadFails_whenAssetAdded_reverts]: ./addAsset.t.sol#L277
[test_givenRiskRejectsPriceSupport_whenAssetAdded_reverts]: ./addAsset.t.sol#L316
[test_givenAssetNotRegisteredInDepositManager_whenAssetAdded_reverts]: ./addAsset.t.sol#L333
[test_givenCorePeriodAbsent_whenAssetAdded_reverts]: ./addAsset.t.sol#L349
[test_givenDepositManagerDisabled_whenAssetAdded_reverts]: ./addAsset.t.sol#L374
[test_givenCorePeriodDisabled_whenAssetAdded_reverts]: ./addAsset.t.sol#L390
[test_whenZeroLtv_reverts]: ./addAsset.t.sol#L406
[test_whenLtvAboveMaximum_reverts]: ./addAsset.t.sol#L420
[test_whenBackingBelowMinimum_reverts]: ./addAsset.t.sol#L437
[test_whenBackingAboveMaximum_reverts]: ./addAsset.t.sol#L451
[test_whenKeeperBpsAboveMaximum_reverts]: ./addAsset.t.sol#L465
[test_whenZeroTerm_reverts]: ./addAsset.t.sol#L482
[test_whenTermAboveMaximum_reverts]: ./addAsset.t.sol#L496
[test_whenZeroHorizon_reverts]: ./addAsset.t.sol#L511
[test_whenHorizonBelowTerm_reverts]: ./addAsset.t.sol#L525
[test_whenHorizonEqualsTerm_reverts]: ./addAsset.t.sol#L540
[test_whenHorizonAboveMaximum_reverts]: ./addAsset.t.sol#L555
[test_whenBaseFeeAboveMaximum_reverts]: ./addAsset.t.sol#L569
[test_whenPreKinkSlopeAboveMaximum_reverts]: ./addAsset.t.sol#L586
[test_whenPostKinkSlopeAboveMaximum_reverts]: ./addAsset.t.sol#L603
[test_whenKinkAtOrAboveMaximum_reverts]: ./addAsset.t.sol#L620
[test_whenZeroKinkAndPositivePreSlope_reverts]: ./addAsset.t.sol#L634
[test_whenZeroKinkAndPositivePostSlope_reverts]: ./addAsset.t.sol#L648
[test_whenTotalAboveMaximum_reverts]: ./addAsset.t.sol#L662
[test_givenExistingAssetAndInvalidStruct_whenAdded_reverts]: ./addAsset.t.sol#L679
[test_givenInvalidRiskAndFee_whenAdded]: ./addAsset.t.sol#L697
[test_givenDirectCustody_whenAdminListsAsset]: ./addAsset.t.sol#L713
[test_givenSynchronousShares_whenAdminListsAsset]: ./addAsset.t.sol#L720
[test_givenSynchronousVault_whenUnderlyingModeListed]: ./addAsset.t.sol#L729
[test_givenDirectCustody_whenSharesRequested_reverts]: ./addAsset.t.sol#L739
[test_givenApprovedZeroPrice_whenListed]: ./addAsset.t.sol#L756
[test_whenSupportedDecimalDomainListed]: ./addAsset.t.sol#L770
[test_whenMaximumRiskListed]: ./addAsset.t.sol#L791
[test_whenMinimumRiskListed]: ./addAsset.t.sol#L811
[test_whenFlatFeeListed]: ./addAsset.t.sol#L824
[test_whenDecreasingSlopesAtTotalCapListed]: ./addAsset.t.sol#L838
[test_givenRegistrationFailsAfterMarketCreation_whenAdded]: ./addAsset.t.sol#L851
[test_givenCoreSelectsOtherConfig_whenAdded]: ./addAsset.t.sol#L875
[test_givenAsynchronousVault_whenUnderlyingListed_reverts]: ./addAsset.t.sol#L892
[test_givenAsynchronousVault_whenSharesListed]: ./addAsset.t.sol#L915
[test_givenExplicitSharesVault_whenUnderlyingListed_reverts]: ./addAsset.t.sol#L930
[test_givenExplicitSharesVault_whenSharesListed]: ./addAsset.t.sol#L951
[test_whenFullRiskDomainListed]: ./addAsset.t.sol#L964
[test_whenFullFeeDomainListed]: ./addAsset.t.sol#L981
[test_whenIndependentRiskFeeAndVaultModeListed]: ./addAsset.t.sol#L1002
[test_givenCollateralCallback_whenNestedListingCaught]: ./addAsset.t.sol#L1034
[test_givenCollateralCallback_whenNestedListingPropagated]: ./addAsset.t.sol#L1056
[test_whenUnsupportedDecimalEndpointsSeeded_reverts]: ./addAsset.t.sol#L1078
[test_whenSupportedDecimalBoundariesSeeded]: ./addAsset.t.sol#L1104
[test_givenExistingAssetWithOriginationsDisabled_whenAddedAgain_reverts]: ./addAsset.t.sol#L1118
[test_whenLtvAboveMaximumEndpointsSeeded_reverts]: ./addAsset.t.sol#L1133
[test_whenBackingBelowMinimumEndpointsSeeded_reverts]: ./addAsset.t.sol#L1154
[test_whenBackingAboveMaximumEndpointsSeeded_reverts]: ./addAsset.t.sol#L1172
[test_whenKeeperBpsAboveMaximumEndpointsSeeded_reverts]: ./addAsset.t.sol#L1190
[test_whenTermAboveMaximumEndpointsSeeded_reverts]: ./addAsset.t.sol#L1211
[test_whenHorizonAboveMaximumEndpointsSeeded_reverts]: ./addAsset.t.sol#L1229
[test_whenBaseFeeAboveMaximumEndpointsSeeded_reverts]: ./addAsset.t.sol#L1247
[test_whenPreKinkSlopeAboveMaximumEndpointsSeeded_reverts]: ./addAsset.t.sol#L1268
[test_whenPostKinkSlopeAboveMaximumEndpointsSeeded_reverts]: ./addAsset.t.sol#L1289
[test_whenKinkAtOrAboveMaximumEndpointsSeeded_reverts]: ./addAsset.t.sol#L1310
[test_whenHorizonRelationBoundariesSeeded_reverts]: ./addAsset.t.sol#L1328
[test_givenStalePrice_whenListed]: ./addAsset.t.sol#L1368
[test_whenFlatFeeBoundariesSeeded]: ./addAsset.t.sol#L1380
[test_whenListingCapBoundariesSeeded]: ./addAsset.t.sol#L1396
[test_whenSingleSlopeMaximumsSeeded]: ./addAsset.t.sol#L1405
[test_whenTotalFeeOverflowBoundariesSeeded_reverts]: ./addAsset.t.sol#L1427

[test_givenMalformedDecimals_whenAssetAdded_reverts]: ./addAsset.t.sol#L297

[test_givenInactiveDisabled_whenAssetAdded_reverts]: addAsset.t.sol#L140
