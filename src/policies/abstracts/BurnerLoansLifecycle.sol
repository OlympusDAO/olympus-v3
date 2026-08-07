// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {ERC165Checker} from "@openzeppelin-5.3.0/utils/introspection/ERC165Checker.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IBurnerLoansLifecycle} from "src/policies/interfaces/IBurnerLoansLifecycle.sol";
import {IBurnerLoansView} from "src/policies/interfaces/IBurnerLoansView.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Libraries
import {BurnerLoansConstants} from "src/policies/libraries/BurnerLoansConstants.sol";
import {BurnerLoansMarketConfig} from "src/policies/libraries/BurnerLoansMarketConfig.sol";

// Contracts
import {EnablerV2} from "src/bases/EnablerV2.sol";
import {ReEnablerGracePeriod} from "src/bases/ReEnablerGracePeriod.sol";
import {Kernel, Policy} from "src/Kernel.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";
import {PolicyEnablerV2} from "src/policies/utils/PolicyEnablerV2.sol";
import {OperatorAuth} from "src/policies/utils/OperatorAuth.sol";
import {BURNER_LOANS_ADMIN_ROLE, BURNER_LOANS_SEIZER_ROLE} from "src/policies/utils/RoleDefinitions.sol";

/// @title Burner Loans Lifecycle Base
/// @notice Lifecycle-only state and adapters after configuration and positions are externalized.
abstract contract BurnerLoansLifecycle is
    Policy,
    ReEnablerGracePeriod,
    PolicyEnablerV2,
    OperatorAuth,
    IBurnerLoansLifecycle,
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

    /// @dev Fixed-term loan module holding markets and positions.
    IFLOANv1 internal _FLOAN;

    /// @dev Minter module used to mint and burn OHM principal.
    MINTRv1 internal _MINTR;

    /// @dev Price module used for collateral and OHM valuation.
    IPRICEv2 internal _PRICE;

    /// @dev Treasury module receiving fees, yield, and seized collateral.
    TRSRYv1 internal _TRSRY;

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

    function _marketId(address asset_) internal view returns (uint32) {
        return BurnerLoansMarketConfig.firstMarketId(_FLOAN, address(this), asset_, address(_OHM));
    }

    /// @notice Resolves and decodes the unique Burner Loans market for an asset.
    /// @dev Reverts when the market is absent, ambiguous, uses another schema, or has malformed data.
    /// @param asset_ Collateral asset whose market is required.
    /// @return marketId_ Resolved FLOAN market identifier.
    /// @return config Decoded Burner Loans asset configuration.
    function _requireAssetConfigured(
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
        (marketId_, config) = _requireAssetConfigured(asset_);
        if (!config.originationsEnabled) revert BurnerLoans_AssetOriginationsDisabled(asset_);
    }

    function _onlyBurnerLoansAdminOrAdmin() internal view {
        _requireAuthorized(!_isAdmin(msg.sender) && !_hasRole(msg.sender, BURNER_LOANS_ADMIN_ROLE));
    }

    /// @dev Restricts MINTR approval repair so arbitrary callers cannot undo an emergency reduction.
    function _onlyBurnerLoansAdminOrSeizer() internal view {
        _requireAuthorized(
            !_hasRole(msg.sender, BURNER_LOANS_ADMIN_ROLE) &&
                !_hasRole(msg.sender, BURNER_LOANS_SEIZER_ROLE)
        );
    }

    function _authorizeReEnable() internal view override {
        _onlyBurnerLoansAdminOrAdmin();
    }

    function _authorizeSetGracePeriod() internal view override onlyAdminRole {}

    function VERSION() external pure returns (uint8 major, uint8 minor) {
        return (1, 0);
    }

    function supportsInterface(
        bytes4 interfaceId_
    ) public view virtual override(EnablerV2, ReEnablerGracePeriod) returns (bool) {
        return
            interfaceId_ == type(IBurnerLoansLifecycle).interfaceId ||
            interfaceId_ == type(IBurnerLoansView).interfaceId ||
            interfaceId_ == type(IOperatorAuth).interfaceId ||
            interfaceId_ == type(IVersioned).interfaceId ||
            super.supportsInterface(interfaceId_);
    }
}
