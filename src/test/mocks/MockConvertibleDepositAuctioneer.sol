// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {Kernel, Policy, Keycode, toKeycode, Permissions} from "src/Kernel.sol";
import {RolesConsumer, ROLESv1} from "src/modules/ROLES/OlympusRoles.sol";
import {IConvertibleDepositAuctioneer} from "src/policies/interfaces/IConvertibleDepositAuctioneer.sol";

contract MockConvertibleDepositAuctioneer is IConvertibleDepositAuctioneer, Policy, RolesConsumer {
    constructor(Kernel kernel_) Policy(kernel_) {}

    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[2] = toKeycode("ROLES");

        ROLES = ROLESv1(getModuleAddress(dependencies[0]));
    }

    function requestPermissions()
        external
        view
        override
        returns (Permissions[] memory permissions)
    {}

    function bid(uint256 deposit) external override returns (uint256 convertable) {
        return deposit;
    }

    function getCurrentTick() external view override returns (Tick memory tick) {}

    function getState() external view override returns (State memory state) {}

    function getDayState() external view override returns (Day memory day) {}

    function bidToken() external view override returns (address token) {}

    function previewBid(
        uint256 deposit
    ) external view override returns (uint256 convertable, address depositSpender) {}

    function setAuctionParameters(
        uint256 newTarget,
        uint256 newSize,
        uint256 newMinPrice
    ) external override returns (uint256 remainder) {}

    function setTimeToExpiry(uint48 newTime) external override {}

    function setTickStep(uint24 newStep) external override {}

    function getTickStep() external view override returns (uint24) {}

    function getTimeToExpiry() external view override returns (uint48) {}
}
