// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.30;

import {WithEnvironment} from "src/scripts/WithEnvironment.s.sol";

/// @title LZBridgeTestnetBase
/// @notice Shared helpers for the testnet LZ bridge scripts: resolving the active chain from
///         `block.chainid`, reading the per-chain deployment files, and asserting the caller.
/// @dev Extended by `LZBridgeTestnetDeploy.s.sol` (deploy + configure) and
///      `LZBridgeTestnetSend.s.sol` (send).
abstract contract LZBridgeTestnetBase is WithEnvironment {
    // ========== ERRORS ========== //

    error LZTestnet_UnsupportedChainId(uint256 chainId);
    error LZTestnet_WrongCaller(string role, address expected, address actual);
    error LZTestnet_RemoteNotDeployed(string remoteChain);

    // ========== CHAIN RESOLUTION ========== //

    /// @dev Resolves the active chain name from `block.chainid` for the three supported testnets.
    function _resolveChain() internal view returns (string memory) {
        if (block.chainid == 11155111) return "sepolia";
        if (block.chainid == 84532) return "base-sepolia";
        if (block.chainid == 421614) return "arbitrum-sepolia";
        revert LZTestnet_UnsupportedChainId(block.chainid);
    }

    /// @dev Reverts with `LZTestnet_WrongCaller` if `actual_` is not `expected_`.
    function _requireCaller(string memory role_, address expected_, address actual_) internal pure {
        if (expected_ != actual_) revert LZTestnet_WrongCaller(role_, expected_, actual_);
    }

    // ========== DEPLOYMENT FILES ========== //

    function _deploymentPath(string memory chain_) internal pure returns (string memory) {
        return string.concat("./src/scripts/lz-bridge-testnet/deployments/", chain_, ".json");
    }

    /// @dev Reads the per-chain deployment JSON written by `deploy`, reverting if absent.
    function _readDeployment(string memory chain_) internal view returns (string memory) {
        string memory path = _deploymentPath(chain_);
        if (!vm.exists(path)) revert LZTestnet_RemoteNotDeployed(chain_);
        return vm.readFile(path);
    }
}
