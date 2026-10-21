// SPDX-License-Identifier: Unlicense
// solhint-disable custom-errors
pragma solidity ^0.8.24;

// Script code, run off-chain by forge: calls in loops are simulated rather than paid for
// on-chain, and a failed `require` is meant to abort the whole run with its message.
// forge-lint: disable-start(calls-loop,custom-errors,require-revert-in-loop)

import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";
import {console2} from "@forge-std-1.16.2/console2.sol";

// Interfaces
import {ICCIPLiquidityContainer} from "src/external/bridge/ICCIPLiquidityContainer.sol";
import {ICCIPLockReleaseTokenPool} from "src/external/bridge/ICCIPLockReleaseTokenPool.sol";
import {ICCIPRateLimiter} from "src/external/bridge/ICCIPRateLimiter.sol";
import {ICCIPTokenAdminRegistry} from "src/external/bridge/ICCIPTokenAdminRegistry.sol";
import {ICCIPTokenPoolAdmin} from "src/external/bridge/ICCIPTokenPoolAdmin.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

// Libraries
import {Surl} from "@surl-1.0.0/Surl.sol";
import {SafeCast} from "src/libraries/SafeCast.sol";
import {ArrayUtils} from "src/scripts/ops/lib/ArrayUtils.sol";
import {CCIPConfigLib} from "src/scripts/ops/lib/CCIPConfigLib.sol";
import {ChainUtils} from "src/scripts/ops/lib/ChainUtils.sol";

// Contracts
import {Kernel, Actions} from "src/Kernel.sol";

/// @title CCIPTokenPoolBatch
/// @notice Multisig batches that act directly on the CCIP token pool and on the OHM entry of the
///         Chainlink TokenAdminRegistry, from the pool owner or the OHM administrator.
/// @dev    These entry points act from the direct pool owner, the OHM administrator or the
///         rebalancer, which serves the bootstrap of a chain before its config policy takes the
///         pool over, and testnets. Once the pool is owned by the CCIPTokenPoolConfig policy and
///         the OHM administrator is the OCG timelock (the mainnet state after the CCIP Bridge
///         Activation proposal), none of them is available to a multisig batch: each reverts
///         with the path to use instead. Route configuration runs through `CCIPRouteReconcileBatch`
///         (config timelock), containment and re-enable through `CCIPTokenPoolConfigBatch`, and the
///         registry, the rebalancer and liquidity withdrawals through an OCG proposal.
contract CCIPTokenPoolBatch is BatchScriptV2 {
    using SafeCast for uint256;
    using Surl for string;

    // ========== STATE ========== //

    /// @notice The Solana mint supply read while planning `fundPool`, in OHM base units, for
    ///         the post-batch check, which is called by selector without arguments.
    uint256 internal _fundPoolSolanaMintSupply;

    // ========== HELPERS ========== //

    function _getTokenPoolAddressNotZero(string memory chain_) internal view returns (address) {
        return _envAddressNotZero(chain_, CCIPConfigLib.poolKey(chain_));
    }

    function _getTokenPoolAddress(string memory chain_) internal view returns (address) {
        return _envAddress(chain_, CCIPConfigLib.poolKey(chain_));
    }

    function _getTokenAdminRegistryConfig()
        internal
        view
        returns (ICCIPTokenAdminRegistry.TokenConfig memory)
    {
        address tokenRegistry = _envAddressNotZero("external.ccip.TokenAdminRegistry");
        address token = _envAddressNotZero("olympus.legacy.OHM");

        return ICCIPTokenAdminRegistry(tokenRegistry).getTokenConfig(token);
    }

    /// @notice Returns the CCIPTokenPoolConfig policy of the local chain, or the zero address when
    ///         it is not deployed.
    function _configAddress() internal view returns (address) {
        return _envAddress("olympus.policies.CCIPTokenPoolConfig");
    }

    /// @notice Returns whether the pool is owned by the CCIPTokenPoolConfig policy.
    function _isPoolOwnedByConfig(address tokenPool_) internal view returns (bool) {
        address config = _configAddress();
        return config != address(0) && ICCIPTokenPoolAdmin(tokenPool_).owner() == config;
    }

    /// @notice Reverts unless the batch owner is the pool owner, naming the path to use otherwise.
    function _requireDirectPoolOwner(address tokenPool_, string memory alternative_) internal view {
        address owner = ICCIPTokenPoolAdmin(tokenPool_).owner();
        if (owner == _owner) return;

        revert(
            string.concat(
                "CCIPTokenPoolBatch: the batch owner is not the pool owner (",
                vm.toString(owner),
                _isPoolOwnedByConfig(tokenPool_) ? ", the CCIPTokenPoolConfig policy). " : "). ",
                alternative_
            )
        );
    }

    /// @notice Reverts unless the batch owner is the OHM administrator, naming the path to use
    ///         otherwise.
    function _requireTokenAdmin(
        ICCIPTokenAdminRegistry.TokenConfig memory config_,
        string memory alternative_
    ) internal view {
        if (config_.administrator == _owner) return;

        revert(
            string.concat(
                "CCIPTokenPoolBatch: the batch owner is not the OHM administrator (",
                vm.toString(config_.administrator),
                "). ",
                alternative_
            )
        );
    }

    string internal constant _ROUTE_ALTERNATIVE =
        "Route configuration of a pool owned by CCIPTokenPoolConfig runs through CCIPRouteReconcileBatch.reconcileRoutes (config timelock) or an OCG proposal.";
    string internal constant _CONTAINMENT_ALTERNATIVE =
        "Containment of a pool owned by CCIPTokenPoolConfig runs through CCIPTokenPoolConfigBatch.disableChain or disableAllChains (the DAO MS as bridge_admin) or their EmergencyMS variants (the Emergency MS).";
    string internal constant _REGISTRY_ALTERNATIVE =
        "On mainnet the OHM administrator is the OCG timelock after the handover: registry changes are OCG proposals.";
    string internal constant _OWNERSHIP_ALTERNATIVE =
        "After the handover the pool ownership is managed through CCIPTokenPoolConfig.transferPoolOwnership by the admin role (an OCG proposal on mainnet).";

    /// @notice Default rate limiter config for a TokenPool
    /// @dev    The rate limiter is disabled by default, hence there is no rate limit
    function _getRateLimiterConfigDefault() internal pure returns (ICCIPRateLimiter.Config memory) {
        return ICCIPRateLimiter.Config({isEnabled: false, capacity: 0, rate: 0});
    }

    /// @notice Rate limiter config for emergency shutdown
    /// @dev    The rate limiter is enabled, with a very low capacity, which means the bridge is effectively disabled
    function _getRateLimiterConfigEmergencyShutdown()
        internal
        pure
        returns (ICCIPRateLimiter.Config memory)
    {
        return ICCIPRateLimiter.Config({isEnabled: true, capacity: 2, rate: 1});
    }

    // ========== INSTALLATION ========== //

    /// @notice Performs installation and initial configuration of the TokenPool
    /// @dev    On a non-canonical chain: the TokenPool is activated in the Kernel and enabled.
    ///         On a canonical chain: the TokenPool is a periphery contract and does not need
    ///         activation. While the batch owner owns the pool, the batch owner is set as the
    ///         rebalancer. Once the pool is owned by the CCIPTokenPoolConfig policy, the rebalancer
    ///         is managed through `CCIPTokenPoolConfig.setRebalancer` by the admin role and the
    ///         function adds nothing.
    function install(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        // Assumptions
        // - The token pool has been linked to OHM in the CCIP token admin registry
        // - The token pool is already configured

        // Load contract addresses from the environment file
        address kernel = _envAddressNotZero("olympus.Kernel");
        address tokenPool = _getTokenPoolAddressNotZero(chain);

        if (!ChainUtils._isCanonicalChain(chain)) {
            // Install the TokenPool policy
            // Assumes that the caller is the kernel executor
            console2.log("Non-Canonical chain: Installing TokenPool policy into Kernel");
            addToBatch(
                kernel,
                abi.encodeWithSelector(
                    Kernel.executeAction.selector,
                    Actions.ActivatePolicy,
                    tokenPool
                )
            );

            // On non-canonical chains (currently), the "admin" role (required for enabling the policy) is set to the DAO MS
            console2.log("Non-Canonical chain: Enabling TokenPool policy");
            addToBatch(tokenPool, abi.encodeWithSelector(IEnabler.enable.selector, ""));
        }
        // Canonical chain has a non-privileged LockReleaseTokenPool contract
        // It cannot facilitate any bridging operations until remote chains are configured
        else {
            console2.log("Canonical chain: No need to install TokenPool contract in Kernel");
            console2.log("Canonical chain: No need to enable TokenPool contract");

            if (_isPoolOwnedByConfig(tokenPool)) {
                console2.log(
                    "Canonical chain: the pool is owned by CCIPTokenPoolConfig; the rebalancer is managed through CCIPTokenPoolConfig.setRebalancer by the admin role (an OCG proposal on mainnet). Nothing to install."
                );
            } else {
                _requireDirectPoolOwner(tokenPool, _OWNERSHIP_ALTERNATIVE);

                // Set the owner as the rebalancer on the LockReleaseTokenPool
                // Allows for withdrawing OHM from the LockReleaseTokenPool
                addToBatch(
                    tokenPool,
                    abi.encodeWithSelector(ICCIPLockReleaseTokenPool.setRebalancer.selector, _owner)
                );
                console2.log(
                    "Canonical chain: Set the owner as the rebalancer of the LockReleaseTokenPool"
                );
            }
        }

        // Run
        proposeBatch();

        console2.log("Completed");

        // Next steps:
        // - Non-canonical chains: Governance to enable the TokenPool policy
    }

    // ========== TOKEN ADMIN REGISTRY ========== //

    /// @notice Accepts the admin role for the OHM token
    /// @dev    The batch owner must be the pending administrator. On mainnet after the handover
    ///         the administrator is the OCG timelock and registry changes are OCG proposals.
    function acceptAdminRole(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        // The batch touches only the CCIP registry, which cannot affect the heartbeat; the
        // burn/mint chains also deploy no OlympusHeart to validate against.
        _skipHeartbeatValidation = true;

        // Load contract addresses from the environment file
        address tokenRegistry = _envAddressNotZero("external.ccip.TokenAdminRegistry");
        address token = _envAddressNotZero("olympus.legacy.OHM");
        ICCIPTokenAdminRegistry.TokenConfig memory tokenConfig = _getTokenAdminRegistryConfig();

        // Check if the owner is already the administrator
        if (tokenConfig.administrator == _owner) {
            console2.log("Owner", _owner, "is already the administrator. Skipping.");
            return;
        }
        if (tokenConfig.pendingAdministrator != _owner) {
            revert(
                string.concat(
                    "CCIPTokenPoolBatch: the batch owner is not the pending OHM administrator (administrator ",
                    vm.toString(tokenConfig.administrator),
                    ", pending ",
                    vm.toString(tokenConfig.pendingAdministrator),
                    "). ",
                    _REGISTRY_ALTERNATIVE
                )
            );
        }

        // Accept the admin role
        console2.log("Accepting admin role for", token, "to", _owner);
        addToBatch(
            tokenRegistry,
            abi.encodeWithSelector(ICCIPTokenAdminRegistry.acceptAdminRole.selector, token)
        );

        // Run
        proposeBatch();

        console2.log("Completed");
    }

    /// @notice Sets the token pool for the OHM token
    /// @dev    The batch owner must be the OHM administrator. On mainnet after the handover the
    ///         administrator is the OCG timelock and registry changes are OCG proposals.
    function setPool(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        // The batch touches only the CCIP registry, which cannot affect the heartbeat; the
        // burn/mint chains also deploy no OlympusHeart to validate against.
        _skipHeartbeatValidation = true;

        // Load contract addresses from the environment file
        address tokenRegistry = _envAddressNotZero("external.ccip.TokenAdminRegistry");
        address token = _envAddressNotZero("olympus.legacy.OHM");
        address tokenPool = _getTokenPoolAddressNotZero(chain);
        ICCIPTokenAdminRegistry.TokenConfig memory tokenConfig = _getTokenAdminRegistryConfig();

        // Check if the pool is already set
        if (tokenConfig.tokenPool == tokenPool) {
            console2.log("Pool", tokenPool, "is already set. Skipping.");
            return;
        }
        _requireTokenAdmin(tokenConfig, _REGISTRY_ALTERNATIVE);

        // Set the pool
        console2.log("Setting pool for", token, "to", tokenPool);
        addToBatch(
            tokenRegistry,
            abi.encodeWithSelector(ICCIPTokenAdminRegistry.setPool.selector, token, tokenPool)
        );

        // Run
        proposeBatch();

        console2.log("Completed");
    }

    /// @notice Transfers the admin role for the OHM token to the DAO multisig
    /// @dev    The batch owner must be the OHM administrator. On mainnet after the handover the
    ///         administrator is the OCG timelock and registry changes are OCG proposals.
    function transferTokenPoolAdminRoleToDaoMS(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        // The batch touches only the CCIP registry, which cannot affect the heartbeat; the
        // burn/mint chains also deploy no OlympusHeart to validate against.
        _skipHeartbeatValidation = true;

        address tokenRegistry = _envAddressNotZero("external.ccip.TokenAdminRegistry");
        address token = _envAddressNotZero("olympus.legacy.OHM");
        address daoMS = _envAddressNotZero("olympus.multisig.dao");
        ICCIPTokenAdminRegistry.TokenConfig memory tokenConfig = _getTokenAdminRegistryConfig();

        // Check if the admin role is already transferred
        if (tokenConfig.administrator == daoMS) {
            console2.log("Admin role already transferred to", daoMS, ". Skipping.");
            return;
        }
        if (tokenConfig.pendingAdministrator == daoMS) {
            console2.log("Admin role transfer to", daoMS, "is already pending. Skipping.");
            return;
        }
        _requireTokenAdmin(tokenConfig, _REGISTRY_ALTERNATIVE);

        console2.log("Transferring admin role for", token, "to", daoMS);
        addToBatch(
            tokenRegistry,
            abi.encodeWithSelector(ICCIPTokenAdminRegistry.transferAdminRole.selector, token, daoMS)
        );

        // Run
        proposeBatch();

        console2.log("Completed");

        // Next steps:
        // - DAO MS must accept the admin role
    }

    // ========== POOL OWNERSHIP ========== //

    /// @notice Transfers the ownership of the TokenPool to the DAO multisig
    /// @dev    The batch owner must be the pool owner. After the handover the pool is owned by
    ///         CCIPTokenPoolConfig and ownership transfers go through `transferPoolOwnership`.
    function transferTokenPoolOwnershipToDaoMS(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        address tokenPool = _getTokenPoolAddressNotZero(chain);
        address daoMS = _envAddressNotZero("olympus.multisig.dao");

        // Check if the owner is already the DAO MS
        if (ICCIPTokenPoolAdmin(tokenPool).owner() == daoMS) {
            console2.log("Owner already transferred to", daoMS, ". Skipping.");
            return;
        }
        if (_pendingOwner(tokenPool) == daoMS) {
            console2.log("Ownership transfer to", daoMS, "is already pending. Skipping.");
            return;
        }
        _requireDirectPoolOwner(tokenPool, _OWNERSHIP_ALTERNATIVE);

        console2.log("Transferring ownership of", tokenPool, "to", daoMS);
        addToBatch(
            tokenPool,
            abi.encodeWithSelector(ICCIPTokenPoolAdmin.transferOwnership.selector, daoMS)
        );

        // Run
        proposeBatch();

        console2.log("Completed");

        // Next steps:
        // - DAO MS must accept the ownership
    }

    /// @notice Proposes the local CCIPTokenPoolConfig policy as the new owner of the TokenPool
    /// @dev    The batch owner must be the pool owner (the deployer, right after the deploy
    ///         sequence). The transfer is only proposed here; the config policy accepts it with
    ///         `acceptPoolOwnership` in the setup batch (non-canonical chains) or in the OCG
    ///         proposal (mainnet). Skipped when the config policy already owns or is the pending
    ///         owner of the pool.
    function transferTokenPoolOwnershipToConfig(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        // The batch touches only the CCIP pool, which cannot affect the heartbeat; the
        // burn/mint chains also deploy no OlympusHeart to validate against.
        _skipHeartbeatValidation = true;

        address tokenPool = _getTokenPoolAddressNotZero(chain);
        address config = _configAddress();
        require(
            config != address(0),
            "CCIPTokenPoolBatch: no CCIPTokenPoolConfig is recorded for this chain; deploy it first"
        );

        if (ICCIPTokenPoolAdmin(tokenPool).owner() == config) {
            console2.log("CCIPTokenPoolConfig already owns the pool. Skipping.");
            return;
        }
        if (_pendingOwner(tokenPool) == config) {
            console2.log("Ownership transfer to CCIPTokenPoolConfig is already pending. Skipping.");
            return;
        }
        _requireDirectPoolOwner(
            tokenPool,
            "Run this entry point again with the printed pool owner as the sender (the deployer after the deploy sequence)."
        );

        console2.log("Transferring ownership of", tokenPool, "to CCIPTokenPoolConfig", config);
        addToBatch(
            tokenPool,
            abi.encodeWithSelector(ICCIPTokenPoolAdmin.transferOwnership.selector, config)
        );

        // Run
        proposeBatch();

        console2.log("Completed");

        // Next steps:
        // - The setup batch (or the OCG proposal on mainnet) accepts the ownership
    }

    /// @notice Accepts the ownership of the TokenPool
    /// @dev    The batch owner must be the pending owner of the pool.
    function acceptTokenPoolOwnership(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        address tokenPool = _getTokenPoolAddressNotZero(chain);
        address daoMS = _envAddressNotZero("olympus.multisig.dao");

        // Check if the owner is already the DAO MS
        if (ICCIPTokenPoolAdmin(tokenPool).owner() == daoMS) {
            console2.log("Owner already transferred to", daoMS, ". Skipping.");
            return;
        }
        address pending = _pendingOwner(tokenPool);
        if (pending != _owner) {
            revert(
                string.concat(
                    "CCIPTokenPoolBatch: the batch owner is not the pending owner of the pool (",
                    vm.toString(pending),
                    "). ",
                    _OWNERSHIP_ALTERNATIVE
                )
            );
        }

        console2.log("Accepting ownership of", tokenPool, "to", daoMS);
        addToBatch(tokenPool, abi.encodeWithSelector(ICCIPTokenPoolAdmin.acceptOwnership.selector));

        // Run
        proposeBatch();

        console2.log("Completed");
    }

    // ========== REMOTE CHAINS (DIRECT POOL OWNER PATH) ========== //

    function _configureRemoteChainEVM(string memory remoteChain_, bool shouldReset_) internal {
        console2.log("\n");
        console2.log("Configuring remote chain", remoteChain_);

        // Validate that the chain is an EVM chain
        if (ChainUtils._isSVMChain(remoteChain_)) {
            revert("_configureRemoteChainEVM: Chain is not an EVM chain");
        }

        address tokenPoolAddress = _getTokenPoolAddress(chain);
        // If the token pool is the zero address, then there is nothing to do
        if (tokenPoolAddress == address(0)) {
            console2.log("Token pool address is the zero address. Skipping.");
            return;
        }
        _requireDirectPoolOwner(tokenPoolAddress, _ROUTE_ALTERNATIVE);

        address remotePoolAddress = _getTokenPoolAddress(remoteChain_);
        // If the remote pool is the zero address, then there is nothing to do
        if (remotePoolAddress == address(0)) {
            console2.log("Remote pool address is the zero address. Skipping.");
            return;
        }

        address remoteTokenAddress = _envAddressNotZero(remoteChain_, "olympus.legacy.OHM");
        uint64 remoteChainSelector = CCIPConfigLib.chainSelector(env, remoteChain_);
        bool isSupportedChain = ICCIPTokenPoolAdmin(tokenPoolAddress).isSupportedChain(
            remoteChainSelector
        );

        // If resetting, then it should be removed
        if (shouldReset_) {
            if (!isSupportedChain) {
                console2.log("Remote chain is not configured. Skipping.");
                return;
            }

            _addRemoveChain(tokenPoolAddress, remoteChainSelector);

            console2.log("Remote chain", remoteChain_, "removed from token pool", tokenPoolAddress);
            console2.log("\n");
            return;
        }

        // Prepare the chain update; an existing route is replaced in the same call
        bytes[] memory remotePoolAddresses = new bytes[](1);
        remotePoolAddresses[0] = CCIPConfigLib.encodeEvmAddress(remotePoolAddress);
        _addChainUpdate(
            tokenPoolAddress,
            remoteChain_,
            remoteChainSelector,
            remotePoolAddresses,
            CCIPConfigLib.encodeEvmAddress(remoteTokenAddress),
            isSupportedChain
        );
    }

    /// @notice Configures the TokenPool to add support for the specified EVM remote chain
    /// @dev    Direct pool owner path only; see the contract NatSpec. An existing route is
    ///         replaced in one `applyChainUpdates` call, a removal followed by an addition in
    ///         one transaction, which resets both buckets to the bootstrap default (disabled
    ///         limiters) as the addition of a new route does.
    ///         Reads `remoteChain` from this function's entry in the args file.
    function configureRemoteChainEVM(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        string memory remoteChain = _readBatchArgString("configureRemoteChainEVM", "remoteChain");

        // Configure the remote chain
        _configureRemoteChainEVM(remoteChain, false);

        // Run
        proposeBatch();

        console2.log("Completed");
    }

    function _configureRemoteChainSVM(string memory remoteChain_, bool shouldReset_) internal {
        console2.log("\n");
        console2.log("Configuring remote chain", remoteChain_);

        // Validate that the chain is an SVM chain
        if (!ChainUtils._isSVMChain(remoteChain_)) {
            revert("_configureRemoteChainSVM: Chain is not an SVM chain");
        }

        address tokenPoolAddress = _getTokenPoolAddress(chain);
        // If the local pool is the zero address, then there is nothing to do
        if (tokenPoolAddress == address(0)) {
            console2.log("Token pool address is the zero address. Skipping.");
            return;
        }
        _requireDirectPoolOwner(tokenPoolAddress, _ROUTE_ALTERNATIVE);

        string memory remotePoolKey = _envString(remoteChain_, CCIPConfigLib.SVM_POOL_KEY);
        // If the remote pool is not set, then there is nothing to do
        if (bytes(remotePoolKey).length == 0) {
            console2.log("Remote pool address is not set. Skipping.");
            return;
        }

        uint64 remoteChainSelector = CCIPConfigLib.chainSelector(env, remoteChain_);
        bool isSupportedChain = ICCIPTokenPoolAdmin(tokenPoolAddress).isSupportedChain(
            remoteChainSelector
        );

        // If resetting, then it should be removed
        if (shouldReset_) {
            if (!isSupportedChain) {
                console2.log("Remote chain is not configured. Skipping.");
                return;
            }

            _addRemoveChain(tokenPoolAddress, remoteChainSelector);

            console2.log("Remote chain", remoteChain_, "removed from token pool", tokenPoolAddress);
            console2.log("\n");
            return;
        }

        // Prepare the chain update; an existing route is replaced in the same call
        bytes[] memory remotePoolAddresses = new bytes[](1);
        remotePoolAddresses[0] = CCIPConfigLib.defaultRemotePool(env, remoteChain_);
        _addChainUpdate(
            tokenPoolAddress,
            remoteChain_,
            remoteChainSelector,
            remotePoolAddresses,
            CCIPConfigLib.defaultRemoteToken(env, remoteChain_),
            isSupportedChain
        );
    }

    /// @notice Configures the TokenPool to add support for the specified SVM remote chain
    /// @dev    Direct pool owner path only; see the contract NatSpec. An existing route is
    ///         replaced in one `applyChainUpdates` call, a removal followed by an addition in
    ///         one transaction, which resets both buckets to the bootstrap default (disabled
    ///         limiters) as the addition of a new route does.
    ///         Reads `remoteChain` from this function's entry in the args file.
    function configureRemoteChainSVM(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        string memory remoteChain = _readBatchArgString("configureRemoteChainSVM", "remoteChain");

        // Configure the remote chain
        _configureRemoteChainSVM(remoteChain, false);

        // Run
        proposeBatch();

        console2.log("Completed");
    }

    function _configureRemoteChains(string memory chain_) internal {
        console2.log("\n");
        console2.log("Configuring all remote chains for", chain_);

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
                _configureRemoteChainSVM(remoteChain, !isTrustedChain);
            } else {
                _configureRemoteChainEVM(remoteChain, !isTrustedChain);
            }
        }
    }

    /// @notice Configures the TokenPool to add support for all remote chains
    /// @dev    Direct pool owner path only; see the contract NatSpec. A chain listed in
    ///         `olympus.config.CCIPCrossChainBridge.chains` is added or, when its route exists,
    ///         replaced in one `applyChainUpdates` call with the bootstrap default limiters; a
    ///         chain outside the list is removed when its route exists.
    function configureAllRemoteChains(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        // Configure the remote chains
        _configureRemoteChains(chain);

        // Run
        proposeBatch();
    }

    function _addRemoveChain(address tokenPool_, uint64 remoteChainSelector_) internal {
        uint64[] memory remoteChainSelectors = new uint64[](1);
        remoteChainSelectors[0] = remoteChainSelector_;

        addToBatch(
            tokenPool_,
            abi.encodeWithSelector(
                ICCIPTokenPoolAdmin.applyChainUpdates.selector,
                remoteChainSelectors,
                new ICCIPTokenPoolAdmin.ChainUpdate[](0)
            )
        );
    }

    /// @notice Adds one `applyChainUpdates` call that adds the route or, when `replace_` is
    ///         true, replaces it in the same call: the pool removes the selectors to remove
    ///         before it adds the updates, so the replacement is a removal followed by an
    ///         addition in one transaction. Both buckets of the added route carry the bootstrap
    ///         default, a disabled limiter.
    function _addChainUpdate(
        address tokenPool_,
        string memory remoteChain_,
        uint64 remoteChainSelector_,
        bytes[] memory remotePoolAddresses_,
        bytes memory remoteTokenAddress_,
        bool replace_
    ) internal {
        uint64[] memory remoteChainSelectorsToRemove = new uint64[](replace_ ? 1 : 0);
        if (replace_) remoteChainSelectorsToRemove[0] = remoteChainSelector_;

        ICCIPTokenPoolAdmin.ChainUpdate[]
            memory chainUpdates = new ICCIPTokenPoolAdmin.ChainUpdate[](1);
        chainUpdates[0] = ICCIPTokenPoolAdmin.ChainUpdate({
            remoteChainSelector: remoteChainSelector_,
            remotePoolAddresses: remotePoolAddresses_,
            remoteTokenAddress: remoteTokenAddress_,
            outboundRateLimiterConfig: _getRateLimiterConfigDefault(),
            inboundRateLimiterConfig: _getRateLimiterConfigDefault()
        });

        // Apply the chain update
        console2.log(
            replace_ ? "Replacing the route of" : "Adding the route of",
            remoteChain_,
            "on token pool",
            tokenPool_
        );
        addToBatch(
            tokenPool_,
            abi.encodeWithSelector(
                ICCIPTokenPoolAdmin.applyChainUpdates.selector,
                remoteChainSelectorsToRemove,
                chainUpdates
            )
        );
    }

    // ===== RATE LIMITS (DIRECT POOL OWNER PATH) ===== //

    function _readRateLimiterConfig(
        string memory functionName_,
        string memory argPrefix_
    ) internal view returns (ICCIPRateLimiter.Config memory) {
        // capacity and rate are OHM local token units with 9 decimals, matching the CCIP OHM token decimals.
        return
            ICCIPRateLimiter.Config({
                isEnabled: _readBatchArgBool(
                    functionName_,
                    string.concat(argPrefix_, ".isEnabled")
                ),
                capacity: _readBatchArgUint256(
                    functionName_,
                    string.concat(argPrefix_, ".capacity")
                ).encodeUInt128(),
                rate: _readBatchArgUint256(functionName_, string.concat(argPrefix_, ".rate"))
                    .encodeUInt128()
            });
    }

    function _logRateLimiterConfig(
        string memory label_,
        ICCIPRateLimiter.Config memory config_
    ) internal pure {
        console2.log(label_);
        console2.log("  Enabled:", config_.isEnabled);
        console2.log("  Capacity:", config_.capacity);
        console2.log("  Rate:", config_.rate);
    }

    /// @notice Sets the outbound and inbound TokenPool rate limits for a remote chain
    /// @dev    Direct pool owner path only: once the pool is owned by CCIPTokenPoolConfig the
    ///         desired limits live in `env.json` and `CCIPRouteReconcileBatch.reconcileRoutes`
    ///         queues them on the config timelock.
    ///         The local chain is determined from block.chainid. `capacity` is the max bucket size and `rate` is the
    ///         bucket refill per second. Both fields are denominated in OHM local token units with 9 decimals.
    ///         Args file format:
    ///         {
    ///           "functions": [{
    ///             "name": "setRateLimits",
    ///             "args": {
    ///               "localChain": "mainnet",
    ///               "remoteChain": "base",
    ///               "outboundRateLimiterConfig": {"isEnabled": true, "capacity": "100000000000", "rate": "100000000"},
    ///               "inboundRateLimiterConfig": {"isEnabled": true, "capacity": "100000000000", "rate": "100000000"}
    ///             }
    ///           }]
    ///         }
    function setRateLimits(
        bool useDaoMS_,
        string calldata argsFilePath_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFilePath_, ledgerDerivationPath_) {
        string memory localChain = _readBatchArgString("setRateLimits", "localChain");
        if (keccak256(abi.encodePacked(localChain)) != keccak256(abi.encodePacked(chain))) {
            revert("Local chain arg does not match the execution chain");
        }
        _skipHeartbeatValidation = true;

        string memory remoteChain = _readBatchArgString("setRateLimits", "remoteChain");
        uint64 remoteChainSelector = CCIPConfigLib.chainSelector(env, remoteChain);
        address tokenPoolAddress = _getTokenPoolAddressNotZero(chain);
        _requireDirectPoolOwner(tokenPoolAddress, _ROUTE_ALTERNATIVE);

        if (!ICCIPTokenPoolAdmin(tokenPoolAddress).isSupportedChain(remoteChainSelector)) {
            revert("Remote chain is not configured on the TokenPool");
        }

        ICCIPRateLimiter.Config memory outboundRateLimiterConfig = _readRateLimiterConfig(
            "setRateLimits",
            "outboundRateLimiterConfig"
        );
        ICCIPRateLimiter.Config memory inboundRateLimiterConfig = _readRateLimiterConfig(
            "setRateLimits",
            "inboundRateLimiterConfig"
        );

        console2.log("Setting rate limits for chain combo");
        console2.log("  Local chain:", chain);
        console2.log("  Remote chain:", remoteChain);
        console2.log("  Remote chain selector:", remoteChainSelector);
        console2.log("  Token pool:", tokenPoolAddress);
        _logRateLimiterConfig("Outbound rate limiter config", outboundRateLimiterConfig);
        _logRateLimiterConfig("Inbound rate limiter config", inboundRateLimiterConfig);

        addToBatch(
            tokenPoolAddress,
            abi.encodeWithSelector(
                ICCIPTokenPoolAdmin.setChainRateLimiterConfig.selector,
                remoteChainSelector,
                outboundRateLimiterConfig,
                inboundRateLimiterConfig
            )
        );

        // Run
        proposeBatch();

        console2.log("Completed");
    }

    // ===== EMERGENCY SHUTDOWN (DIRECT POOL OWNER PATH) ===== //

    function _emergencyShutdown(uint64 remoteChainSelector_) internal {
        address tokenPoolAddress = _getTokenPoolAddressNotZero(chain);
        _requireDirectPoolOwner(tokenPoolAddress, _CONTAINMENT_ALTERNATIVE);

        // Set the rate limiter config to emergency shutdown
        console2.log(
            "Setting rate limiter config to emergency shutdown for remote chain selector",
            remoteChainSelector_,
            "and token pool",
            tokenPoolAddress
        );
        addToBatch(
            tokenPoolAddress,
            abi.encodeWithSelector(
                ICCIPTokenPoolAdmin.setChainRateLimiterConfig.selector,
                remoteChainSelector_,
                _getRateLimiterConfigEmergencyShutdown(),
                _getRateLimiterConfigEmergencyShutdown()
            )
        );
    }

    /// @notice Performs an emergency shutdown of the TokenPool for a specific remote chain by enabling the rate limiter with a very low capacity
    /// @dev    Direct pool owner path only: once the pool is owned by CCIPTokenPoolConfig, use
    ///         `CCIPTokenPoolConfigBatch.disableChain` (the DAO MS as `bridge_admin`) or
    ///         `disableChainEmergencyMS` (the Emergency MS).
    ///         To restore the approved limits, use `setRateLimits` while the pool has a direct
    ///         owner, or `CCIPRouteReconcileBatch.reconcileRoutes` with the route named in its
    ///         `restoreContained` args after the handover; `configureRemoteChainEVM` and
    ///         `configureRemoteChainSVM` replace the route with disabled limiters instead.
    ///         Reads `remoteChain` from this function's entry in the args file.
    function emergencyShutdown(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        string memory remoteChain = _readBatchArgString("emergencyShutdown", "remoteChain");
        uint64 remoteChainSelector = CCIPConfigLib.chainSelector(env, remoteChain);

        _emergencyShutdown(remoteChainSelector);

        // Run
        proposeBatch();

        console2.log("Completed");
    }

    /// @notice Performs an emergency shutdown of the TokenPool for all remote chains by enabling the rate limiter with a very low capacity
    /// @dev    Direct pool owner path only: once the pool is owned by CCIPTokenPoolConfig, use
    ///         `CCIPTokenPoolConfigBatch.disableAllChains` (the DAO MS as `bridge_admin`) or
    ///         `disableAllChainsEmergencyMS` (the Emergency MS).
    ///         To restore the approved limits, use `setRateLimits` per route while the pool has
    ///         a direct owner, or `CCIPRouteReconcileBatch.reconcileRoutes` with every route
    ///         named in its `restoreContained` args after the handover; `configureRemoteChainEVM`
    ///         and `configureRemoteChainSVM` replace a route with disabled limiters instead.
    function emergencyShutdownAll(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        // Determine the remote chains that are configured
        uint64[] memory remoteChainSelectors = ICCIPTokenPoolAdmin(
            _getTokenPoolAddressNotZero(chain)
        ).getSupportedChains();

        for (uint256 i = 0; i < remoteChainSelectors.length; i++) {
            _emergencyShutdown(remoteChainSelectors[i]);
        }

        // Run
        proposeBatch();

        console2.log("Completed");
    }

    // ===== FUNDING (DAO MS PATH) ===== //

    /// @notice Reads the supply of the Solana OHM mint declared in `env.json`
    ///         (`current.solana.olympus.legacy.OHM`), in OHM base units, with a `getTokenSupply`
    ///         call to the JSON-RPC endpoint behind the `solana` alias of `foundry.toml`.
    /// @dev    The supply enters the free-liquidity comparison of `fundPool`, where a zero or
    ///         understated value would count the OHM locked for Solana as free, so every failure
    ///         reverts: a failed request, a status other than 200, a response without a token
    ///         supply, decimals other than 9 (the supply is compared with the pool balance in
    ///         OHM base units, 9 decimals) or an amount that is not a decimal number.
    function _readSolanaMintSupply() internal returns (uint256 supply) {
        string memory mintKey = ".current.solana.olympus.legacy.OHM";
        require(
            vm.keyExistsJson(env, mintKey),
            "CCIPTokenPoolBatch: missing env.json key current.solana.olympus.legacy.OHM"
        );
        string memory mint = vm.parseJsonString(env, mintKey);

        string[] memory headers = new string[](1);
        headers[0] = "Content-Type: application/json";
        // The body carries no single quote: Surl single-quotes it inside `bash -c`
        string memory body = string.concat(
            '{"jsonrpc":"2.0","id":1,"method":"getTokenSupply","params":["',
            mint,
            '"]}'
        );
        (uint256 status, bytes memory data) = vm.rpcUrl("solana").post(headers, body);
        require(
            status == 200,
            string.concat(
                "CCIPTokenPoolBatch: the Solana RPC answered getTokenSupply with HTTP status ",
                vm.toString(status)
            )
        );

        string memory response = string(data);
        require(
            vm.keyExistsJson(response, ".result.value.amount") &&
                vm.keyExistsJson(response, ".result.value.decimals"),
            string.concat("CCIPTokenPoolBatch: the Solana RPC returned no token supply: ", response)
        );
        uint256 decimals = vm.parseJsonUint(response, ".result.value.decimals");
        require(
            decimals == 9,
            string.concat(
                "CCIPTokenPoolBatch: the Solana OHM mint reports ",
                vm.toString(decimals),
                " decimals, not 9"
            )
        );
        bytes memory amount = bytes(vm.parseJsonString(response, ".result.value.amount"));
        require(amount.length != 0, "CCIPTokenPoolBatch: the Solana mint supply is empty");
        for (uint256 i = 0; i < amount.length; i++) {
            require(
                amount[i] >= 0x30 && amount[i] <= 0x39,
                string.concat(
                    "CCIPTokenPoolBatch: the Solana mint supply is not a decimal number: ",
                    string(amount)
                )
            );
        }
        supply = vm.parseUint(string(amount));
    }

    /// @notice Funds the canonical lock/release pool with the OHM amount read from the args
    ///         file: the minimum backing declared in `env.json`
    ///         (`olympus.config.CCIP.minimumPoolBacking`, the OHM supply outstanding on the
    ///         burn/mint chains that the pool must be able to release) minus the unclaimable
    ///         balance of the pool (`olympus.config.CCIP.poolUnclaimableBalance`, OHM locked
    ///         against burns on Solana outside CCIP that nothing will release).
    /// @dev    The pool balance also holds the OHM locked for Solana, which the Solana mint
    ///         supply measures and a release toward Ethereum withdraws, so the backing the pool
    ///         offers the burn/mint chains is its free liquidity, the balance minus that supply.
    ///         The batch reads the supply from the Solana RPC behind the `solana` alias of
    ///         `foundry.toml` while planning (a failed or malformed read fails the build) and
    ///         proposes nothing when the free liquidity already covers the minimum backing.
    ///         Otherwise it requires the amount of the args file to equal the minimum backing
    ///         minus the unclaimable balance, the figure `shell/calc_bridged_supply.sh` prints,
    ///         which depends neither on the pool balance nor on the Solana supply, so a
    ///         transfer in flight cannot understate it: on a pool whose balance minus the Solana
    ///         supply is the unclaimable balance, the free liquidity after the transfer is the
    ///         minimum backing exactly. The amount is the whole minimum backing net of the
    ///         unclaimable balance whatever the pool holds, so a pool whose free liquidity is
    ///         short by less (after a rebalancer withdrawal) is over-funded by the difference.
    ///         The transfer is a plain `OHM.transfer` from the batch owner; the pool keeps no
    ///         internal liquidity accounting and reads `balanceOf`, so no rebalancer role is
    ///         needed to deposit. The post-batch check requires, against the simulated state,
    ///         the free liquidity after the transfer (with the supply read while planning) and
    ///         the raw balance (the floor the proposal build and the checker compare on chain)
    ///         at or above the minimum backing; a balance that falls between the build and the
    ///         execution (a rebalancer withdrawal) is not reported here: a fall below the
    ///         minimum backing surfaces as `BackingTooLow` of the proposal build, a smaller one
    ///         (within the Solana mint supply) leaves the raw balance at the floor and is caught
    ///         only by a new run of the script or of this batch. Build the batch immediately
    ///         before signing.
    ///         Not tracked: a further burn on Solana outside CCIP, or OHM sent to the pool
    ///         directly, is not reflected in the unclaimable balance of `env.json` and settles
    ///         as surplus in the pool. Transfers in flight (a lock not yet minted on Solana, a
    ///         burn not yet released on Ethereum), which anyone can create, overstate the free
    ///         liquidity the early return reads by the amount in flight, so a pool left short by
    ///         less than that amount (after a rebalancer withdrawal) is reported as covered
    ///         until they settle; the amount itself reads neither the balance nor the supply.
    ///         Args file format (`amount` in OHM base units, 9 decimals; on 2026-10-14 the
    ///         minimum backing 130721000000000 minus the unclaimable balance 214163189):
    ///         {
    ///           "functions": [{
    ///             "name": "fundPool",
    ///             "args": {"amount": "130720785836811"}
    ///           }]
    ///         }
    ///
    ///         Reverts if:
    ///         - The chain is not canonical (burn/mint pools hold no backing).
    ///         - `env.json` lacks `olympus.config.CCIP.minimumPoolBacking` or
    ///           `olympus.config.CCIP.poolUnclaimableBalance` of the chain, or the minimum
    ///           backing is zero.
    ///         - `env.json` lacks `current.solana.olympus.legacy.OHM`, the Solana mint.
    ///         - The unclaimable balance is at or above the minimum backing.
    ///         - The Solana RPC request fails, answers with a status other than 200, without a
    ///           token supply, with decimals other than 9 or with an amount that is not a
    ///           decimal number.
    ///         - The free liquidity is below the minimum backing and the args file does not
    ///           carry `fundPool.amount`.
    ///         - The free liquidity is below the minimum backing and the amount is not the
    ///           minimum backing minus the unclaimable balance.
    ///         - The free liquidity is below the minimum backing and the batch owner's OHM
    ///           balance does not cover the amount.
    ///         - The pool balance after the transfer, or the free liquidity after it, is below
    ///           the minimum backing (the post-batch check).
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    /// @param argsFile_ Path to the arguments file.
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    function fundPool(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        // The batch touches only the OHM balance of the pool
        _skipHeartbeatValidation = true;
        require(
            ChainUtils._isCanonicalChain(chain),
            "CCIPTokenPoolBatch: funding applies to the canonical lock/release pool only"
        );

        address ohm = _envAddressNotZero("olympus.legacy.OHM");
        address tokenPool = _getTokenPoolAddressNotZero(chain);
        uint256 minimumBacking = CCIPConfigLib.minimumPoolBacking(env, chain);
        uint256 unclaimable = CCIPConfigLib.poolUnclaimableBalance(env, chain);
        require(
            unclaimable < minimumBacking,
            string.concat(
                "CCIPTokenPoolBatch: the unclaimable balance ",
                vm.toString(unclaimable),
                " is not below the minimum backing ",
                vm.toString(minimumBacking)
            )
        );
        uint256 poolBalance = IERC20(ohm).balanceOf(tokenPool);
        uint256 solanaSupply = _readSolanaMintSupply();
        _fundPoolSolanaMintSupply = solanaSupply;
        // The free liquidity is the balance minus the OHM locked for Solana; a pool that holds
        // less than the Solana supply has none
        uint256 freeLiquidity = poolBalance > solanaSupply ? poolBalance - solanaSupply : 0;

        console2.log("\n=== Fund the CCIP lock/release pool ===");
        console2.log("Pool:", tokenPool);
        console2.log("Minimum backing (env.json):", minimumBacking);
        console2.log("Unclaimable balance (env.json):", unclaimable);
        console2.log("Solana mint supply (Solana RPC):", solanaSupply);
        console2.log("Pool balance before:", poolBalance);
        console2.log("Free liquidity before (balance minus Solana supply):", freeLiquidity);
        if (poolBalance < solanaSupply) {
            console2.log(
                "The pool holds less than the Solana mint supply by",
                solanaSupply - poolBalance
            );
        }

        if (freeLiquidity >= minimumBacking) {
            console2.log(
                "The free liquidity of the pool already covers the minimum backing. Nothing to do."
            );
        } else {
            uint256 amount = _readBatchArgUint256("fundPool", "amount");
            uint256 expectedAmount = minimumBacking - unclaimable;
            require(
                amount == expectedAmount,
                string.concat(
                    "CCIPTokenPoolBatch: the funding amount ",
                    vm.toString(amount),
                    " is not the minimum backing minus the unclaimable balance, ",
                    vm.toString(expectedAmount)
                )
            );
            uint256 ownerBalance = IERC20(ohm).balanceOf(_owner);
            require(
                ownerBalance >= amount,
                string.concat(
                    "CCIPTokenPoolBatch: the batch owner holds ",
                    vm.toString(ownerBalance),
                    " OHM, below the funding amount ",
                    vm.toString(amount)
                )
            );
            uint256 balanceAfter = poolBalance + amount;
            console2.log("Amount (args file, minimum backing minus unclaimable balance):", amount);
            console2.log("Pool balance after:", balanceAfter);
            console2.log(
                "Free liquidity after:",
                balanceAfter > solanaSupply ? balanceAfter - solanaSupply : 0
            );
            addToBatch(ohm, abi.encodeWithSelector(IERC20.transfer.selector, tokenPool, amount));
            console2.log("Added: OHM.transfer(pool,", amount, ")");
        }

        _setPostBatchValidateSelector(this._validateFunded.selector);

        // Run
        proposeBatch();

        console2.log("Completed");
    }

    /// @notice Validates the state after `fundPool` against the simulated state of the batch:
    ///         the pool balance must be at or above the minimum backing (the floor the proposal
    ///         build and the checker compare on chain), and so must the free liquidity, the
    ///         balance minus the Solana mint supply read while planning.
    function _validateFunded() external view {
        address ohm = _envAddressNotZero("olympus.legacy.OHM");
        address tokenPool = _getTokenPoolAddressNotZero(chain);
        uint256 minimumBacking = CCIPConfigLib.minimumPoolBacking(env, chain);
        uint256 solanaSupply = _fundPoolSolanaMintSupply;
        uint256 poolBalance = IERC20(ohm).balanceOf(tokenPool);
        require(
            poolBalance >= minimumBacking,
            string.concat(
                "The pool balance ",
                vm.toString(poolBalance),
                " is below the minimum backing ",
                vm.toString(minimumBacking)
            )
        );
        require(
            poolBalance >= solanaSupply && poolBalance - solanaSupply >= minimumBacking,
            string.concat(
                "The free liquidity of the pool (balance ",
                vm.toString(poolBalance),
                " minus the Solana mint supply ",
                vm.toString(solanaSupply),
                ") is below the minimum backing ",
                vm.toString(minimumBacking)
            )
        );
        uint256 freeLiquidity = poolBalance - solanaSupply;
        console2.log("The pool holds the minimum backing:", poolBalance);
        console2.log("The free liquidity of the pool covers the minimum backing:", freeLiquidity);
        if (freeLiquidity > minimumBacking) {
            console2.log(
                "The free liquidity exceeds the minimum backing by",
                freeLiquidity - minimumBacking,
                "(transfers in flight, OHM burned on Solana outside CCIP or sent to the pool directly, or a pool whose free liquidity was short by less than the amount)"
            );
        }
    }

    // ===== LIQUIDITY (REBALANCER PATH) ===== //

    function _withdrawLiquidity(uint256 liquidity_) internal {
        // Validate that the chain is canonical
        if (!ChainUtils._isCanonicalChain(chain)) {
            revert(
                "Withdrawing liquidity is only supported on the LockReleaseTokenPool on canonical chains"
            );
        }

        address tokenPoolAddress = _getTokenPoolAddressNotZero(chain);

        // `withdrawLiquidity` is gated on the rebalancer, not the owner
        address rebalancer = ICCIPLockReleaseTokenPool(tokenPoolAddress).getRebalancer();
        if (rebalancer != _owner) {
            revert(
                string.concat(
                    "CCIPTokenPoolBatch: the batch owner is not the rebalancer of the pool (",
                    vm.toString(rebalancer),
                    "). On mainnet the rebalancer is the OCG timelock after the handover, so liquidity withdrawals are OCG proposals."
                )
            );
        }

        // Withdraw liquidity
        console2.log(
            "Withdrawing liquidity of",
            liquidity_,
            "OHM from token pool",
            tokenPoolAddress
        );
        addToBatch(
            tokenPoolAddress,
            abi.encodeWithSelector(ICCIPLiquidityContainer.withdrawLiquidity.selector, liquidity_)
        );
    }

    /// @notice Withdraws the total balance of OHM from a LockReleaseTokenPool
    /// @dev    This function can only be called on canonical chains, by the rebalancer
    function withdrawAllLiquidity(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        // The pool keeps no internal accounting: its liquidity is its OHM balance
        address ohm = _envAddressNotZero("olympus.legacy.OHM");
        uint256 liquidity = IERC20(ohm).balanceOf(_getTokenPoolAddressNotZero(chain));
        if (liquidity == 0) {
            console2.log("The pool holds no OHM. Nothing to withdraw.");
            return;
        }

        // Withdraw liquidity
        _withdrawLiquidity(liquidity);

        // Run
        proposeBatch();

        console2.log("Completed");
    }

    /// @notice Withdraws a specific amount of OHM from a LockReleaseTokenPool
    /// @dev    This function can only be called on canonical chains, by the rebalancer
    ///         Reads `amount` in OHM base units (9 decimals) from this function's args entry.
    function withdrawLiquidity(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        uint256 amount = _readBatchArgUint256("withdrawLiquidity", "amount");

        // Withdraw liquidity
        _withdrawLiquidity(amount);

        // Run
        proposeBatch();

        console2.log("Completed");
    }

    // ===== INTERNAL HELPERS ===== //

    function _pendingOwner(address tokenPool_) internal view returns (address pending) {
        return CCIPConfigLib.pendingOwner(tokenPool_);
    }
}

// forge-lint: disable-end(calls-loop,custom-errors,require-revert-in-loop)
