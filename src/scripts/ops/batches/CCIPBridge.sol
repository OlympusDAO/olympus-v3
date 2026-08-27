// SPDX-License-Identifier: Unlicensed
// solhint-disable custom-errors
pragma solidity ^0.8.24;

import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";
import {console2} from "@forge-std-1.16.2/console2.sol";

// Interfaces
import {ICCIPCrossChainBridge} from "src/periphery/interfaces/ICCIPCrossChainBridge.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

// Libraries
import {ArrayUtils} from "src/scripts/ops/lib/ArrayUtils.sol";
import {CCIPConfigLib} from "src/scripts/ops/lib/CCIPConfigLib.sol";
import {ChainUtils} from "src/scripts/ops/lib/ChainUtils.sol";

// Contracts
import {Owned} from "@solmate-6.2.0/auth/Owned.sol";

/// @title CCIPBridge
/// @notice Declarative reconciliation of the CCIPCrossChainBridge periphery against `env.json`.
///         The desired state is the `periphery` block of each route under
///         `olympus.config.CCIP.routes.<remoteChain>`; the live state is the periphery contract;
///         the batch contains only the calls that converge the two.
///
///         Entry points, each gated on the batch owner being the periphery owner:
///         - `reconcileTrustedRemotes`: compare the trusted remote and the gas limit of every
///           declared remote chain independently, and add only the differing fields. A remote is
///           unset only for a route or `periphery` block declared with `enabled: false`; a live
///           trusted remote whose route has no `periphery` block is reported and left untouched.
///           A second run on a converged state proposes nothing.
///         - `enable` / `disable`: switch the periphery lifecycle flag, conditionally.
///         - `transferOwnership`: transfer the periphery to the DAO MS (run by the deployer once
///           after the deploy sequence).
///
///         The legacy `olympus.config.CCIPCrossChainBridge.chains` list is not read by the
///         reconciler; it remains for the direct pool owner functions of `CCIPTokenPool.sol`,
///         and a drift between it and the set of `periphery` blocks is reported.
contract CCIPBridge is BatchScriptV2 {
    // =========== ENTRY POINTS =========== //

    /// @notice Converges the trusted remotes and the gas limits of the periphery to the
    ///         `periphery` blocks of `env.json`.
    /// @dev    The trusted remote and the gas limit are compared independently, so a matching
    ///         remote does not mask a stale gas limit. Removals require the explicit marker
    ///         (`enabled: false` on the route or on its `periphery` block); removing a trusted
    ///         remote stops the periphery from sending to and accepting from that chain, while
    ///         messages already in flight toward this chain are then recorded as failed and stay
    ///         retryable. A removal only unsets the trusted remote: the stored gas limit is
    ///         left in place, since it is inert without one.
    ///
    ///         Reverts if:
    ///         - The args file is not empty.
    ///         - The batch owner is not the owner of the periphery.
    ///         - A declared periphery block is malformed (see `CCIPConfigLib`).
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    /// @param signOnly_ Whether to only sign the batch without proposing/executing it.
    /// @param argsFile_ Path to the arguments file (unused, must be empty).
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    /// @param signature_ Optional pre-computed signature for the batch.
    function reconcileTrustedRemotes(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath_, signature_) {
        _validateArgsFileEmpty(argsFile_);
        // The batch touches only the CCIP periphery
        _skipHeartbeatValidation = true;

        ICCIPCrossChainBridge bridge = _bridge();
        CCIPConfigLib.DesiredPeriphery[] memory desired = CCIPConfigLib.desiredPeripheries(
            env,
            chain
        );

        console2.log("\n=== Reconcile the CCIPCrossChainBridge trusted remotes ===");
        console2.log("Periphery:", address(bridge));
        console2.log("Declared periphery blocks:", desired.length);

        _warnLegacyChainsDrift(desired);

        uint256 planned;
        for (uint256 i; i < desired.length; ++i) {
            planned += _planPeriphery(bridge, desired[i]);
        }
        _reportUnmanagedRemotes(bridge, desired);

        if (planned == 0) {
            console2.log("\nNo change needed: the periphery matches env.json.");
        }

        _setPostBatchValidateSelector(this._validateReconciled.selector);

        proposeBatch();
    }

    /// @notice Enables the periphery, conditionally.
    /// @dev    Enabling does not configure trusted remotes; run `reconcileTrustedRemotes` for
    ///         that.
    ///
    ///         Reverts if:
    ///         - The args file is not empty.
    ///         - The batch owner is not the owner of the periphery.
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    /// @param signOnly_ Whether to only sign the batch without proposing/executing it.
    /// @param argsFile_ Path to the arguments file (unused, must be empty).
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    /// @param signature_ Optional pre-computed signature for the batch.
    function enable(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath_, signature_) {
        _validateArgsFileEmpty(argsFile_);
        _skipHeartbeatValidation = true;

        ICCIPCrossChainBridge bridge = _bridge();
        console2.log("\n=== Enable the CCIPCrossChainBridge periphery ===");
        if (IEnabler(address(bridge)).isEnabled()) {
            console2.log("The periphery is already enabled. Nothing to do.");
        } else {
            addToBatch(address(bridge), abi.encodeWithSelector(IEnabler.enable.selector, ""));
            console2.log("Added: enable()");
        }

        proposeBatch();
    }

    /// @notice Disables the periphery, conditionally.
    /// @dev    Disabling the periphery does not stop CCIP transfers of OHM: the pool stays
    ///         registered and any address can call the router directly. Messages received while
    ///         disabled are recorded as failed and stay retryable.
    ///
    ///         Reverts if:
    ///         - The args file is not empty.
    ///         - The batch owner is not the owner of the periphery.
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    /// @param signOnly_ Whether to only sign the batch without proposing/executing it.
    /// @param argsFile_ Path to the arguments file (unused, must be empty).
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    /// @param signature_ Optional pre-computed signature for the batch.
    function disable(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath_, signature_) {
        _validateArgsFileEmpty(argsFile_);
        _skipHeartbeatValidation = true;

        ICCIPCrossChainBridge bridge = _bridge();
        console2.log("\n=== Disable the CCIPCrossChainBridge periphery ===");
        if (!IEnabler(address(bridge)).isEnabled()) {
            console2.log("The periphery is already disabled. Nothing to do.");
        } else {
            addToBatch(address(bridge), abi.encodeWithSelector(IEnabler.disable.selector, ""));
            console2.log("Added: disable()");
        }

        proposeBatch();
    }

    /// @notice Transfers the ownership of the periphery to the DAO MS, conditionally.
    /// @dev    Run by the deployer once after the deploy sequence (`useDaoMS` false). The
    ///         solmate ownership transfer is single step.
    ///
    ///         Reverts if:
    ///         - The args file is not empty.
    ///         - A transfer is due and the batch owner is not the owner of the periphery.
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    /// @param signOnly_ Whether to only sign the batch without proposing/executing it.
    /// @param argsFile_ Path to the arguments file (unused, must be empty).
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    /// @param signature_ Optional pre-computed signature for the batch.
    function transferOwnership(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath_, signature_) {
        _validateArgsFileEmpty(argsFile_);
        _skipHeartbeatValidation = true;

        address bridgeAddress = _envAddressNotZero(CCIPConfigLib.EVM_BRIDGE_KEY);
        address daoMS = _envAddressNotZero("olympus.multisig.dao");

        console2.log("\n=== Transfer the CCIPCrossChainBridge ownership to the DAO MS ===");
        if (Owned(bridgeAddress).owner() == daoMS) {
            console2.log("The DAO MS already owns the periphery. Nothing to do.");
        } else {
            _requireBridgeOwner(bridgeAddress);
            addToBatch(
                bridgeAddress,
                abi.encodeWithSelector(Owned.transferOwnership.selector, daoMS)
            );
            console2.log("Added: transferOwnership(", daoMS, ")");
        }

        proposeBatch();
    }

    // =========== VALIDATION =========== //

    /// @notice Validates the state after `reconcileTrustedRemotes`.
    function _validateReconciled() external view {
        ICCIPCrossChainBridge bridge = ICCIPCrossChainBridge(
            _envAddressNotZero(CCIPConfigLib.EVM_BRIDGE_KEY)
        );
        CCIPConfigLib.DesiredPeriphery[] memory desired = CCIPConfigLib.desiredPeripheries(
            env,
            chain
        );

        console2.log("\nValidating reconcileTrustedRemotes post-batch state");
        for (uint256 i; i < desired.length; ++i) {
            CCIPConfigLib.DesiredPeriphery memory entry = desired[i];
            if (entry.isSvm) {
                ICCIPCrossChainBridge.TrustedRemoteSVM memory live = bridge.getTrustedRemoteSVM(
                    entry.chainSelector
                );
                if (!entry.enabled) {
                    require(
                        !live.isSet,
                        string.concat("SVM trusted remote is still set: ", entry.remoteChain)
                    );
                } else {
                    require(
                        live.isSet && live.remoteAddress == entry.svmTrustedRemote,
                        string.concat("SVM trusted remote mismatch: ", entry.remoteChain)
                    );
                }
            } else {
                ICCIPCrossChainBridge.TrustedRemoteEVM memory live = bridge.getTrustedRemoteEVM(
                    entry.chainSelector
                );
                if (!entry.enabled) {
                    require(
                        !live.isSet,
                        string.concat("EVM trusted remote is still set: ", entry.remoteChain)
                    );
                } else {
                    require(
                        live.isSet && live.remoteAddress == entry.evmTrustedRemote,
                        string.concat("EVM trusted remote mismatch: ", entry.remoteChain)
                    );
                }
            }
            if (entry.enabled) {
                require(
                    bridge.getGasLimit(entry.chainSelector) == entry.gasLimit,
                    string.concat("Gas limit mismatch: ", entry.remoteChain)
                );
            }
            console2.log("  Converged:", entry.remoteChain);
        }
        console2.log("reconcileTrustedRemotes post-batch validation passed");
    }

    // =========== PLANNING =========== //

    /// @return planned The number of calls added for this remote chain.
    function _planPeriphery(
        ICCIPCrossChainBridge bridge_,
        CCIPConfigLib.DesiredPeriphery memory entry_
    ) internal returns (uint256 planned) {
        console2.log("\nRemote", entry_.remoteChain, "selector", entry_.chainSelector);

        if (entry_.isSvm) {
            ICCIPCrossChainBridge.TrustedRemoteSVM memory live = bridge_.getTrustedRemoteSVM(
                entry_.chainSelector
            );
            console2.log("  live remote:", live.isSet ? vm.toString(live.remoteAddress) : "unset");
            if (!entry_.enabled) {
                return _planUnsetSvm(bridge_, entry_, live.isSet);
            }
            console2.log("  desired remote:", vm.toString(entry_.svmTrustedRemote));
            if (!live.isSet || live.remoteAddress != entry_.svmTrustedRemote) {
                addToBatch(
                    address(bridge_),
                    abi.encodeWithSelector(
                        ICCIPCrossChainBridge.setTrustedRemoteSVM.selector,
                        entry_.chainSelector,
                        entry_.svmTrustedRemote
                    )
                );
                console2.log("  Added: setTrustedRemoteSVM");
                planned++;
            } else {
                console2.log("  Trusted remote matches.");
            }
        } else {
            ICCIPCrossChainBridge.TrustedRemoteEVM memory live = bridge_.getTrustedRemoteEVM(
                entry_.chainSelector
            );
            console2.log("  live remote:", live.isSet ? vm.toString(live.remoteAddress) : "unset");
            if (!entry_.enabled) {
                return _planUnsetEvm(bridge_, entry_, live.isSet);
            }
            console2.log("  desired remote:", vm.toString(entry_.evmTrustedRemote));
            if (!live.isSet || live.remoteAddress != entry_.evmTrustedRemote) {
                addToBatch(
                    address(bridge_),
                    abi.encodeWithSelector(
                        ICCIPCrossChainBridge.setTrustedRemoteEVM.selector,
                        entry_.chainSelector,
                        entry_.evmTrustedRemote
                    )
                );
                console2.log("  Added: setTrustedRemoteEVM");
                planned++;
            } else {
                console2.log("  Trusted remote matches.");
            }
        }

        // The gas limit is compared independently, so a matching remote does not mask its drift
        uint32 liveGas = bridge_.getGasLimit(entry_.chainSelector);
        console2.log("  live gas limit:", liveGas, "desired:", entry_.gasLimit);
        if (liveGas != entry_.gasLimit) {
            addToBatch(
                address(bridge_),
                abi.encodeWithSelector(
                    ICCIPCrossChainBridge.setGasLimit.selector,
                    entry_.chainSelector,
                    entry_.gasLimit
                )
            );
            console2.log("  Added: setGasLimit");
            planned++;
        } else {
            console2.log("  Gas limit matches.");
        }
    }

    function _planUnsetSvm(
        ICCIPCrossChainBridge bridge_,
        CCIPConfigLib.DesiredPeriphery memory entry_,
        bool isSet_
    ) internal returns (uint256 planned) {
        if (!isSet_) {
            console2.log("  Declared with enabled=false and not set. Nothing to do.");
            return 0;
        }
        console2.log(
            "  WARNING: unsetting the trusted remote; in-flight messages from it will be recorded as failed."
        );
        addToBatch(
            address(bridge_),
            abi.encodeWithSelector(
                ICCIPCrossChainBridge.unsetTrustedRemoteSVM.selector,
                entry_.chainSelector
            )
        );
        console2.log("  Added: unsetTrustedRemoteSVM");
        return 1;
    }

    function _planUnsetEvm(
        ICCIPCrossChainBridge bridge_,
        CCIPConfigLib.DesiredPeriphery memory entry_,
        bool isSet_
    ) internal returns (uint256 planned) {
        if (!isSet_) {
            console2.log("  Declared with enabled=false and not set. Nothing to do.");
            return 0;
        }
        console2.log(
            "  WARNING: unsetting the trusted remote; in-flight messages from it will be recorded as failed."
        );
        addToBatch(
            address(bridge_),
            abi.encodeWithSelector(
                ICCIPCrossChainBridge.unsetTrustedRemoteEVM.selector,
                entry_.chainSelector
            )
        );
        console2.log("  Added: unsetTrustedRemoteEVM");
        return 1;
    }

    // =========== REPORTING =========== //

    /// @notice Reports a live trusted remote whose route declares no `periphery` block; it is
    ///         left untouched, since removal requires the explicit marker.
    function _reportUnmanagedRemotes(
        ICCIPCrossChainBridge bridge_,
        CCIPConfigLib.DesiredPeriphery[] memory desired_
    ) internal view {
        string[] memory allChains = ChainUtils._getChains(chain);
        for (uint256 i; i < allChains.length; ++i) {
            string memory remoteChain = allChains[i];
            if (keccak256(bytes(remoteChain)) == keccak256(bytes(chain))) continue;

            bool declared;
            for (uint256 j; j < desired_.length; ++j) {
                if (keccak256(bytes(desired_[j].remoteChain)) == keccak256(bytes(remoteChain))) {
                    declared = true;
                    break;
                }
            }
            if (declared) continue;

            // A chain without a recorded selector (some testnets) cannot be looked up
            if (_envUint(remoteChain, CCIPConfigLib.CHAIN_SELECTOR_KEY) == 0) continue;
            uint64 selector = CCIPConfigLib.chainSelector(env, remoteChain);

            bool isSet = ChainUtils._isSVMChain(remoteChain)
                ? bridge_.getTrustedRemoteSVM(selector).isSet
                : bridge_.getTrustedRemoteEVM(selector).isSet;
            if (isSet) {
                console2.log(
                    "\nWARNING: the live trusted remote for",
                    remoteChain,
                    "has no periphery block in env.json and is left untouched; declare it, or declare its periphery block with enabled: false to unset it."
                );
            }
        }
    }

    /// @notice Reports a drift between the legacy `olympus.config.CCIPCrossChainBridge.chains`
    ///         list and the set of declared `periphery` blocks. The reconciler ignores the
    ///         legacy list; it remains for the direct pool owner functions of
    ///         `CCIPTokenPool.sol`.
    function _warnLegacyChainsDrift(
        CCIPConfigLib.DesiredPeriphery[] memory desired_
    ) internal view {
        string[] memory legacy = _envStringArray("olympus.config.CCIPCrossChainBridge.chains");

        bool drift = legacy.length != desired_.length;
        if (!drift) {
            for (uint256 i; i < desired_.length; ++i) {
                if (!ArrayUtils.contains(legacy, desired_[i].remoteChain)) {
                    drift = true;
                    break;
                }
            }
        }
        if (drift) {
            console2.log(
                "\nWARNING: the legacy olympus.config.CCIPCrossChainBridge.chains list differs from the set of periphery blocks; the reconciler ignores the list, but keep them in sync for the direct pool owner functions."
            );
        }
    }

    // =========== INTERNAL HELPERS =========== //

    function _bridge() internal view returns (ICCIPCrossChainBridge bridge) {
        address bridgeAddress = _envAddressNotZero(CCIPConfigLib.EVM_BRIDGE_KEY);
        _requireBridgeOwner(bridgeAddress);
        return ICCIPCrossChainBridge(bridgeAddress);
    }

    function _requireBridgeOwner(address bridgeAddress_) internal view {
        address owner = Owned(bridgeAddress_).owner();
        require(
            owner == _owner,
            string.concat(
                "CCIPBridge: the batch owner is not the owner of the periphery (",
                vm.toString(owner),
                ")"
            )
        );
    }
}
