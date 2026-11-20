// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC4626} from "src/interfaces/IERC4626.sol";

/// @notice Minimal sUSDe interface required by the mainnet fork compatibility test.
/// @dev Ethena's MIT-licensed IStakedUSDe and IStakedUSDeCooldown interfaces omit the public
///      cooldownDuration getter and pin Solidity to 0.8.20. This local ABI subset supports the
///      repository compiler without importing the staking implementation.
///      Upstream: https://github.com/ethena-labs/bbp-public-assets/tree/f3e56d5f06bfef82367d5d5b561398e91d5bebc1/contracts/contracts/interfaces
interface IStakedUSDeV2 is IERC4626 {
    /// @notice Raised when synchronous redemption is disabled by the cooldown mode.
    error OperationNotAllowed();

    /// @notice Returns the active cooldown duration in seconds.
    function cooldownDuration() external view returns (uint24);
}
