// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.7.0/interfaces/IERC165.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBackingOracle} from "src/policies/interfaces/IBackingOracle.sol";

// Contracts
import {Kernel, Keycode, Permissions, Policy} from "src/Kernel.sol";

/// @dev Unrestricted fixture injection; backing remains readable independently of lifecycle.
contract MockBackingOracle is Policy, IBackingOracle, IEnabler, IERC165 {
    bool public override isEnabled = true;
    uint256 public override backing;

    constructor(Kernel kernel_, uint256 backing_) Policy(kernel_) {
        backing = backing_;
    }

    function setBacking(uint256 backing_) external override {
        backing = backing_;
        emit BackingSet(backing_);
    }

    /// @inheritdoc IBackingOracle
    /// @dev Fixture injection accepts any value, matching the unbounded setter.
    function validateSetBacking(uint256) external pure override {}

    /// @inheritdoc IBackingOracle
    function decimals() external pure override returns (uint8) {
        return 18;
    }

    function supportsInterface(bytes4 interfaceId_) external pure override returns (bool) {
        return
            interfaceId_ == type(IEnabler).interfaceId ||
            interfaceId_ == type(IERC165).interfaceId ||
            interfaceId_ == type(IBackingOracle).interfaceId;
    }

    function setEnabled(bool enabled_) external {
        isEnabled = enabled_;
    }

    function enable(bytes calldata) external override {
        isEnabled = true;
        emit Enabled();
    }

    function disable(bytes calldata) external override {
        isEnabled = false;
        emit Disabled();
    }

    function configureDependencies() external pure override returns (Keycode[] memory) {
        return new Keycode[](0);
    }

    function requestPermissions() external pure override returns (Permissions[] memory) {
        return new Permissions[](0);
    }
}
