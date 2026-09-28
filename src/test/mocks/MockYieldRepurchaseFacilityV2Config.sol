// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

import {IERC165} from "@openzeppelin-5.3.0/utils/introspection/IERC165.sol";
import {IYieldRepurchaseFacilityV2Config} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2Config.sol";

import {Address} from "@openzeppelin-5.3.0/utils/Address.sol";

import {Kernel, Keycode, Permissions, Policy} from "src/Kernel.sol";

/// @notice Stand-in for the configuration policy that YieldRepurchaseFacilityV2 binds as its
///         configurator.
/// @dev The facility accepts a configurator that is an active policy of its kernel,
///      advertises `IYieldRepurchaseFacilityV2Config`, and reports the facility as its
///      `facility()`. The stand-in satisfies exactly that: it declares no dependencies,
///      requests no module permissions, binds any facility through an ungated `setFacility`,
///      and relays any call through an ungated `forward`.
///
///      TODO: replace with YieldRepurchaseFacilityV2Config and its config timelock. The tests
///      that route a configuration call through `forward` then call the config policy, or
///      queue and execute through the timelock.
contract MockYieldRepurchaseFacilityV2Config is Policy, IYieldRepurchaseFacilityV2Config, IERC165 {
    /// @inheritdoc IYieldRepurchaseFacilityV2Config
    address public override facility;

    constructor(Kernel kernel_) Policy(kernel_) {}

    /// @inheritdoc Policy
    function configureDependencies()
        external
        pure
        override
        returns (Keycode[] memory dependencies)
    {
        return new Keycode[](0);
    }

    /// @inheritdoc Policy
    function requestPermissions() external pure override returns (Permissions[] memory requests) {
        return new Permissions[](0);
    }

    /// @notice Binds the facility reported by `facility()`.
    /// @param facility_ The facility to bind.
    function setFacility(address facility_) external {
        facility = facility_;
    }

    /// @notice Calls `target_` with `data_` from this contract's address.
    /// @dev Lets a test reach a facility function that trusts this address, without pranking it.
    ///      A revert of the call is bubbled up with its original data.
    /// @param target_ The contract to call.
    /// @param data_ The calldata of the call.
    /// @return result The return data of the call.
    function forward(address target_, bytes calldata data_) external returns (bytes memory result) {
        return Address.functionCall(target_, data_);
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId_) external pure override returns (bool) {
        return
            interfaceId_ == type(IYieldRepurchaseFacilityV2Config).interfaceId ||
            interfaceId_ == type(IERC165).interfaceId;
    }
}
