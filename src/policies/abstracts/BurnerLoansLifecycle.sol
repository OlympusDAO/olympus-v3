// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {ERC165Checker} from "@openzeppelin-5.3.0/utils/introspection/ERC165Checker.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IBurnerLoansLifecycle} from "src/policies/interfaces/IBurnerLoansLifecycle.sol";
import {IBurnerLoansInventory} from "src/policies/interfaces/IBurnerLoansInventory.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";
import {IBurnerLoansView} from "src/policies/interfaces/IBurnerLoansView.sol";
import {IBurnerLoansYieldClaim} from "src/policies/interfaces/IBurnerLoansYieldClaim.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Libraries
import {BurnerLoansConstants} from "src/policies/libraries/BurnerLoansConstants.sol";
import {BurnerLoansDependencies} from "src/policies/libraries/BurnerLoansDependencies.sol";
import {BurnerLoansMarketConfig} from "src/policies/libraries/BurnerLoansMarketConfig.sol";

// Contracts
import {EnablerV2} from "src/bases/EnablerV2.sol";
import {ReEnablerGracePeriod} from "src/bases/ReEnablerGracePeriod.sol";
import {Kernel, Policy} from "src/Kernel.sol";
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";
import {PolicyEnablerV2} from "src/policies/utils/PolicyEnablerV2.sol";
import {OperatorAuth} from "src/policies/utils/OperatorAuth.sol";
import {BURNER_LOANS_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

/// @title Burner Loans Lifecycle Base
/// @notice Lifecycle-only state and adapters after configuration and positions are externalized.
abstract contract BurnerLoansLifecycle is
    Policy,
    ReEnablerGracePeriod,
    PolicyEnablerV2,
    OperatorAuth,
    IBurnerLoansLifecycle,
    IBurnerLoansYieldClaim,
    IBurnerLoansView,
    IVersioned
{
    /// @dev Basis-point denominator shared by lifecycle calculations.
    uint256 internal constant _BPS = BurnerLoansConstants.MAX_BPS;

    /// @dev Fixed-point scale used for health factors and utilization values.
    uint256 internal constant _WAD = 1e18;

    /// @dev Debt token minted by Burner Loans.
    IERC20 internal immutable _OHM;

    /// @dev Decimal precision of `_OHM`.
    uint8 internal immutable _OHM_DECIMALS;

    /// @dev Custody policy that holds collateral on behalf of Burner Loans.
    IDepositManager internal immutable _DEPOSIT_MANAGER;

    /// @dev OHM funding and aggregate-principal accounting policy.
    IBurnerLoansInventory internal _INVENTORY;

    /// @dev Burner Loans Config policy authorized to manage facility configuration.
    IBurnerLoansConfig internal _CONFIGURATOR;

    /// @dev Fixed-term loan module holding markets and positions.
    IFLOANv1 internal _FLOAN;

    /// @dev Price module used for collateral and OHM valuation.
    IPRICEv2 internal _PRICE;

    /// @dev Treasury module receiving fees, yield, and seized collateral.
    TRSRYv1 internal _TRSRY;

    /// @notice Initializes the facility's immutable Kernel, OHM, and custody dependencies.
    /// @dev Reverts with `BurnerLoans_ZeroAddress` for a zero token or DepositManager,
    ///      `BurnerLoans_InvalidDepositManager` for an incompatible DepositManager, or
    ///      `BurnerLoans_DepositManagerKernelMismatch` when it belongs to another Kernel.
    /// @param kernel_ Kernel governing this policy.
    /// @param ohm_ OHM debt token used by the facility.
    /// @param depositManager_ DepositManager that custodies collateral.
    constructor(
        Kernel kernel_,
        IERC20 ohm_,
        IDepositManager depositManager_
    ) Policy(kernel_) ReEnablerGracePeriod(BurnerLoansConstants.REENABLE_GRACE_PERIOD) {
        if (address(ohm_) == address(0) || address(depositManager_) == address(0)) {
            revert BurnerLoans_ZeroAddress();
        }
        if (
            !ERC165Checker.supportsInterface(
                address(depositManager_),
                type(IDepositManager).interfaceId
            )
        ) {
            revert BurnerLoans_InvalidDepositManager(address(depositManager_));
        }
        address depositManagerKernel = address(Policy(address(depositManager_)).kernel());
        if (depositManagerKernel != address(kernel_)) {
            revert BurnerLoans_DepositManagerKernelMismatch(address(kernel_), depositManagerKernel);
        }
        _OHM = ohm_;
        _OHM_DECIMALS = ohm_.decimals();
        _DEPOSIT_MANAGER = depositManager_;
    }

    /// @dev Validates and stores a compatible Burner Loans Inventory contract bound to this facility.
    function _setInventory(address inventory_) internal {
        BurnerLoansDependencies.validateInventoryLink(
            kernel,
            address(this),
            address(_OHM),
            inventory_
        );
        _INVENTORY = IBurnerLoansInventory(inventory_);
        emit InventorySet(inventory_);
    }

    /// @dev Validates and stores the Burner Loans Config policy for this facility.
    function _setConfigurator(address configurator_) internal {
        BurnerLoansDependencies.validateConfiguratorLink(
            kernel,
            address(this),
            address(_OHM),
            configurator_
        );
        _CONFIGURATOR = IBurnerLoansConfig(configurator_);
        emit ConfiguratorSet(configurator_);
    }

    /// @dev Reverts unless the configured Burner Loans Inventory is an active policy.
    function _requireInventoryActive(address inventory_) internal view {
        if (!kernel.isPolicyActive(Policy(inventory_))) {
            revert BurnerLoans_InventoryNotActive(inventory_);
        }
    }

    /// @notice Resolves the earliest FLOAN market for a collateral asset and OHM.
    /// @dev Reverts when no matching market exists. Lifecycle servicing deliberately uses the
    ///      earliest market when FLOAN contains multiple matches.
    /// @param asset_ Collateral asset whose market is resolved.
    /// @return marketId_ Earliest matching market identifier.
    function _marketId(address asset_) internal view returns (uint32 marketId_) {
        return BurnerLoansMarketConfig.firstMarketId(_FLOAN, address(this), asset_, address(_OHM));
    }

    /// @notice Returns the decoded Burner Loans market for an asset.
    /// @dev Reverts when no matching market exists, or when the earliest matching market uses
    ///      another schema or has malformed data.
    /// @param asset_ Collateral asset whose market is required.
    /// @return marketId_ Resolved FLOAN market identifier.
    /// @return config Decoded Burner Loans asset configuration.
    function _getAssetMarket(
        address asset_
    ) internal view returns (uint32 marketId_, AssetConfig memory config) {
        marketId_ = _marketId(asset_);
        IFLOANv1.Market memory market = _FLOAN.getMarket(marketId_);
        config = BurnerLoansMarketConfig.assetConfig(
            marketId_,
            market,
            _FLOAN.getMarketConfigData(marketId_)
        );
    }

    /// @notice Resolves a configured market and requires originations to be enabled.
    /// @param asset_ Collateral asset whose market is required.
    /// @return marketId_ Resolved FLOAN market identifier.
    /// @return config Decoded Burner Loans asset configuration.
    function _requireAssetOriginationsEnabled(
        address asset_
    ) internal view returns (uint32 marketId_, AssetConfig memory config) {
        (marketId_, config) = _getAssetMarket(asset_);
        if (!config.originationsEnabled) revert BurnerLoans_AssetOriginationsDisabled(asset_);
    }

    /// @notice Requires OCG admin or Burner Loans admin authority.
    /// @dev Reverts with `NotAuthorised` when the caller has neither role.
    function _onlyBurnerLoansAdminOrAdmin() internal view {
        _requireAuthorized(!_isAdmin(msg.sender) && !_hasRole(msg.sender, BURNER_LOANS_ADMIN_ROLE));
    }

    /// @notice Authorizes a re-enable transition during the grace period.
    /// @dev Reverts unless the caller is an OCG admin or Burner Loans admin.
    function _authorizeReEnable() internal view override {
        _onlyBurnerLoansAdminOrAdmin();
    }

    /// @notice Authorizes a grace-period update.
    /// @dev Reverts unless the caller has the OCG admin role.
    function _authorizeSetGracePeriod() internal view override onlyAdminRole {}

    /// @dev Prevents enabling Burner Loans before compatible Config and Burner Loans Inventory
    ///      policies are bound and agree.
    function _beforeEnable(bytes calldata) internal view override {
        BurnerLoansDependencies.validateConfiguration(
            kernel,
            address(this),
            address(_OHM),
            address(_DEPOSIT_MANAGER),
            address(_INVENTORY),
            address(_CONFIGURATOR)
        );
    }

    /// @dev Preserves the grace-period gate and revalidates configuration before re-enabling.
    function _beforeReEnable() internal override {
        super._beforeReEnable();
        BurnerLoansDependencies.validateConfiguration(
            kernel,
            address(this),
            address(_OHM),
            address(_DEPOSIT_MANAGER),
            address(_INVENTORY),
            address(_CONFIGURATOR)
        );
    }

    /// @inheritdoc IVersioned
    function VERSION() external pure returns (uint8 major, uint8 minor) {
        return (1, 0);
    }

    /// @inheritdoc EnablerV2
    function supportsInterface(
        bytes4 interfaceId_
    ) public view virtual override(EnablerV2, ReEnablerGracePeriod) returns (bool) {
        return
            interfaceId_ == type(IBurnerLoansLifecycle).interfaceId ||
            interfaceId_ == type(IBurnerLoansView).interfaceId ||
            interfaceId_ == type(IBurnerLoansYieldClaim).interfaceId ||
            interfaceId_ == type(IOperatorAuth).interfaceId ||
            interfaceId_ == type(IVersioned).interfaceId ||
            super.supportsInterface(interfaceId_);
    }
}
