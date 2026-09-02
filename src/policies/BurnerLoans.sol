// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IBurnerLoansLifecycle} from "src/policies/interfaces/IBurnerLoansLifecycle.sol";
import {BurnerLoansContext} from "src/policies/interfaces/IBurnerLoansSeizureContext.sol";
import {IBurnerLoansView} from "src/policies/interfaces/IBurnerLoansView.sol";
import {IBurnerLoansYieldClaim} from "src/policies/interfaces/IBurnerLoansYieldClaim.sol";
import {IOlympusBackingOracle} from "src/policies/interfaces/IOlympusBackingOracle.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";

// Libraries
import {ReentrancyGuard} from "@openzeppelin-5.3.0/utils/ReentrancyGuard.sol";
import {EnumerableSet} from "@openzeppelin-5.3.0/utils/structs/EnumerableSet.sol";
import {BurnerLoansCustody} from "src/policies/libraries/BurnerLoansCustody.sol";
import {BurnerLoansDependencies} from "src/policies/libraries/BurnerLoansDependencies.sol";
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
contract BurnerLoans is BurnerLoansLifecycle, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice Oracle supplying the canonical backing value per OHM.
    address public backingOracle;

    /// @dev Facility-owned recipient and per-asset allocations.
    BurnerLoansDependencies.YieldRoutingState internal _YIELD_ROUTING;

    /// @dev Append-only collateral assets registered by Config after market creation.
    EnumerableSet.AddressSet internal _ASSETS;

    modifier onlyConfigurator() {
        _onlyConfigurator();
        _;
    }

    /// @notice Requires the caller to be the currently bound Config policy.
    /// @dev Reverts with `BurnerLoans_OnlyConfigurator` for every other caller.
    function _onlyConfigurator() internal view {
        if (msg.sender != address(_CONFIGURATOR)) revert BurnerLoans_OnlyConfigurator(msg.sender);
    }

    /// @notice Requires an asset to be present in Config's append-only facility registry.
    /// @dev Reverts with `BurnerLoans_AssetNotConfigured` for unregistered assets.
    function _requireAssetRegistered(address asset_) internal view {
        if (!_ASSETS.contains(asset_)) revert BurnerLoans_AssetNotConfigured(asset_);
    }

    // ========== CONSTRUCTOR ========== //

    constructor(
        Kernel kernel_,
        IERC20 ohm_,
        IDepositManager depositManager_,
        IOlympusBackingOracle backingOracle_
    ) BurnerLoansLifecycle(kernel_, ohm_, depositManager_) {
        BurnerLoansDependencies.validateBackingOracle(address(backingOracle_));
        backingOracle = address(backingOracle_);
    }

    // ========== POLICY SETUP ========== //

    /// @inheritdoc Policy
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
    function setInventory(address inventory_) external override givenDisabled onlyAdminRole {
        _setInventory(inventory_);
    }

    /// @inheritdoc IBurnerLoansLifecycle
    function setConfigurator(address configurator_) external override givenDisabled onlyAdminRole {
        _setConfigurator(configurator_);
    }

    /// @inheritdoc IBurnerLoansLifecycle
    /// @dev Reverts if:
    ///      - Burner Loans is disabled.
    ///      - The caller is not the bound Config policy.
    ///      - The FLOAN market is missing, ambiguous, or has incompatible configuration data.
    ///      - The asset is already registered.
    function addAsset(address asset_) external override onlyConfigurator {
        _requireEnabled();
        // Config creates the FLOAN market first. Resolve it before extending the append-only
        // registry so every registered asset is immediately serviceable by the facility.
        _getAssetMarket(asset_);
        if (!_ASSETS.add(asset_)) revert BurnerLoans_AssetAlreadyConfigured(asset_);
        emit AssetRegistered(asset_);
    }

    /// @inheritdoc IBurnerLoansLifecycle
    /// @dev Reverts if:
    ///      - Burner Loans is disabled.
    ///      - The caller is not the bound Config policy.
    ///      - A nonzero recipient lacks the required interfaces, is not an active Kernel policy, or
    ///        is disabled.
    ///      - A nonzero recipient does not support every asset with a nonzero allocation.
    ///      - The recipient is zero while any asset allocation remains nonzero.
    function setYieldRecipient(address recipient_) external override onlyConfigurator {
        _requireEnabled();
        BurnerLoansDependencies.setYieldRecipient(
            _YIELD_ROUTING,
            _ASSETS,
            kernel,
            _DEPOSIT_MANAGER,
            recipient_
        );
    }

    /// @inheritdoc IBurnerLoansLifecycle
    /// @dev Reverts if:
    ///      - Burner Loans is disabled.
    ///      - The caller is not the bound Config policy.
    ///      - `asset_` is not registered or `bps_` exceeds 10_000.
    ///      - The yield recipient is zero.
    ///      - For nonzero `bps_`, the recipient lacks required interfaces, is not an active Kernel
    ///        policy, is disabled, or its live vault route does not match DepositManager.
    ///        Zero `bps_` remains available to clear an allocation after recipient drift.
    function setYieldRecipientAssetBps(
        address asset_,
        uint16 bps_
    ) external override onlyConfigurator {
        _requireEnabled();
        BurnerLoansDependencies.setYieldRecipientAssetBps(
            _YIELD_ROUTING,
            _ASSETS,
            kernel,
            _DEPOSIT_MANAGER,
            asset_,
            bps_
        );
    }

    /// @notice Sets the oracle supplying canonical OHM backing.
    /// @dev Oracle rotation is intentionally enabled-only so health and seizure economics cannot
    ///      change while borrower actions are paused. Reverts if:
    ///      - Burner Loans is disabled.
    ///      - The caller lacks the OCG admin role.
    ///      - `backingOracle_` is zero, has no code, or lacks `IOlympusBackingOracle` support.
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
    ) external nonReentrant returns (uint256, uint256) {
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
    ///      - Burner Loans is disabled, asset originations are disabled, or the asset market is
    ///        unavailable.
    ///      - The caller is not the owner or an authorized operator.
    ///      - `ohmAmount_` or `recipient_` is zero, or the position has no credited collateral.
    ///      - OHM or collateral PRICE is unsupported, zero, or stale.
    ///      - The resulting global or asset active debt exceeds its cap.
    ///      - The position is seized, matured, currently unhealthy, or unhealthy after borrowing.
    ///      - The collateral fee exceeds `maxFee_` or cannot be transferred from the caller.
    ///      - Burner Loans Inventory cannot fund or transfer exactly `ohmAmount_` to `recipient_`.
    function borrow(
        address asset_,
        uint128 ohmAmount_,
        address onBehalfOf_,
        address recipient_,
        uint256 maxFee_
    ) external nonReentrant returns (uint256, uint256, uint256, uint48, uint256) {
        _requireEnabled();
        return BurnerLoansCustody.borrow(asset_, onBehalfOf_, recipient_, ohmAmount_, maxFee_);
    }

    /// @inheritdoc IBurnerLoansLifecycle
    /// @dev Reverts if:
    ///      - Burner Loans or Burner Loans Inventory is disabled.
    ///      - The asset market or borrower position is unavailable or has no debt.
    ///      - `repayOhm_` is zero, exceeds principal, or is submitted in the latest borrow block.
    ///      - The OHM transfer fails or Inventory receives an inexact amount.
    ///      - FLOAN debt reduction or Inventory settlement fails.
    /// @dev Repayment deliberately avoids PRICE reads so debt reduction remains available when
    ///      oracle data is stale. Returns FLOAN's actual remaining principal and the established
    ///      no-oracle health sentinel. The transfer must increase Burner Loans Inventory's balance
    ///      by exactly `repayOhm_`.
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
    ///      - Burner Loans or asset originations are disabled.
    ///      - The caller is not the owner or an authorized operator.
    ///      - The asset market or borrower debt position is unavailable.
    ///      - The term count, current health, maturity, or resulting horizon is invalid.
    ///      - The collateral fee exceeds `maxFee_` or cannot be transferred to Treasury.
    ///      - FLOAN rejects the maturity mutation.
    ///      Returns the fee plus FLOAN's actual resulting maturity and health factor.
    function extend(
        address asset_,
        address onBehalfOf_,
        uint16 termCount_,
        uint256 maxFee_
    ) external override nonReentrant returns (uint256 fee, uint48 maturity, uint256 healthFactor) {
        _requireEnabled();
        _requireSenderAuthorized(msg.sender, onBehalfOf_);
        return
            BurnerLoansCustody.extend(_marketId(asset_), asset_, onBehalfOf_, termCount_, maxFee_);
    }

    /// @inheritdoc IBurnerLoansLifecycle
    /// @dev Reverts if:
    ///      - Burner Loans, DepositManager, or Burner Loans Inventory is disabled.
    ///      - `borrowers_` is empty, exceeds the batch limit, or contains duplicates.
    ///      - The asset market, custody route, backing value, or PRICE data is invalid.
    ///      - Any borrower has no debt or is not currently seizable.
    ///      - Custody is insolvent, returns zero assets, or leaves a residual facility balance.
    ///      - FLOAN defaulting, Inventory settlement, DepositManager withdrawal, or token transfer
    ///        fails.
    function seize(
        address asset_,
        address[] calldata borrowers_
    ) external override nonReentrant returns (uint256, uint256) {
        _requireEnabled();
        return BurnerLoansSeizure.seize(asset_, borrowers_);
    }

    /// @inheritdoc IBurnerLoansYieldClaim
    /// @dev Asset disable does not block safe surplus collection. Iterates the append-only asset
    ///      registry atomically. Reverts if:
    ///      - Burner Loans or DepositManager is disabled.
    ///      - Any registered asset has no configured custody period or custody is insolvent.
    ///      - Any nonzero recipient allocation has an invalid live policy or vault route.
    ///      - DepositManager yield claiming or an asset transfer fails.
    function claimYield() external override nonReentrant {
        _requireEnabled();
        BurnerLoansCustody.claimYield(_ASSETS, _YIELD_ROUTING);
    }

    // ========== VIEW FUNCTIONS ========== //

    /// @inheritdoc IBurnerLoansView
    function validateAssetDependencies(address asset_) external view override {
        BurnerLoansView.validateAssetDependencies(asset_);
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
    /// @dev Reads facility-owned routing storage and does not perform live recipient validation.
    function getYieldRecipient() external view override returns (address recipient) {
        return _YIELD_ROUTING.recipient;
    }

    /// @inheritdoc IBurnerLoansView
    /// @dev Returns the append-only registry length maintained by `addAsset`.
    function getAssetCount() external view override returns (uint256 count) {
        return _ASSETS.length();
    }

    /// @inheritdoc IBurnerLoansView
    /// @dev Reverts with OpenZeppelin's enumerable-set bounds error for an invalid index.
    function getAssetAt(uint256 index_) external view override returns (address asset) {
        return _ASSETS.at(index_);
    }

    /// @inheritdoc IBurnerLoansView
    /// @dev Returns zero for assets without a configured allocation.
    function getYieldRecipientAssetBps(address asset_) external view override returns (uint16 bps) {
        return _YIELD_ROUTING.assetBps[asset_];
    }

    /// @inheritdoc IBurnerLoansView
    /// @dev Reverts if:
    ///      - The recipient is zero or lacks `IYieldRecipient` or `IEnabler` support.
    ///      - The recipient is not an active policy in the facility Kernel.
    ///      - The recipient is disabled.
    function validateYieldRecipient(address recipient_) external view override {
        BurnerLoansDependencies.validateYieldRecipient(kernel, recipient_);
    }

    /// @inheritdoc IBurnerLoansView
    /// @dev Reverts if global recipient validation fails or the exact DepositManager asset-vault
    ///      pair is mismatched or disabled. Recipient lookup failures bubble unchanged.
    function validateYieldRecipientAsset(
        address recipient_,
        address asset_
    ) external view override {
        BurnerLoansDependencies.validateYieldRecipientAsset(
            kernel,
            _DEPOSIT_MANAGER,
            recipient_,
            asset_
        );
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
    function getPosition(
        address asset_,
        address borrower_
    ) external view override returns (Position memory) {
        return BurnerLoansView.getPositionForBorrower(_FLOAN, _marketId(asset_), borrower_);
    }

    /// @inheritdoc IBurnerLoansView
    function getActiveBorrowers(address asset_) external view override returns (address[] memory) {
        return _FLOAN.getActiveBorrowers(_marketId(asset_));
    }

    /// @inheritdoc IBurnerLoansView
    function isSeizable(address asset_, address borrower_) external view override returns (bool) {
        return BurnerLoansView.isBorrowerSeizable(asset_, _marketId(asset_), borrower_);
    }

    /// @inheritdoc IBurnerLoansView
    function previewSeize(
        address asset_,
        address[] calldata borrowers_
    ) external view override returns (SeizePreview memory) {
        _requireEnabled();
        return BurnerLoansSeizure.previewSeize(asset_, borrowers_);
    }

    /// @inheritdoc IBurnerLoansView
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
    function previewDepositCollateral(
        address asset_,
        uint128 amount_,
        address onBehalfOf_
    ) external view override returns (uint256 depositedCollateral, uint256 totalCollateral) {
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
    function previewBorrow(
        address asset_,
        uint128 ohmAmount_,
        address onBehalfOf_
    ) external view override returns (BorrowPreview memory) {
        _requireEnabled();
        _requireInventoryActive(address(_INVENTORY));
        return BurnerLoansQuote.previewBorrow(asset_, ohmAmount_, _marketId(asset_), onBehalfOf_);
    }

    /// @inheritdoc IBurnerLoansView
    function previewRepay(
        address asset_,
        uint128 repayOhm_,
        address onBehalfOf_
    ) external view override returns (RepayPreview memory) {
        _requireEnabled();
        return BurnerLoansView.previewRepayForBorrower(asset_, onBehalfOf_, repayOhm_);
    }

    /// @inheritdoc IBurnerLoansView
    function previewExtend(
        address asset_,
        address onBehalfOf_,
        uint16 termCount_
    ) external view override returns (ExtendPreview memory) {
        _requireEnabled();
        return BurnerLoansQuote.previewExtend(asset_, termCount_, _marketId(asset_), onBehalfOf_);
    }

    /// @inheritdoc IBurnerLoansView
    function positionHealthFactor(
        address asset_,
        uint256 collateral_,
        uint256 debtOhm_
    ) external view override returns (uint256) {
        return BurnerLoansQuote.positionHealthFactor(asset_, collateral_, debtOhm_);
    }

    /// @inheritdoc IBurnerLoansView
    /// @dev Reverts if Burner Loans is disabled, the asset is unregistered, custody is unsupported,
    ///      or a solvent claim has an invalid live recipient route.
    function previewClaimYield(
        address asset_
    ) external view override returns (ClaimYieldPreview memory) {
        _requireEnabled();
        _requireAssetRegistered(asset_);
        return
            BurnerLoansCustody.previewClaimYield(
                asset_,
                _YIELD_ROUTING.recipient,
                _YIELD_ROUTING.assetBps[asset_]
            );
    }

    /// @inheritdoc IBurnerLoansView
    function getAssetCollateralStatus(
        address asset_
    ) external view override returns (AssetCollateralStatus memory) {
        _requireAssetRegistered(asset_);
        return BurnerLoansCustody.getAssetCollateralStatus(_DEPOSIT_MANAGER, asset_, address(this));
    }

    /// @notice Returns the dependency snapshot consumed by linked Burner Loans libraries.
    /// @return dependencies Current token, module, custody, oracle, treasury, and role dependencies.
    function context() external view returns (BurnerLoansContext memory dependencies) {
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
                treasury: address(_TRSRY),
                roles: ROLES
            });
    }
}
