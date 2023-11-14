// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

/// @dev    Interface for the Aura base reward pool
///         Example contract: https://etherscan.io/address/0xB9D6ED734Ccbdd0b9CadFED712Cf8AC6D0917EcD
interface IAuraRewardPool {
    function balanceOf(address account_) external view returns (uint256);

    function asset() external view returns (address);
}
