// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.20;

import {IERC4626} from "src/interfaces/IERC4626.sol";

/// @notice Minimal sUSDe interface required by the mainnet fork compatibility test.
interface IStakedUSDeV2 is IERC4626 {
    /// @notice Raised when synchronous redemption is disabled by the cooldown mode.
    error OperationNotAllowed();

    /// @notice Returns the active cooldown duration in seconds.
    function cooldownDuration() external view returns (uint24);
}
