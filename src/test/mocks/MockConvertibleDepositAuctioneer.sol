// SPDX-License-Identifier: Unlicense
// solhint-disable custom-errors
pragma solidity >=0.8.15;

import {Kernel, Policy, Keycode, toKeycode, Permissions} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/OlympusRoles.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";
import {IConvertibleDepositAuctioneer} from "src/policies/interfaces/deposits/IConvertibleDepositAuctioneer.sol";
import {IERC20} from "src/interfaces/IERC20.sol";

contract MockConvertibleDepositAuctioneer is IConvertibleDepositAuctioneer, Policy, PolicyEnabler {
    uint48 internal _initTimestamp;
    int256[] internal _auctionResults;

    IERC20 internal immutable _DEPOSIT_ASSET;

    uint256 public target;
    uint256 public tickSize;
    uint256 public minPrice;

    constructor(Kernel kernel_, address depositAsset_) Policy(kernel_) {
        _DEPOSIT_ASSET = IERC20(depositAsset_);
    }

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
        uint8,
        uint256 depositAmount_,
        uint256,
        bool,
        bool
    )
        external
        pure
        override
        returns (uint256 ohmOut, uint256 positionId, uint256 receiptTokenId, uint256 actualAmount)
    {
        return (depositAmount_, 0, 0, depositAmount_);
    }

    function previewBid(
        uint8,
        uint256 depositAmount_
    ) external pure override returns (uint256 ohmOut) {
        return (depositAmount_);
    }

    function getPreviousTick(uint8) external view override returns (Tick memory tick) {}

    function getCurrentTick(uint8) external view override returns (Tick memory tick) {}

    function getCurrentTickSize() external view override returns (uint256) {
        return tickSize;
    }

    function getAuctionParameters()
        external
        view
        override
        returns (AuctionParameters memory auctionParameters)
    {}

    function isAuctionActive() external view override returns (bool) {
        return target > 0;
    }

    function getDayState() external view override returns (Day memory day) {}

    function setAuctionParameters(
        uint256 newTarget,
        uint256 newSize,
        uint256 newMinPrice
    ) external override {
        // Mimic behaviour of the real auctioneer with error handling
        // Tick size must be non-zero when target is non-zero
        if (newTarget > 0 && newSize == 0) revert("tick size zero");

        // Min price must be non-zero when target is non-zero (can be zero when auction is disabled)
        if (newTarget > 0 && newMinPrice == 0) revert("min price zero");

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

    function enableDepositPeriod(uint8 depositPeriod_) external override {}

    function disableDepositPeriod(uint8 depositPeriod_) external override {}

    function getDepositAsset() external view override returns (IERC20) {
        return _DEPOSIT_ASSET;
    }

    function getDepositPeriods() external view override returns (uint8[] memory) {}

    function isDepositPeriodEnabled(
        uint8 depositPeriod_
    ) external view override returns (bool, bool) {}

    function getDepositPeriodsCount() external view override returns (uint256) {}
}
