// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {Kernel, Policy, Keycode, toKeycode, Permissions} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/OlympusRoles.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";
import {IConvertibleDepositAuctioneer} from "src/policies/interfaces/IConvertibleDepositAuctioneer.sol";

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
        uint256 deposit
    ) external pure override returns (uint256 convertable, uint256 positionId) {
        return (deposit, 0);
    }

    function getPreviousTick() external view override returns (Tick memory tick) {}

    function getCurrentTick() external view override returns (Tick memory tick) {}

    function getAuctionParameters()
        external
        view
        override
        returns (AuctionParameters memory auctionParameters)
    {}

    function getDayState() external view override returns (Day memory day) {}

    function previewBid(
        uint256 deposit
    ) external view override returns (uint256 convertable, address depositSpender) {}

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

    function setTimeToExpiry(uint48 newTime) external override {}

    function setRedemptionPeriod(uint48 newPeriod) external override {}

    function setTickStep(uint24 newStep) external override {}

    function getTickStep() external view override returns (uint24) {}

    function getTimeToExpiry() external view override returns (uint48) {}

    function getRedemptionPeriod() external view override returns (uint48) {}

    function getAuctionTrackingPeriod() external view override returns (uint8) {}

    function getAuctionResults() external view override returns (int256[] memory) {
        return _auctionResults;
    }

    function getAuctionResultsNextIndex() external view override returns (uint8) {}

    function setAuctionTrackingPeriod(uint8 newPeriod) external override {}
}
