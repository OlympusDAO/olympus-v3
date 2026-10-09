// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IBurnerLoansLifecycle} from "src/policies/interfaces/IBurnerLoansLifecycle.sol";
import {BurnerLoansContext, IBurnerLoansSeizureContext} from "src/policies/interfaces/IBurnerLoansSeizureContext.sol";
import {IBurnerLoansView} from "src/policies/interfaces/IBurnerLoansView.sol";
import {IBurnerLoansYieldClaim} from "src/policies/interfaces/IBurnerLoansYieldClaim.sol";
import {IOlympusBackingOracle} from "src/policies/interfaces/IOlympusBackingOracle.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";

// Libraries
import {ReentrancyGuard} from "@openzeppelin-5.7.0/utils/ReentrancyGuard.sol";
import {EnumerableSet} from "@openzeppelin-5.7.0/utils/structs/EnumerableSet.sol";
import {BurnerLoansCustody} from "src/policies/libraries/BurnerLoansCustody.sol";
import {BurnerLoansDependencies} from "src/policies/libraries/BurnerLoansDependencies.sol";
import {BurnerLoansPayouts} from "src/policies/libraries/BurnerLoansPayouts.sol";
import {BurnerLoansQuote} from "src/policies/libraries/BurnerLoansQuote.sol";
import {BurnerLoansSeizure} from "src/policies/libraries/BurnerLoansSeizure.sol";
import {BurnerLoansView} from "src/policies/libraries/BurnerLoansView.sol";

// Contracts
import {Kernel, Keycode, Permissions, Policy} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";
import {BurnerLoansLifecycle} from "src/policies/abstracts/BurnerLoansLifecycle.sol";

/// @title Burner Loans
/// @notice Fixed-term, zero-interest OHM shorting facility skeleton.
/// @dev Collateral assets must have exact ERC20 transfer semantics. Asset admission relies on
///      governance review; DepositManager verifies exact receipt when collateral enters custody.
///      All token-touching lifecycle entry points share one storage-backed reentrancy guard.
contract BurnerLoans is BurnerLoansLifecycle, ReentrancyGuard, IBurnerLoansSeizureContext {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice Oracle supplying the canonical backing value per OHM.
    address public backingOracle;

    /// @inheritdoc IBurnerLoansView
    address public override revenueDistributor;
    /// @inheritdoc IBurnerLoansView
    bool public override sendFeesToDistributor;
    /// @inheritdoc IBurnerLoansView
    bool public override sendYieldToDistributor;

    /// @dev Related balances and enumerable retry keys passed together to the payout library.
    BurnerLoansPayouts.State internal _PAYOUTS;

    /// @dev Append-only collateral assets registered by Config after market creation.
    EnumerableSet.AddressSet internal _ASSETS;

    modifier onlyConfigurator() {
        _requireConfigurator();
        _;
    }

    /// @dev Reverts if:
    ///      - the caller is not the currently bound Config policy.
    function _requireConfigurator() internal view {
        if (msg.sender != address(_CONFIGURATOR)) revert BurnerLoans_OnlyConfigurator(msg.sender);
    }

    // ========== CONSTRUCTOR ========== //

    /// @dev Reverts if:
    ///      - The inherited lifecycle constructor rejects a required dependency.
    ///      - The backing oracle is zero, has no code, or lacks the required interface.
    constructor(
        Kernel kernel_,
        IERC20 ohm_,
        IDepositManager depositManager_,
        IPriceCache priceCache_,
        IOlympusBackingOracle backingOracle_
    ) BurnerLoansLifecycle(kernel_, ohm_, depositManager_, priceCache_) {
        BurnerLoansDependencies.validateBackingOracle(address(backingOracle_));
        backingOracle = address(backingOracle_);
        emit BackingOracleSet(address(backingOracle_));
    }

    // ========== POLICY SETUP ========== //

    /// @inheritdoc Policy
    /// @dev Reverts if:
    ///      - A required module is missing.
    ///      - A module version or dependency is incompatible.
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = BurnerLoansDependencies.keycodes();

        _FLOAN = IFLOANv1(getModuleAddress(dependencies[0]));
        address priceAddress = getModuleAddress(dependencies[1]);
        ROLES = ROLESv1(getModuleAddress(dependencies[2]));
        _TRSRY = TRSRYv1(getModuleAddress(dependencies[3]));

        _PRICE = BurnerLoansDependencies.validate(_FLOAN, priceAddress, ROLES, _TRSRY);
    }

    /// @inheritdoc Policy
    function requestPermissions() external pure override returns (Permissions[] memory requests) {
        return BurnerLoansDependencies.permissions();
    }

    // ========== ADMIN FUNCTIONS ========== //

    /// @inheritdoc IBurnerLoansLifecycle
    /// @dev Reverts if:
    ///      - The caller lacks the admin role or Burner Loans is enabled.
    ///      - The inventory is incompatible, bound elsewhere, or inactive.
    function setInventory(address inventory_) external override givenDisabled onlyAdminRole {
        _setInventory(inventory_);
    }

    /// @inheritdoc IBurnerLoansLifecycle
    /// @dev Reverts if:
    ///      - The caller lacks the admin role or Burner Loans is enabled.
    ///      - The configurator is invalid or bound to another facility.
    function setConfigurator(address configurator_) external override givenDisabled onlyAdminRole {
        _setConfigurator(_ASSETS, configurator_);
    }

    /// @inheritdoc IBurnerLoansLifecycle
    /// @dev Reverts if:
    ///      - The caller lacks the admin role.
    ///      - The price cache is invalid.
    function setPriceCache(address priceCache_) external override onlyAdminRole {
        _setPriceCache(priceCache_);
    }

    /// @inheritdoc IBurnerLoansLifecycle
    /// @dev Reverts if:
    ///      - The caller lacks the admin role.
    ///      - Burner Loans is inactive or locally disabled.
    ///      - A nonzero distributor is invalid or belongs to another Kernel.
    ///      - The distributor is cleared while either send flag is enabled.
    function setRevenueDistributor(address distributor_) external override onlyAdminRole {
        _requirePolicyActive();
        _requireEnabled();
        if (distributor_ == address(0) && (sendFeesToDistributor || sendYieldToDistributor)) {
            revert BurnerLoans_RevenueDistributorRequired();
        }
        if (distributor_ == revenueDistributor) return;
        if (distributor_ != address(0)) {
            BurnerLoansDependencies.validateRevenueDistributor(kernel, distributor_);
        }
        revenueDistributor = distributor_;
        emit RevenueDistributorSet(distributor_);
    }

    /// @inheritdoc IBurnerLoansLifecycle
    /// @dev Reverts if:
    ///      - The caller is not the configurator or Burner Loans is inactive or disabled.
    ///      - Enabling selects an invalid distributor or one bound to another Kernel.
    function setSendFeesToDistributor(
        bool enabled_
    ) external override nonReentrant onlyConfigurator {
        _requirePolicyActive();
        _requireEnabled();
        if (enabled_ == sendFeesToDistributor) return;
        _validateSendFlag(enabled_);
        sendFeesToDistributor = enabled_;
        emit SendFeesToDistributorSet(enabled_);
    }

    /// @inheritdoc IBurnerLoansLifecycle
    /// @dev Reverts if:
    ///      - The caller is not the configurator or Burner Loans is inactive or disabled.
    ///      - Enabling selects an invalid distributor or one bound to another Kernel.
    function setSendYieldToDistributor(
        bool enabled_
    ) external override nonReentrant onlyConfigurator {
        _requirePolicyActive();
        _requireEnabled();
        if (enabled_ == sendYieldToDistributor) return;
        _validateSendFlag(enabled_);
        sendYieldToDistributor = enabled_;
        emit SendYieldToDistributorSet(enabled_);
    }

    /// @dev Disabling needs no destination. Enabling must revalidate the currently selected
    ///      distributor because the pointer or its policy state may have changed since setup.
    ///      Reverts if:
    ///      - Enabling has no selected distributor.
    ///      - The selected distributor is incompatible or belongs to another Kernel.
    function _validateSendFlag(bool enabled_) internal view {
        if (!enabled_) return;
        if (revenueDistributor == address(0)) revert BurnerLoans_RevenueDistributorRequired();
        BurnerLoansDependencies.validateRevenueDistributor(kernel, revenueDistributor);
    }

    /// @inheritdoc IBurnerLoansLifecycle
    /// @dev Reverts if:
    ///      - The caller is not the configurator.
    ///      - Burner Loans is disabled.
    function setPriceCacheMaxAge(
        uint48 priceCacheMaxAge_
    ) external override nonReentrant onlyConfigurator {
        _requireEnabled();
        _priceCacheMaxAge = priceCacheMaxAge_;
        emit PriceCacheMaxAgeSet(priceCacheMaxAge_);
    }

    /// @inheritdoc IBurnerLoansLifecycle
    /// @dev Reverts if:
    ///      - Burner Loans is disabled.
    ///      - The caller is not the bound Config policy.
    ///      - The FLOAN market is missing, ambiguous, or has incompatible configuration data.
    ///      - The asset is already registered.
    function addAsset(address asset_) external override nonReentrant onlyConfigurator {
        _requireEnabled();
        // Config creates the FLOAN market first. Resolve it before extending the append-only
        // registry so every registered asset is immediately serviceable by the facility.
        (, AssetConfig memory config) = _getAssetMarket(asset_);
        BurnerLoansView.validateAssetWithdrawAsShares(asset_, config.withdrawAsShares);
        BurnerLoansDependencies.registerAsset(_ASSETS, asset_);
    }

    /// @notice Sets the oracle supplying canonical OHM backing.
    /// @dev Oracle rotation is intentionally enabled-only so health and seizure economics cannot
    ///      change while borrower actions are paused. Reverts if:
    ///      - Burner Loans is disabled.
    ///      - The caller lacks the OCG admin role.
    ///      - `backingOracle_` is zero, has no code, or lacks `IOlympusBackingOracle` support.
    // validateBackingOracle rejects zero, non-contract, and unsupported oracle addresses.
    // forge-lint: disable-next-line(missing-zero-check)
    function setBackingOracle(address backingOracle_) external givenEnabled onlyAdminRole {
        BurnerLoansDependencies.validateBackingOracle(backingOracle_);
        backingOracle = backingOracle_;
        emit BackingOracleSet(backingOracle_);
    }

    // ========== USER FUNCTIONS ========== //

    /// @inheritdoc IBurnerLoansLifecycle
    /// @dev Reverts if:
    ///      - Burner Loans, asset originations, or DepositManager is disabled.
    ///      - The caller is not the owner or an authorized operator.
    ///      - DepositManager has no configured and enabled unwrapped custody period for this asset
    ///        and facility.
    ///      - `amount_` is zero, below the DepositManager minimum, or exceeds its operator cap.
    ///      - Token transfer fails or delivers an inexact amount, DepositManager detects inexact
    ///        receipt, custody leaves residual collateral, or vault rounding produces zero credit.
    function depositCollateral(
        address asset_,
        uint128 amount_,
        address onBehalfOf_
    ) external nonReentrant returns (uint256, uint256, uint256) {
        _requireEnabled();
        return BurnerLoansCustody.depositCollateral(asset_, amount_, onBehalfOf_);
    }

    /// @inheritdoc IBurnerLoansLifecycle
    /// @dev Disabling asset originations or its DepositManager period does not block this exit;
    ///      DepositManager itself must remain enabled. Reverts if:
    ///      - Burner Loans or DepositManager is disabled.
    ///      - The caller is not the owner or an authorized operator.
    ///      - DepositManager has no configured unwrapped custody period for this asset and facility.
    ///      - `amount_` is zero or exceeds credited collateral, or custody returns zero assets.
    ///      - `recipient_` is zero, PRICE is unavailable or stale with debt, or health falls below
    ///        1e18 after the withdrawal.
    /// @dev Exact outgoing transfer behavior is an asset-onboarding assumption; it is not checked
    ///      again on every withdrawal. The requested credit is debited while DepositManager's
    ///      nonzero actual output is returned, which may be lower after ERC-4626 rounding.
    function withdrawCollateral(
        address asset_,
        uint128 amount_,
        address onBehalfOf_,
        address recipient_
    )
        external
        nonReentrant
        returns (
            address tokenOut,
            uint256 amountOut,
            uint256 remainingDepositedCollateral,
            uint256 healthFactor_
        )
    {
        _requireEnabled();
        return BurnerLoansCustody.withdrawCollateral(asset_, onBehalfOf_, recipient_, amount_);
    }

    /// @inheritdoc IBurnerLoansLifecycle
    /// @dev Uses pre-borrow asset utilization for the fee curve and charges the fee on the
    ///      incremental required collateral. Reverts if:
    ///      - Burner Loans is disabled or Kernel-inactive, asset originations are disabled, or the
    ///        asset market is unavailable.
    ///      - The caller is not the owner or an authorized operator.
    ///      - `ohmAmount_` or `recipient_` is zero, or the position has no credited collateral.
    ///      - OHM or collateral PRICE is unsupported, zero, or stale.
    ///      - The resulting global or asset active debt exceeds its cap.
    ///      - The position is seized, matured, currently unhealthy, or unhealthy after borrowing.
    ///      - The collateral fee exceeds `maxFee_` or cannot be collected from the caller.
    ///      - Burner Loans Inventory cannot fund or transfer exactly `ohmAmount_` to `recipient_`.
    function borrow(
        address asset_,
        uint128 ohmAmount_,
        address onBehalfOf_,
        address recipient_,
        uint256 maxFee_
    )
        external
        nonReentrant
        returns (uint256 borrowed, uint256 fee, uint256 debt, uint48 maturity, uint256 health)
    {
        _requireEnabled();
        _requirePolicyActive();
        (borrowed, fee, debt, maturity, health) = BurnerLoansCustody.borrow(
            asset_,
            onBehalfOf_,
            recipient_,
            ohmAmount_,
            maxFee_
        );
        _collectFee(asset_, fee);
    }

    /// @inheritdoc IBurnerLoansLifecycle
    /// @dev Reverts if:
    ///      - Burner Loans or Burner Loans Inventory is disabled.
    ///      - The asset market or borrower position is unavailable or has no debt.
    ///      - `repayOhm_` is zero, exceeds principal, or is submitted in the latest borrow block.
    ///      - The OHM transfer fails or Inventory receives an inexact amount.
    ///      - FLOAN debt reduction or Inventory settlement fails.
    ///      - OHM or collateral PRICE is unsupported, zero, or stale when debt remains.
    /// @dev Returns FLOAN's actual remaining principal and the resulting health factor. A full
    ///      repayment returns max uint without reading PRICE. The transfer must increase Burner
    ///      Loans Inventory's balance by exactly `repayOhm_`.
    function repay(
        address asset_,
        uint128 repayOhm_,
        address onBehalfOf_
    ) external override nonReentrant returns (uint256 remainingDebtOhm, uint256 healthFactor) {
        _requireEnabled();
        if (repayOhm_ == 0) revert BurnerLoans_ZeroAmount();
        (uint32 marketId, ) = _getAssetMarket(asset_);
        return BurnerLoansCustody.repay(marketId, asset_, onBehalfOf_, repayOhm_);
    }

    /// @inheritdoc IBurnerLoansLifecycle
    /// @dev Reverts if:
    ///      - Burner Loans is disabled or Kernel-inactive, or asset originations are disabled.
    ///      - The caller is not the owner or an authorized operator.
    ///      - The asset market or borrower debt position is unavailable.
    ///      - The term count, current health, maturity, or resulting horizon is invalid.
    ///      - The collateral fee exceeds `maxFee_` or cannot be collected from the caller.
    ///      - FLOAN rejects the maturity mutation.
    ///      Returns the fee plus FLOAN's actual resulting maturity and health factor.
    function extend(
        address asset_,
        address onBehalfOf_,
        uint16 termCount_,
        uint256 maxFee_
    ) external override nonReentrant returns (uint256 fee, uint48 maturity, uint256 healthFactor) {
        _requireEnabled();
        _requirePolicyActive();
        _requireSenderAuthorized(msg.sender, onBehalfOf_);
        (fee, maturity, healthFactor) = BurnerLoansCustody.extend(
            _marketId(asset_),
            asset_,
            onBehalfOf_,
            termCount_,
            maxFee_
        );
        _collectFee(asset_, fee);
    }

    /// @inheritdoc IBurnerLoansLifecycle
    /// @dev Reverts if:
    ///      - Burner Loans is disabled or Kernel-inactive, or DepositManager or Burner Loans
    ///        Inventory is disabled.
    ///      - `borrowers_` is empty, exceeds the batch limit, or contains duplicates.
    ///      - The asset market, custody route, backing value, or PRICE data is invalid.
    ///      - Any borrower has no debt or is not currently seizable.
    ///      - Custody is insolvent.
    ///      - FLOAN defaulting, Inventory settlement, or DepositManager withdrawal fails.
    ///        Rejected keeper or Treasury payouts remain pending.
    ///      A share-mode seizure may default debt with zero immediate output; retained share dust
    ///      becomes custody yield.
    function seize(
        address asset_,
        address[] calldata borrowers_
    ) external override nonReentrant returns (address, uint256, uint256) {
        _requireEnabled();
        _requirePolicyActive();
        return BurnerLoansSeizure.seize(_PAYOUTS, asset_, borrowers_);
    }

    /// @inheritdoc IBurnerLoansYieldClaim
    /// @dev Reverts if:
    ///      - Burner Loans is disabled or Kernel-inactive, the asset is unregistered, or custody
    ///        is unsupported.
    ///      - DepositManager cannot release claimable yield or transfer it to the current recipient.
    function claimYield(
        address asset_
    ) external override nonReentrant givenEnabled returns (address tokenOut, uint256 amountOut) {
        _requirePolicyActive();
        return BurnerLoansCustody.claimYield(_ASSETS, asset_);
    }

    /// @inheritdoc IBurnerLoansLifecycle
    /// @dev Reverts if:
    ///      - Burner Loans is Kernel-inactive or locally disabled.
    ///      - A guarded operation is already in progress.
    ///      A failed token transfer leaves that payout owed.
    function transferPendingPayout(
        address token_,
        address recipient_
    ) external override nonReentrant returns (uint256 transferred) {
        _requirePolicyActive();
        _requireEnabled();
        if (recipient_ == _feeRecipient()) {
            transferred += BurnerLoansPayouts.transferPendingFee(_PAYOUTS, token_, recipient_);
        }
        if (recipient_ == address(_TRSRY)) {
            transferred += BurnerLoansPayouts.transferPendingSeizedCollateral(
                _PAYOUTS,
                token_,
                recipient_
            );
        }
        transferred += BurnerLoansPayouts.transferPendingSeizureReward(
            _PAYOUTS,
            token_,
            recipient_
        );
    }

    /// @dev Reverts if:
    ///      - this policy is no longer active in the Kernel.
    function _requirePolicyActive() internal view {
        if (!kernel.isPolicyActive(Policy(address(this)))) revert BurnerLoans_PolicyInactive();
    }

    /// @inheritdoc IBurnerLoansView
    function pendingPayout(
        address token_,
        address recipient_
    ) external view override returns (uint256) {
        return _pendingAmount(token_, recipient_);
    }

    /// @dev Combines liabilities currently owed to this address.
    function _pendingAmount(
        address token_,
        address recipient_
    ) internal view returns (uint256 amount) {
        amount = _PAYOUTS.pendingKeeperRewards[token_][recipient_];
        if (recipient_ == _feeRecipient()) amount += _PAYOUTS.pendingFees[token_];
        if (recipient_ == address(_TRSRY)) amount += _PAYOUTS.pendingSeizedCollateral[token_];
    }

    /// @inheritdoc IBurnerLoansView
    function getPendingPayoutTokens() external view override returns (address[] memory) {
        return BurnerLoansPayouts.tokens(_PAYOUTS);
    }

    /// @inheritdoc IBurnerLoansView
    function getPendingPayoutRecipients(
        address token_
    ) external view override returns (address[] memory) {
        return BurnerLoansPayouts.recipients(_PAYOUTS, token_, _feeRecipient(), address(_TRSRY));
    }

    /// @dev Collects the caller's fee, records any deferred outgoing payout, and selects its
    ///      current destination. Failure to send the collected fee onward leaves it pending.
    ///      Reverts if:
    ///      - The caller's fee cannot be collected exactly.
    function _collectFee(address asset_, uint256 fee_) internal {
        BurnerLoansPayouts.collectFee(_PAYOUTS, asset_, msg.sender, _feeRecipient(), fee_);
    }

    /// @dev Returns the distributor when fee routing is enabled, otherwise the cached Treasury.
    function _feeRecipient() internal view returns (address) {
        return
            sendFeesToDistributor && revenueDistributor != address(0)
                ? revenueDistributor
                : address(_TRSRY);
    }

    /// @dev Returns the distributor when yield routing is enabled, otherwise the cached Treasury.
    function _yieldRecipient() internal view returns (address) {
        return
            sendYieldToDistributor && revenueDistributor != address(0)
                ? revenueDistributor
                : address(_TRSRY);
    }

    // ========== VIEW FUNCTIONS ========== //

    /// @inheritdoc IBurnerLoansView
    /// @dev Reverts if:
    ///      - The asset is invalid.
    ///      - A required module configuration for the asset is invalid.
    function validateAssetDependencies(address asset_) external view override {
        BurnerLoansView.validateAssetDependencies(asset_);
    }

    /// @inheritdoc IBurnerLoansView
    /// @dev Reverts if:
    ///      - The asset's custody configuration does not match `withdrawAsShares_`.
    function validateAssetWithdrawAsShares(
        address asset_,
        bool withdrawAsShares_
    ) external view override {
        BurnerLoansView.validateAssetWithdrawAsShares(asset_, withdrawAsShares_);
    }

    /// @inheritdoc IBurnerLoansView
    function ohm() external view override returns (address) {
        return address(_OHM);
    }

    /// @inheritdoc IBurnerLoansView
    function inventory() external view override returns (address) {
        return address(_INVENTORY);
    }

    /// @inheritdoc IBurnerLoansView
    function configurator() external view override returns (address) {
        return address(_CONFIGURATOR);
    }

    /// @inheritdoc IBurnerLoansView
    function priceCache() external view override returns (address) {
        return address(_PRICE_CACHE);
    }

    /// @inheritdoc IBurnerLoansView
    function priceCacheMaxAge() external view override returns (uint48) {
        return _priceCacheMaxAge;
    }

    /// @inheritdoc IBurnerLoansView
    /// @dev Returns the append-only registry length maintained by `addAsset`.
    function getAssetCount() external view override returns (uint256 count) {
        return _ASSETS.length();
    }

    /// @inheritdoc IBurnerLoansView
    /// @dev Reverts if:
    ///      - `index_` is outside the registered-asset set; OpenZeppelin supplies the bounds error.
    function getAssetAt(uint256 index_) external view override returns (address asset) {
        return _ASSETS.at(index_);
    }

    /// @inheritdoc IBurnerLoansView
    function floan() external view override returns (address) {
        return address(_FLOAN);
    }

    /// @notice Returns aggregate active principal serviced by this facility.
    /// @return activeDebtOhm Active principal in OHM token decimals.
    function totalActiveDebtOhm() public view returns (uint256 activeDebtOhm) {
        return _FLOAN.getFacilityPrincipalDue(address(this), address(_OHM));
    }

    /// @notice Returns active principal for one collateral asset.
    /// @dev Returns zero when the asset has no compatible Burner Loans market.
    /// @param asset_ Collateral asset whose debt is queried.
    /// @return activeDebtOhm Active principal in OHM token decimals.
    function assetActiveDebtOhm(address asset_) external view returns (uint256 activeDebtOhm) {
        return BurnerLoansView.assetActiveDebtOhm(_FLOAN, address(this), address(_OHM), asset_);
    }

    /// @inheritdoc IBurnerLoansView
    /// @dev Reverts if:
    ///      - The asset has no compatible FLOAN market.
    function getPosition(
        address asset_,
        address borrower_
    ) external view override returns (Position memory) {
        return BurnerLoansView.getPositionForBorrower(_FLOAN, _marketId(asset_), borrower_);
    }

    /// @inheritdoc IBurnerLoansView
    /// @dev Reverts if:
    ///      - The asset has no compatible FLOAN market.
    function getActiveBorrowers(address asset_) external view override returns (address[] memory) {
        return _FLOAN.getActiveBorrowers(_marketId(asset_));
    }

    /// @inheritdoc IBurnerLoansView
    /// @dev Reverts if:
    ///      - The asset has no compatible FLOAN market.
    ///      - Required price data is invalid.
    function isSeizable(address asset_, address borrower_) external view override returns (bool) {
        return BurnerLoansView.isBorrowerSeizable(asset_, _marketId(asset_), borrower_);
    }

    /// @inheritdoc IBurnerLoansView
    /// @dev Reverts if:
    ///      - Burner Loans is disabled or Kernel-inactive, or the asset or borrower set is invalid.
    ///      - Required custody, backing, or price data is unavailable.
    function previewSeize(
        address asset_,
        address[] calldata borrowers_
    ) external view override returns (SeizePreview memory) {
        _requireEnabled();
        _requirePolicyActive();
        return BurnerLoansSeizure.previewSeize(asset_, borrowers_);
    }

    /// @inheritdoc IBurnerLoansView
    /// @dev Reverts if:
    ///      - Burner Loans is disabled or the asset market is unavailable.
    ///      - A scan parameter or required backing or price data is invalid.
    function getSeizableBorrowers(
        address asset_,
        uint256 startIndex_,
        uint256 maxBorrowersToCheck_,
        uint256 maxBorrowersToReturn_
    ) external view override returns (address[] memory, uint256, uint256) {
        _requireEnabled();
        return
            BurnerLoansSeizure.getSeizableBorrowers(
                BurnerLoansSeizure.ScanRequest({
                    asset: asset_,
                    startIndex: startIndex_,
                    maxBorrowersToCheck: maxBorrowersToCheck_,
                    maxBorrowersToReturn: maxBorrowersToReturn_
                })
            );
    }

    /// @inheritdoc IBurnerLoansView
    /// @dev Reverts if:
    ///      - Burner Loans is disabled or the asset market or custody route is invalid.
    ///      - The deposit amount cannot be credited.
    function previewDepositCollateral(
        address asset_,
        uint128 amount_,
        address onBehalfOf_
    ) external view override returns (uint256, uint256, uint256) {
        _requireEnabled();
        return
            BurnerLoansView.previewDepositCollateralForBorrower(
                asset_,
                amount_,
                _marketId(asset_),
                onBehalfOf_
            );
    }

    /// @inheritdoc IBurnerLoansView
    /// @dev Reverts if:
    ///      - Burner Loans is disabled or the asset market or custody route is invalid.
    ///      - The withdrawal exceeds credited collateral or makes the position unhealthy.
    function previewWithdrawCollateral(
        address asset_,
        uint128 amount_,
        address onBehalfOf_
    ) external view override returns (WithdrawPreview memory) {
        _requireEnabled();
        return
            BurnerLoansView.previewWithdrawCollateralForBorrower(
                asset_,
                amount_,
                _marketId(asset_),
                onBehalfOf_
            );
    }

    /// @inheritdoc IBurnerLoansView
    /// @dev Reverts if:
    ///      - Burner Loans is disabled or Kernel-inactive, or Inventory is disabled.
    ///      - The asset market, position, requested amount, collateral, cap, or required price
    ///        data is invalid.
    function previewBorrow(
        address asset_,
        uint128 ohmAmount_,
        address onBehalfOf_
    ) external view override returns (BorrowPreview memory) {
        _requireEnabled();
        _requirePolicyActive();
        _requireInventoryActive(address(_INVENTORY));
        return BurnerLoansQuote.previewBorrow(asset_, ohmAmount_, _marketId(asset_), onBehalfOf_);
    }

    /// @inheritdoc IBurnerLoansView
    /// @dev Reverts if:
    ///      - Burner Loans is disabled or the asset or borrower debt is unavailable.
    ///      - The requested repayment is invalid.
    function previewRepay(
        address asset_,
        uint128 repayOhm_,
        address onBehalfOf_
    ) external view override returns (RepayPreview memory) {
        _requireEnabled();
        return BurnerLoansView.previewRepayForBorrower(asset_, onBehalfOf_, repayOhm_);
    }

    /// @inheritdoc IBurnerLoansView
    /// @dev Reverts if:
    ///      - Burner Loans is disabled or Kernel-inactive.
    ///      - The asset market, borrower debt, requested term count, maturity, health, or required
    ///        price data is invalid.
    function previewExtend(
        address asset_,
        address onBehalfOf_,
        uint16 termCount_
    ) external view override returns (ExtendPreview memory) {
        _requireEnabled();
        _requirePolicyActive();
        return BurnerLoansQuote.previewExtend(asset_, termCount_, _marketId(asset_), onBehalfOf_);
    }

    /// @inheritdoc IBurnerLoansView
    /// @dev Reverts if:
    ///      - Required configuration or price data is unavailable for nonzero debt.
    function positionHealthFactor(
        address asset_,
        uint256 collateral_,
        uint256 debtOhm_
    ) external view override returns (uint256) {
        return BurnerLoansQuote.positionHealthFactor(asset_, collateral_, debtOhm_);
    }

    /// @inheritdoc IBurnerLoansView
    /// @dev Reverts if:
    ///      - The market or borrower position is missing.
    ///      - Either supplied price is zero or required current configuration or backing is invalid.
    ///      An existing zero-principal position returns max uint only after both supplied prices
    ///      are validated.
    function positionHealthFactorAtPrice(
        address asset_,
        address borrower_,
        uint256 collateralUsdPrice_,
        uint256 ohmUsdPrice_
    ) external view override returns (uint256) {
        return
            BurnerLoansQuote.positionHealthFactorAtPrice(
                asset_,
                _marketId(asset_),
                borrower_,
                collateralUsdPrice_,
                ohmUsdPrice_
            );
    }

    /// @inheritdoc IBurnerLoansView
    /// @dev Reverts if:
    ///      - Burner Loans is disabled or Kernel-inactive, or the asset is not registered.
    ///      - The configured custody route is unsupported or DepositManager cannot quote yield.
    function previewClaimYield(
        address asset_
    ) external view override returns (ClaimYieldPreview memory) {
        _requireEnabled();
        _requirePolicyActive();
        return BurnerLoansCustody.previewClaimYield(_ASSETS, asset_);
    }

    /// @inheritdoc IBurnerLoansView
    /// @dev Reverts if:
    ///      - The asset is not registered.
    ///      - DepositManager cannot report its custody.
    function getAssetCollateralStatus(
        address asset_
    ) external view override returns (AssetCollateralStatus memory) {
        return
            BurnerLoansCustody.getRegisteredAssetCollateralStatus(
                _ASSETS,
                _DEPOSIT_MANAGER,
                asset_
            );
    }

    /// @inheritdoc IBurnerLoansSeizureContext
    function context() external view override returns (BurnerLoansContext memory dependencies) {
        return
            BurnerLoansContext({
                ohm: _OHM,
                ohmDecimals: _OHM_DECIMALS,
                depositManager: _DEPOSIT_MANAGER,
                facility: address(this),
                inventory: _INVENTORY,
                backingOracle: backingOracle,
                floan: _FLOAN,
                price: _PRICE,
                priceCache: _PRICE_CACHE,
                priceCacheMaxAge: _priceCacheMaxAge,
                treasury: address(_TRSRY),
                yieldRecipient: _yieldRecipient(),
                roles: ROLES
            });
    }

    /// @inheritdoc BurnerLoansLifecycle
    function supportsInterface(bytes4 interfaceId_) public view override returns (bool) {
        return
            interfaceId_ == type(IBurnerLoansSeizureContext).interfaceId ||
            super.supportsInterface(interfaceId_);
    }
}
