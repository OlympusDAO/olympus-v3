// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.15;

import {Kernel, Policy, Keycode, toKeycode, Permissions} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/OlympusRoles.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";
import {IConvertibleDepositAuctioneer} from "src/policies/interfaces/IConvertibleDepositAuctioneer.sol";
import {IERC20} from "src/interfaces/IERC20.sol";

contract MockConvertibleDepositAuctioneer is IConvertibleDepositAuctioneer, Policy, PolicyEnabler {
    uint48 internal _initTimestamp;
    int256[] internal _auctionResults;

    uint256 public target;
    uint256 public tickSize;
    uint256 public minPrice;

    constructor(Kernel kernel_) Policy(kernel_) {}

    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("ROLES");

        ROLES = ROLESv1(getModuleAddress(dependencies[0]));

        return dependencies;
    }

    function requestPermissions()
        external
        view
        override
        returns (Permissions[] memory permissions)
    {}

    function bid(
        IERC20,
        uint8,
        uint256 depositAmount_,
        bool,
        bool
    ) external pure override returns (uint256 ohmOut, uint256 positionId, uint256 receiptTokenId) {
        return (depositAmount_, 0, 0);
    }

    function previewBid(
        IERC20,
        uint8,
        uint256 depositAmount_
    ) external view override returns (uint256 ohmOut, address depositSpender) {
        return (depositAmount_, address(this));
    }

    function getPreviousTick(IERC20, uint8) external view override returns (Tick memory tick) {}

    function getCurrentTick(IERC20, uint8) external view override returns (Tick memory tick) {}

    function getCurrentTickSize() external view override returns (uint256) {
        return tickSize;
    }

    function getAuctionParameters()
        external
        view
        override
        returns (AuctionParameters memory auctionParameters)
    {}

    function getDayState() external view override returns (Day memory day) {}

    function setAuctionParameters(
        uint256 newTarget,
        uint256 newSize,
        uint256 newMinPrice
    ) external override {
        target = newTarget;
        tickSize = newSize;
        minPrice = newMinPrice;
    }

    function setAuctionResults(int256[] memory results) external {
        _auctionResults = results;
    }

    function setTickStep(uint24 newStep) external override {}

    function getTickStep() external view override returns (uint24) {}

    function getAuctionTrackingPeriod() external view override returns (uint8) {}

    function getAuctionResults() external view override returns (int256[] memory) {
        return _auctionResults;
    }

    function getAuctionResultsNextIndex() external view override returns (uint8) {}

    function setAuctionTrackingPeriod(uint8 newPeriod) external override {}

    function enableDepositPeriod(IERC20 depositAsset_, uint8 depositPeriod_) external override {}

    function disableDepositPeriod(IERC20 depositAsset_, uint8 depositPeriod_) external override {}

    function getDepositAssets() external view override returns (IERC20[] memory) {}

    function getDepositPeriods(
        IERC20 depositAsset_
    ) external view override returns (uint8[] memory) {}

    function isDepositEnabled(
        IERC20 depositAsset_,
        uint8 depositPeriod_
    ) external view override returns (bool) {}

    function getDepositAssetsAndPeriodsCount() external view override returns (uint256) {}
}
