// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.24;

import {OlyBatch} from "src/scripts/ops/OlyBatch.sol";

import {Kernel, Actions} from "src/Kernel.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

import {console2} from "forge-std/console2.sol";

/// @title ConfigureCCIPTokenPool
/// @notice Multi-sig batch to configure the CCIP bridge
///         This scripts is designed to define the desired configuration,
///         and the script will execute the necessary transactions to
///         configure the CCIP bridge to the desired state.
contract CCIPTokenPoolBatch is OlyBatch {
    address public kernel;
    address public tokenPool;
    address public crossChainBridge;

    /// @dev Returns true if the chain is canonical chain upon which new OHM is minted (mainnet or sepolia)
    function _isChainCanonical(string memory chain_) internal pure returns (bool) {
        return
            keccak256(abi.encodePacked(chain_)) == keccak256(abi.encodePacked("mainnet")) ||
            keccak256(abi.encodePacked(chain_)) == keccak256(abi.encodePacked("sepolia"));
    }

    function _getTokenPoolAddress(string memory chain_) internal view returns (address) {
        if (_isChainCanonical(chain_)) {
            return _envAddressNotZero("olympus.policies.CCIPLockReleaseTokenPool");
        } else {
            return _envAddressNotZero("olympus.policies.CCIPBurnMintTokenPool");
        }
    }

    function _envAddressNotZero(string memory key_) internal view returns (address) {
        address addressValue = envAddress("current", key_);
        if (addressValue == address(0)) {
            // solhint-disable-next-line gas-custom-errors
            revert("Address is not set");
        }

        return addressValue;
    }

    function loadEnv() internal override {
        // Load contract addresses from the environment file
        kernel = envAddress("current", "olympus.Kernel");
        tokenPool = _getTokenPoolAddress(chain);
        crossChainBridge = _envAddressNotZero("olympus.periphery.CCIPCrossChainBridge");
    }

    function install(bool send_) external isDaoBatch(send_) {
        // Assumptions
        // - The token pool has been linked to OHM in the CCIP token admin registry
        // - The token pool is already configured

        // Install the TokenPool policy
        if (!_isChainCanonical(chain)) {
            console2.log("Installing TokenPool policy into Kernel");
            addToBatch(
                kernel,
                abi.encodeWithSelector(
                    Kernel.executeAction.selector,
                    Actions.ActivatePolicy,
                    tokenPool
                )
            );
        } else {
            console2.log("Enabling TokenPool periphery contract");
            addToBatch(tokenPool, abi.encodeWithSelector(IEnabler.enable.selector, ""));
        }

        // Enable the CCIPCrossChainBridge
        console2.log("Enabling CCIPCrossChainBridge");
        addToBatch(crossChainBridge, abi.encodeWithSelector(IEnabler.enable.selector, ""));

        console2.log("Completed");

        // Next steps:
        // - Non-canonical chains: Governance to enable the TokenPool policy
    }
}
