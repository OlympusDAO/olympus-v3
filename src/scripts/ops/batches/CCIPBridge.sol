// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.24;

import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";
import {ChainUtils} from "src/scripts/ops/lib/ChainUtils.sol";
import {ArrayUtils} from "src/scripts/ops/lib/ArrayUtils.sol";
import {console2} from "@forge-std-1.9.6/console2.sol";

import {ICCIPCrossChainBridge} from "src/periphery/interfaces/ICCIPCrossChainBridge.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {Owned} from "solmate/auth/Owned.sol";

contract CCIPBridgeBatch is BatchScriptV2 {
    // [X] Declarative configuration of a bridge
    // [X] Enable trusted remotes for the specified chains
    // [X] Management of gas limit

    bytes32 public constant SOLANA_RECEIVER =
        0x0000000000000000000000000000000000000000000000000000000000000000;
    uint32 public constant EVM_GAS_LIMIT = 200_000;

    /// @notice Sets trusted remotes and enables the bridge for the specified chain
    function enable(string calldata chain_, bool useDaoMS_) external setUp(chain_, useDaoMS_) {
        // Set the trusted remotes
        _setAllTrustedRemotes(chain_);

        // Set the bridge to enabled
        console2.log("\n");
        console2.log("Enabling bridge for", chain_);
        address bridgeAddress = _envAddressNotZero("olympus.periphery.CCIPCrossChainBridge");
        addToBatch(bridgeAddress, abi.encodeWithSelector(IEnabler.enable.selector, ""));

        // Run
        proposeBatch();
    }

    /// @notice Disables the bridge for the specified chain
    function disable(string calldata chain_, bool useDaoMS_) external setUp(chain_, useDaoMS_) {
        // Set the bridge to disabled
        console2.log("\n");
        console2.log("Disabling bridge for", chain_);
        address bridgeAddress = _envAddressNotZero("olympus.periphery.CCIPCrossChainBridge");
        addToBatch(bridgeAddress, abi.encodeWithSelector(IEnabler.disable.selector, ""));

        // Run
        proposeBatch();

        console2.log("Completed");
    }

    /// @notice Sets the trusted remote for an EVM chain
    /// @dev    Handles the following scenarios:
    ///         - No bridge for the local chain: skips
    ///         - Trusted remote is already set: skips
    ///         - Trusted remote is not the same: sets to the remote bridge address (or zero address if the remote chain has no bridge)
    function _setTrustedRemoteEVM(string memory remoteChain_, bool shouldReset_) internal {
        // Validate that the chain is an EVM chain
        if (ChainUtils._isSVMChain(remoteChain_)) {
            // solhint-disable-next-line gas-custom-errors
            revert("_setTrustedRemoteEVM: Chain is not an EVM chain");
        }

        address bridgeAddress = _envAddress("olympus.periphery.CCIPCrossChainBridge");
        if (bridgeAddress == address(0)) {
            console2.log("\n");
            console2.log("  No bridge found for", chain, ". Skipping.");
            console2.log("\n");
            return;
        }

        uint64 remoteChainSelector = uint64(
            _envUintNotZero(remoteChain_, "external.ccip.ChainSelector")
        );
        ICCIPCrossChainBridge.TrustedRemoteEVM memory trustedRemote = ICCIPCrossChainBridge(
            bridgeAddress
        ).getTrustedRemoteEVM(remoteChainSelector);

        console2.log("\n");
        console2.log("  Destination EVM chain:", remoteChain_);

        // If resetting the trusted remote, then it should be unset
        if (shouldReset_) {
            if (trustedRemote.isSet) {
                addToBatch(
                    bridgeAddress,
                    abi.encodeWithSelector(
                        ICCIPCrossChainBridge.unsetTrustedRemoteEVM.selector,
                        remoteChainSelector
                    )
                );

                console2.log("  Trusted remote unset");
                console2.log("\n");
                return;
            }

            console2.log("  Trusted remote is not active. No change needed.");
            console2.log("\n");
            return;
        }

        address remoteBridgeAddress = _envAddressNotZero(
            remoteChain_,
            "olympus.periphery.CCIPCrossChainBridge"
        );

        // If the trusted remote should not be set
        if (trustedRemote.isSet && trustedRemote.remoteAddress == remoteBridgeAddress) {
            console2.log(
                "  Trusted remote is already set to",
                vm.toString(remoteBridgeAddress),
                ". No change needed."
            );
            console2.log("\n");
            return;
        }

        // Set the trusted remote
        addToBatch(
            bridgeAddress,
            abi.encodeWithSelector(
                ICCIPCrossChainBridge.setTrustedRemoteEVM.selector,
                remoteChainSelector,
                remoteBridgeAddress
            )
        );

        console2.log("  Trusted remote set to", vm.toString(remoteBridgeAddress));
        console2.log("\n");

        // Set the gas limit
        addToBatch(
            bridgeAddress,
            abi.encodeWithSelector(
                ICCIPCrossChainBridge.setGasLimit.selector,
                remoteChainSelector,
                EVM_GAS_LIMIT
            )
        );

        console2.log("  Gas limit set to", EVM_GAS_LIMIT);
        console2.log("\n");
    }

    function setTrustedRemoteEVM(
        string calldata chain_,
        bool useDaoMS_,
        string calldata remoteChain_
    ) external setUp(chain_, useDaoMS_) {
        // Set the trusted remote
        _setTrustedRemoteEVM(remoteChain_, false);

        // Run
        proposeBatch();

        console2.log("Completed");
    }

    function _setTrustedRemoteSVM(string memory remoteChain_, bool shouldReset_) internal {
        // Validate that the chain is an SVM chain
        if (!ChainUtils._isSVMChain(remoteChain_)) {
            // solhint-disable-next-line gas-custom-errors
            revert("_setTrustedRemoteSVM: Chain is not an SVM chain");
        }

        address bridgeAddress = _envAddressNotZero("olympus.periphery.CCIPCrossChainBridge");
        if (bridgeAddress == address(0)) {
            console2.log("\n");
            console2.log("  No bridge found for", chain, ". Skipping.");
            console2.log("\n");
            return;
        }

        uint64 remoteChainSelector = uint64(
            _envUintNotZero(remoteChain_, "external.ccip.ChainSelector")
        );
        ICCIPCrossChainBridge.TrustedRemoteSVM memory trustedRemote = ICCIPCrossChainBridge(
            bridgeAddress
        ).getTrustedRemoteSVM(remoteChainSelector);

        console2.log("\n");
        console2.log("  Destination SVM chain:", remoteChain_);

        // If resetting the trusted remote, then it should be unset
        if (shouldReset_) {
            if (trustedRemote.isSet) {
                addToBatch(
                    bridgeAddress,
                    abi.encodeWithSelector(
                        ICCIPCrossChainBridge.unsetTrustedRemoteSVM.selector,
                        remoteChainSelector
                    )
                );

                console2.log("  Trusted remote unset");
                console2.log("\n");
                return;
            }

            console2.log("  Trusted remote is not active. No change needed.");
            console2.log("\n");
            return;
        }

        bytes32 remotePubKey = SOLANA_RECEIVER;

        // If the trusted remote is already set, no need to set it again
        if (trustedRemote.isSet && trustedRemote.remoteAddress == remotePubKey) {
            console2.log("  Trusted remote is already set. No change needed.");
            console2.log("\n");
            return;
        }

        // Set the trusted remote
        addToBatch(
            bridgeAddress,
            abi.encodeWithSelector(
                ICCIPCrossChainBridge.setTrustedRemoteSVM.selector,
                remoteChainSelector,
                remotePubKey
            )
        );

        // Note: at this stage, no need to set the gas limit, as it should be 0 and is 0 by default
    }

    function setTrustedRemoteSVM(
        string calldata chain_,
        bool useDaoMS_,
        string calldata remoteChain_
    ) external setUp(chain_, useDaoMS_) {
        // Set the trusted remote
        _setTrustedRemoteSVM(remoteChain_, false);

        // Run
        proposeBatch();

        console2.log("Completed");
    }

    function _setAllTrustedRemotes(string memory chain_) internal {
        console2.log("\n");
        console2.log("Setting all trusted remotes for", chain_);

        string[] memory allChains = ChainUtils._getChains(chain_);
        string[] memory trustedChains = _envStringArray(
            "olympus.config.CCIPCrossChainBridge.chains"
        );

        // Iterate over all chains
        for (uint256 i = 0; i < allChains.length; i++) {
            string memory remoteChain = allChains[i];

            // Skip the current chain
            if (keccak256(abi.encodePacked(chain_)) == keccak256(abi.encodePacked(remoteChain))) {
                continue;
            }

            // If the chain is not in the trusted chains listed in the config, then it should be removed as a trusted remote
            bool isTrustedChain = ArrayUtils.contains(trustedChains, remoteChain);

            if (ChainUtils._isSVMChain(remoteChain)) {
                _setTrustedRemoteSVM(remoteChain, !isTrustedChain);
            } else {
                _setTrustedRemoteEVM(remoteChain, !isTrustedChain);
            }
        }
    }

    /// @notice Sets the bridges on all other chains as trusted remotes for the source chain
    /// @dev    This currently does not support selectively enabling bridging for specific chains
    ///
    ///         This function skips the function call if the trusted remote is already set to the correct value
    function setAllTrustedRemotes(
        string calldata chain_,
        bool useDaoMS_
    ) external setUp(chain_, useDaoMS_) {
        // Set the trusted remotes
        _setAllTrustedRemotes(chain_);

        // Run
        proposeBatch();
    }

    function transferOwnership(
        string calldata chain_,
        bool useDaoMS_
    ) external setUp(chain_, useDaoMS_) {
        address bridgeAddress = _envAddressNotZero("olympus.periphery.CCIPCrossChainBridge");
        address newOwner = _envAddressNotZero("olympus.multisig.dao");

        // Check if the owner is already the new owner
        if (Owned(bridgeAddress).owner() == newOwner) {
            console2.log("Owner", newOwner, "is already the new owner. Skipping.");
            return;
        }

        console2.log("\n");
        console2.log(
            "Transferring ownership of",
            vm.toString(bridgeAddress),
            "to",
            vm.toString(newOwner)
        );

        addToBatch(
            bridgeAddress,
            abi.encodeWithSelector(Owned.transferOwnership.selector, newOwner)
        );

        // Run
        proposeBatch();
    }
}
