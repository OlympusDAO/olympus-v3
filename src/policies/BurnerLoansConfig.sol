// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";

// Contracts
import {Kernel, Keycode, Module, Permissions, toKeycode} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {BurnerLoansConfigBase} from "src/policies/abstracts/BurnerLoansConfig.sol";

/// @title Burner Loans Config
/// @notice Configuration policy for Burner Loans markets and risk parameters.
contract BurnerLoansConfig is BurnerLoansConfigBase {
    constructor(
        Kernel kernel_,
        IERC20 ohm_,
        IDepositManager depositManager_
    ) BurnerLoansConfigBase(kernel_, ohm_, depositManager_) {}

    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](3);
        dependencies[0] = toKeycode("FLOAN");
        dependencies[1] = toKeycode("PRICE");
        dependencies[2] = toKeycode("ROLES");

        _FLOAN = IFLOANv1(getModuleAddress(dependencies[0]));
        address priceAddress = getModuleAddress(dependencies[1]);
        ROLES = ROLESv1(getModuleAddress(dependencies[2]));

        (uint8 floanMajor, ) = Module(address(_FLOAN)).VERSION();
        (uint8 priceMajor, uint8 priceMinor) = Module(priceAddress).VERSION();
        (uint8 rolesMajor, ) = ROLES.VERSION();
        bool priceVersionSupported = priceMajor == 2 || (priceMajor == 1 && priceMinor >= 2);
        if (floanMajor != 1 || !priceVersionSupported || rolesMajor != 1) {
            revert BurnerLoans_InvalidModuleVersion();
        }
        if (!IERC165(priceAddress).supportsInterface(type(IPRICEv2).interfaceId)) {
            revert BurnerLoans_InvalidModuleVersion();
        }
        _PRICE = IPRICEv2(priceAddress);
    }

    function requestPermissions() external pure override returns (Permissions[] memory requests) {
        Keycode floan = toKeycode("FLOAN");
        requests = new Permissions[](7);
        requests[0] = Permissions({keycode: floan, funcSelector: IFLOANv1.createMarket.selector});
        requests[1] = Permissions({
            keycode: floan,
            funcSelector: IFLOANv1.setMarketOriginationsEnabled.selector
        });
        requests[2] = Permissions({
            keycode: floan,
            funcSelector: IFLOANv1.setMarketFacility.selector
        });
        requests[3] = Permissions({
            keycode: floan,
            funcSelector: IFLOANv1.setMarketPrincipalCap.selector
        });
        requests[4] = Permissions({
            keycode: floan,
            funcSelector: IFLOANv1.setMarketRiskConfig.selector
        });
        requests[5] = Permissions({
            keycode: floan,
            funcSelector: IFLOANv1.setMarketBaseFee.selector
        });
        requests[6] = Permissions({
            keycode: floan,
            funcSelector: IFLOANv1.setMarketConfigData.selector
        });
    }

    function ohm() external view returns (address) {
        return address(_OHM);
    }

    function depositManager() external view returns (address) {
        return address(_DEPOSIT_MANAGER);
    }

    function isAssetConfigured(address facility_, address asset_) external view returns (bool) {
        return _isAssetConfigured(facility_, asset_);
    }

    function marketId(address facility_, address asset_) external view returns (uint32) {
        return _marketId(facility_, asset_);
    }

    function getAssetConfig(
        address facility_,
        address asset_
    ) external view returns (AssetConfig memory) {
        if (!_isAssetConfigured(facility_, asset_)) {
            return
                AssetConfig({
                    enabled: false,
                    collateralDecimals: 0,
                    collateralFactorBps: 0,
                    minCollateralRatioBps: 0,
                    backingMultiplierBps: 0,
                    keeperRewardBps: 0,
                    termLength: 0,
                    maxMaturityHorizon: 0,
                    debtCap: 0,
                    maxKeeperReward: 0
                });
        }
        return _getAssetConfig(_marketId(facility_, asset_));
    }

    function getAssetFeeConfig(
        address facility_,
        address asset_
    ) external view returns (AssetFeeConfig memory) {
        if (!_isAssetConfigured(facility_, asset_)) {
            return
                AssetFeeConfig({
                    baseFeeBps: 0,
                    kinkBps: 0,
                    preKinkSlopeBps: 0,
                    postKinkSlopeBps: 0
                });
        }
        return _getAssetFeeConfig(_marketId(facility_, asset_));
    }

    function _feeRateWad(
        uint256,
        AssetFeeConfig memory feeConfig_
    ) internal pure override returns (uint256) {
        return
            uint256(
                feeConfig_.baseFeeBps + feeConfig_.preKinkSlopeBps + feeConfig_.postKinkSlopeBps
            ) * (_WAD / _BPS);
    }
}
