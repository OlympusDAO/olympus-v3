// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.24;

import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";
import {ChainHelper} from "src/scripts/ops/lib/Chain.sol";
import {console2} from "@forge-std-1.9.6/console2.sol";

import {ICCIPCrossChainBridge} from "src/periphery/interfaces/ICCIPCrossChainBridge.sol";

contract CCIPBridgeBatch is BatchScriptV2 {
    // TODOs
    // [X] Declarative configuration of a bridge
    // [ ] Enable trusted remotes for the specified chains

    bytes32 public constant SOLANA_RECEIVER =
        0x0000000000000000000000000000000000000000000000000000000000000000;

    function _setTrustedRemoteEVM(string calldata remoteChain_) internal {
        // Validate that the chain is an EVM chain
        if (ChainHelper._isSVMChain(remoteChain_)) {
            // solhint-disable-next-line gas-custom-errors
            revert("_setTrustedRemoteEVM: Chain is not an EVM chain");
        }

        address bridgeAddress = _envAddressNotZero("olympus.periphery.CCIPCrossChainBridge");
        uint64 remoteChainSelector = uint64(
            _envUintNotZero(remoteChain_, "external.ccip.ChainSelector")
        );
        address remoteBridgeAddress = _envAddressNotZero(
            remoteChain_,
            "olympus.periphery.CCIPCrossChainBridge"
        );

        if (
            address(ICCIPCrossChainBridge(bridge).getTrustedRemoteEVM(remoteChainSelector)) ==
            remoteBridgeAddress
        ) {
            console2.log("  Trusted remote for EVM chain", remoteChain, "is already set");
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

        console2.log("  Set trusted remote for EVM chain", remoteChain_);
    }

    function setTrustedRemoteEVM(
        string calldata chain_,
        bool useDaoMS_,
        string calldata remoteChain_
    ) external setUp(chain_, useDaoMS_) {
        // Set the trusted remote
        _setTrustedRemoteEVM(remoteChain_);

        // Run
        proposeBatch();

        console2.log("Completed");
    }

    function _setTrustedRemoteSVM(string calldata remoteChain_) internal {
        // Validate that the chain is an SVM chain
        if (!ChainHelper._isSVMChain(remoteChain_)) {
            // solhint-disable-next-line gas-custom-errors
            revert("_setTrustedRemoteSVM: Chain is not an SVM chain");
        }

        address bridgeAddress = _envAddressNotZero("olympus.periphery.CCIPCrossChainBridge");
        uint64 remoteChainSelector = uint64(
            _envUintNotZero(remoteChain_, "external.ccip.ChainSelector")
        );
        bytes32 remotePubKey = SOLANA_RECEIVER;

        if (
            ICCIPCrossChainBridge(bridgeAddress).getTrustedRemoteSVM(remoteChainSelector) ==
            remotePubKey
        ) {
            console2.log("  Trusted remote for SVM chain", remoteChain_, "is already set");
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

        console2.log("  Set trusted remote for SVM chain", remoteChain_);
    }

    function setTrustedRemoteSVM(
        string calldata chain_,
        bool useDaoMS_,
        string calldata remoteChain_
    ) external setUp(chain_, useDaoMS_) {
        // Set the trusted remote
        _setTrustedRemoteSVM(remoteChain_);

        // Run
        proposeBatch();

        console2.log("Completed");
    }

    /// @notice Sets the bridges on all other chains as trusted remotes for the source chain
    /// @dev    This currently does not support selectively enabling bridging for specific chains
    ///
    ///         This function skips the function call if the trusted remote is already set to the correct value
    function setAllTrustedRemotes(
        string calldata chain_,
        bool useDaoMS_
    ) external setUp(chain_, useDaoMS_) {
        console2.log("Setting all trusted remotes for", chain_);

        string[] memory allChains = ChainHelper._getChains(chain_);

        // Iterate over all chains
        for (uint256 i = 0; i < allChains.length; i++) {
            string memory remoteChain = allChains[i];

            // Skip the current chain
            if (keccak256(abi.encodePacked(chain_)) == keccak256(abi.encodePacked(remoteChain))) {
                continue;
            }

            if (ChainHelper._isEVMChain(remoteChain)) {
                _setTrustedRemoteEVM(remoteChain);
            } else if (ChainHelper._isSVMChain(remoteChain)) {
                _setTrustedRemoteSVM(remoteChain);
            }
        }

        // Run
        proposeBatch();
    }
}
