// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.7.0/interfaces/IERC165.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IBackingOracle} from "src/policies/interfaces/IBackingOracle.sol";

contract MockBackingOracle is IBackingOracle, IERC165, IVersioned {
    uint256 public override backing;

    constructor(uint256 backing_) {
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
            interfaceId_ == type(IVersioned).interfaceId ||
            interfaceId_ == type(IERC165).interfaceId ||
            interfaceId_ == type(IBackingOracle).interfaceId;
    }

    /// @inheritdoc IVersioned
    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        return (1, 0);
    }
}
