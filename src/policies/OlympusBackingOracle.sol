// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.30;

// Interfaces
import {IOlympusBackingOracle} from "src/policies/interfaces/IOlympusBackingOracle.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";

// Contracts
import {EnablerV2} from "src/bases/EnablerV2.sol";
import {ROLESv1} from "modules/ROLES/ROLES.v1.sol";
import {Kernel, Keycode, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {PolicyEnablerV2} from "src/policies/utils/PolicyEnablerV2.sol";

/// @title OlympusBackingOracle
/// @notice A policy that serves as the canonical OHM backing value (the reserve per OHM, 18 decimals).
contract OlympusBackingOracle is Policy, PolicyEnablerV2, IOlympusBackingOracle, IVersioned {
    // ========== CONSTANTS ========== //

    uint256 private constant _ENABLE_DATA_LENGTH = 32;
    uint256 private constant _MAX_BACKING_REDUCTION_PERCENT = 10;
    uint256 private constant _PERCENT_SCALE = 100;

    // ========== STATE ========== //

    /// @inheritdoc IOlympusBackingOracle
    uint256 public override backing;

    // ========== INITIALIZATION & POLICY SETUP ========== //

    constructor(Kernel kernel_) Policy(kernel_) {
        if (address(kernel_) == address(0)) revert OlympusBackingOracle_ZeroKernelAddress();

        // Disabled by default
    }

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("ROLES");

        ROLES = ROLESv1(getModuleAddress(dependencies[0]));

        (uint8 m, ) = ROLES.VERSION();
        if (m != 1) revert Policy_WrongModuleVersion(abi.encode([1]));

        return dependencies;
    }

    /// @inheritdoc Policy
    /// @dev A read-only policy; no module writes are required.
    function requestPermissions() external pure override returns (Permissions[] memory) {}

    /// @inheritdoc IVersioned
    function VERSION() external pure returns (uint8, uint8) {
        return (1, 0);
    }

    // ========== ENABLE ========== //

    /// @inheritdoc EnablerV2
    /// @dev Sets the `backing`.
    ///
    ///      Reverts if:
    ///      - The enable data is not the correct length.
    ///      - The initial backing value is zero.
    function _beforeEnable(bytes calldata data_) internal override {
        if (data_.length != _ENABLE_DATA_LENGTH)
            revert OlympusBackingOracle_InvalidEnableDataLength();
        uint256 initialBacking = abi.decode(data_, (uint256));
        _requireNonzeroBacking(initialBacking);

        _setBacking(initialBacking);
    }

    // ========== ADMIN FUNCTIONS ========== //

    /// @inheritdoc IOlympusBackingOracle
    /// @dev Reverts if:
    ///      - The caller does not have the admin role.
    ///      - The policy is not enabled.
    ///      - `newBacking_` is zero.
    ///      - `newBacking_` reduces the current backing beyond the allowed threshold (`_MAX_BACKING_REDUCTION_PERCENT`).
    function setBacking(uint256 newBacking_) external givenEnabled onlyAdminRole {
        _requireNonzeroBacking(newBacking_);

        uint256 currentBacking = backing;
        // Cannot reduce by more than _MAX_BACKING_REDUCTION_PERCENT per call
        uint256 minBacking = (currentBacking * (_PERCENT_SCALE - _MAX_BACKING_REDUCTION_PERCENT)) /
            _PERCENT_SCALE;
        if (newBacking_ < minBacking)
            revert OlympusBackingOracle_BackingReductionTooLarge(
                currentBacking,
                newBacking_,
                minBacking
            );

        _setBacking(newBacking_);
    }

    // ========== INTERNAL HELPERS ========== //

    function _setBacking(uint256 backing_) private {
        backing = backing_;
        emit BackingSet(backing_);
    }

    function _requireNonzeroBacking(uint256 backing_) private pure {
        if (backing_ == 0) revert OlympusBackingOracle_ZeroBacking();
    }

    // ========== ERC165 ========== //

    /// @inheritdoc EnablerV2
    function supportsInterface(
        bytes4 interfaceId_
    ) public view virtual override(EnablerV2) returns (bool) {
        return
            interfaceId_ == type(IOlympusBackingOracle).interfaceId ||
            interfaceId_ == type(IVersioned).interfaceId ||
            super.supportsInterface(interfaceId_);
    }
}
