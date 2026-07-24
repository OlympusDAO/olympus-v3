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
import {BURNER_LOANS_ADMIN_ROLE, BURNER_LOANS_MANAGER_ROLE} from "src/policies/utils/RoleDefinitions.sol";

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
    uint256 internal constant _BPS = BurnerLoansConstants.MAX_BPS;
    uint256 internal constant _WAD = 1e18;

    IERC20 internal immutable _OHM;
    uint8 internal immutable _OHM_DECIMALS;
    IDepositManager internal immutable _DEPOSIT_MANAGER;

    IFLOANv1 internal _FLOAN;
    MINTRv1 internal _MINTR;
    IPRICEv2 internal _PRICE;
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

        _OHM = ohm_;
        _OHM_DECIMALS = ohm_.decimals();
        _DEPOSIT_MANAGER = depositManager_;
    }

    function _marketId(address asset_) internal view returns (uint32) {
        return BurnerLoansMarketConfig.marketId(_FLOAN, address(this), asset_, address(_OHM));
    }

    function _requireAssetConfigured(
        address asset_
    ) internal view returns (AssetConfig memory config) {
        uint32 marketId_ = _marketId(asset_);
        IFLOANv1.Market memory market = _FLOAN.getMarket(marketId_);
        return
            BurnerLoansMarketConfig.assetConfig(
                marketId_,
                market,
                _FLOAN.getMarketConfigData(marketId_)
            );
    }

    function _assetFeeConfig(address asset_) internal view returns (AssetFeeConfig memory) {
        uint32 marketId_ = _marketId(asset_);
        return
            BurnerLoansMarketConfig.feeConfig(
                marketId_,
                _FLOAN.getMarket(marketId_),
                _FLOAN.getMarketConfigData(marketId_)
            );
    }

    function _requireAssetOriginationsEnabled(
        address asset_
    ) internal view returns (AssetConfig memory config) {
        config = _requireAssetConfigured(asset_);
        if (!config.originationsEnabled) revert BurnerLoans_AssetOriginationsDisabled(asset_);
    }

    function _onlyBurnerLoansAdminOrAdmin() internal view {
        _requireAuthorized(!_isAdmin(msg.sender) && !_hasRole(msg.sender, BURNER_LOANS_ADMIN_ROLE));
    }

    function _onlyBurnerLoansManager() internal view {
        _requireRole(msg.sender, BURNER_LOANS_MANAGER_ROLE);
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
