// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IDepositManagerV1_1} from "src/policies/interfaces/deposits/IDepositManagerV1_1.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";
import {LoanParameters} from "src/policies/burnerloans/libraries/LoanParameters.sol";
import {LoanSolvency} from "src/policies/burnerloans/libraries/LoanSolvency.sol";

// Contracts

/// @notice Shared custody validation, previews and collateral accounting views.
/// @dev Every function is internal; this helper has no deployed or linked runtime.
library LoanCustody {
    /// @notice Requires custody to support an exit from Core's deposit period.
    /// @dev Reverts if:
    ///      - DepositManager reports another Kernel.
    ///      - DepositManager is Kernel-inactive.
    ///      - DepositManager is locally paused.
    ///      - The asset or period is unconfigured.
    ///
    /// @dev A configured period may be disabled for new deposits without blocking exits.
    ///
    /// @param core_ Core whose operator namespace holds the collateral.
    /// @param asset_ Underlying collateral asset.
    /// @param kernel_ Kernel shared by the action and its custody dependency.
    function validateWithdrawalSupport(
        IBurnerLoansCore core_,
        address asset_,
        address kernel_
    ) internal view {
        IDepositManager depositManager = IDepositManager(core_.depositManager());
        PolicyDependency.requireActive(address(depositManager), kernel_);
        validateCustodySupportFor(
            depositManager,
            asset_,
            LoanParameters._DEPOSIT_PERIOD,
            false,
            address(core_)
        );
    }

    /// @notice Validates custody support for an explicit operator.
    /// @dev Reverts if:
    ///      - DepositManager is disabled or the asset or requested period is unavailable.
    /// @param depositManager_ Permanent operator-namespaced collateral custodian.
    /// @param asset_ Underlying collateral token identifying the market.
    /// @param depositPeriod_ Custody receipt period.
    /// @param requireEnabledPeriod_ Whether the custody period must accept new deposits.
    /// @param operator_ DepositManager accounting namespace.
    /// @return assetConfiguration Validated DepositManager asset custody configuration.
    function validateCustodySupportFor(
        IDepositManager depositManager_,
        address asset_,
        uint8 depositPeriod_,
        bool requireEnabledPeriod_,
        address operator_
    ) internal view returns (IDepositManager.AssetConfiguration memory assetConfiguration) {
        // Core validates the permanent DepositManager interface at deployment. This view call
        // already uses STATICCALL; a handwritten decoder or catch wrapper adds no trusted input.
        if (!IEnabler(address(depositManager_)).isEnabled())
            revert IBurnerLoansCore.BurnerLoansCore_InvalidDepositManager(address(depositManager_));

        assetConfiguration = depositManager_.getAssetConfiguration(IERC20(asset_));
        if (!assetConfiguration.isConfigured) {
            revert IBurnerLoansCore.BurnerLoansCore_InvalidDepositManager(address(depositManager_));
        }

        IDepositManager.AssetPeriodStatus memory assetPeriod = depositManager_.isAssetPeriod(
            IERC20(asset_),
            depositPeriod_,
            operator_
        );
        if (!assetPeriod.isConfigured || (requireEnabledPeriod_ && !assetPeriod.isEnabled)) {
            revert IBurnerLoansCore.BurnerLoansCore_InvalidDepositManager(address(depositManager_));
        }
    }

    /// @notice Validates a deposit amount against the configured minimum.
    /// @dev DepositManager validates its aggregate asset cap using credited principal after vault
    ///      conversion. Repeating that check here against the raw input would reject valid deposits.
    ///      Reverts if:
    ///      - The amount is below the configured minimum deposit.
    /// @param asset_ Underlying collateral token identifying the market.
    /// @param assetConfiguration_ DepositManager custody configuration.
    /// @param amount_ Token amount in the operation's documented token units.
    function validateMinimumDeposit(
        address asset_,
        IDepositManager.AssetConfiguration memory assetConfiguration_,
        uint128 amount_
    ) internal pure {
        if (amount_ < assetConfiguration_.minimumDeposit) {
            revert IAssetManager.AssetManager_MinimumDepositNotMet(
                asset_,
                amount_,
                assetConfiguration_.minimumDeposit
            );
        }
    }

    /// @notice Quotes withdrawable collateral credited by a DepositManager deposit.
    /// @dev Reverts if:
    ///      - DepositManager rejects the preview or the estimated credit exceeds `uint128`.
    /// @param depositManager_ DepositManager V1.1 implementation.
    /// @param asset_ Underlying collateral asset.
    /// @param amount_ Underlying amount supplied.
    /// @return uint128 Estimated withdrawable credit, rounded according to DepositManager.
    function previewDepositAmount(
        IDepositManager depositManager_,
        address asset_,
        uint128 amount_
    ) internal view returns (uint128) {
        // Burner Loans credits only the asset-denominated estimate; the share estimate is
        // informational for callers that interact with DepositManager directly.
        // This multiline operation needs a range; the suppression ends immediately after it.
        // forge-lint: disable-start(unused-return)
        (uint256 estimatedCredit, ) = IDepositManagerV1_1(address(depositManager_)).previewDeposit(
            IERC20(asset_),
            amount_
        );
        // forge-lint: disable-end(unused-return)
        return SafeCast.toUint128(estimatedCredit);
    }

    /// @notice Quotes the DepositManager output for a requested collateral debit.
    /// @dev Reverts if:
    ///      - DepositManager rejects the preview.
    /// @param depositManager_ DepositManager V1.1 implementation.
    /// @param asset_ Underlying collateral asset.
    /// @param amount_ Credited collateral amount.
    /// @param withdrawAsShares_ Whether DepositManager returns vault shares.
    /// @return address Token expected from DepositManager.
    /// @return uint256 Amount expected in `tokenOut` decimals.
    function previewWithdrawAmount(
        IDepositManager depositManager_,
        address asset_,
        uint256 amount_,
        bool withdrawAsShares_
    ) internal view returns (address, uint256) {
        (IERC20 outputToken, uint256 outputAmount) = IDepositManagerV1_1(address(depositManager_))
            .previewWithdraw(IERC20(asset_), amount_, withdrawAsShares_);
        return (address(outputToken), outputAmount);
    }

    /// @notice Returns validated custody accounting for an asset and operator.
    /// @dev Reverts if:
    ///      - Custody support is invalid.
    /// @param depositManager_ Permanent operator-namespaced collateral custodian.
    /// @param asset_ Underlying collateral token identifying the market.
    /// @param operator_ DepositManager accounting namespace.
    /// @return collateralStatus Held/borrowed assets, liabilities, shares, solvency and claimable yield.
    function getAssetCollateralStatus(
        IDepositManager depositManager_,
        address asset_,
        address operator_
    ) internal view returns (IBurnerLoansCore.AssetCollateralStatus memory collateralStatus) {
        validateCustodySupportFor(
            depositManager_,
            asset_,
            LoanParameters._DEPOSIT_PERIOD,
            false,
            operator_
        );
        IERC20 asset = IERC20(asset_);
        (collateralStatus.shares, collateralStatus.assets) = depositManager_.getOperatorAssets(
            asset,
            operator_
        );
        collateralStatus.borrowed = depositManager_.getBorrowedAmount(asset, operator_);
        collateralStatus.liabilities = depositManager_.getOperatorLiabilities(asset, operator_);
        // External borrowings still back the operator's liabilities, even though those assets are
        // unavailable for immediate withdrawal. Solvency and currently claimable yield are separate views.
        collateralStatus.solvent = LoanSolvency.isSolvent(
            collateralStatus.assets,
            collateralStatus.borrowed,
            collateralStatus.liabilities
        );
        collateralStatus.claimableYield = depositManager_.maxClaimYield(asset, operator_);
    }

    /// @notice Returns the underlying-denominated yield request for the configured output mode.
    /// @dev Legacy underlying withdrawals retain DepositManager's one-unit redemption buffer.
    ///      Share withdrawals do not redeem, so the solvent surplus can include that final unit.
    ///      The request is capped by assets currently held because borrowed coverage is accounted
    ///      for but is not presently transferable from custody.
    ///      Reverts if:
    ///      - Adding held and borrowed asset amounts overflows.
    /// @param status_ Operator custody shares, assets, borrowed coverage and liabilities.
    /// @param withdrawAsShares_ Whether the selected output mode transfers shares instead of redeeming.
    /// @return uint256 Underlying-denominated transferable yield request; shares omit the redemption buffer.
    function claimableYieldRequest(
        IBurnerLoansCore.AssetCollateralStatus memory status_,
        bool withdrawAsShares_
    ) internal pure returns (uint256) {
        if (!withdrawAsShares_) return status_.claimableYield;

        // Share exits can realize the asset-equivalent surplus without an underlying-liquidity
        // withdrawal. Include borrowed backing when finding surplus, but cap the request to held assets.
        uint256 coveredAssets = status_.assets + status_.borrowed;
        if (coveredAssets <= status_.liabilities) return 0;
        uint256 surplus = coveredAssets - status_.liabilities;
        return surplus < status_.assets ? surplus : status_.assets;
    }
}
