// SPDX-License-Identifier: Unlicensed
// solhint-disable custom-errors
pragma solidity ^0.8.24;

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
import {SafeCast} from "src/libraries/SafeCast.sol";
import {ArrayUtils} from "src/scripts/ops/lib/ArrayUtils.sol";
import {CCIPConfigLib} from "src/scripts/ops/lib/CCIPConfigLib.sol";
import {ChainUtils} from "src/scripts/ops/lib/ChainUtils.sol";

// Contracts
import {Kernel, Actions} from "src/Kernel.sol";

/// @title CCIPTokenPool
/// @notice Multisig batches that act directly on the CCIP token pool and on the OHM entry of the
///         Chainlink TokenAdminRegistry, from the pool owner or the OHM administrator.
/// @dev    These entry points act from the direct pool owner, the OHM administrator or the
///         rebalancer, which serves the bootstrap of a chain before its config policy takes the
///         pool over, and testnets. Once the pool is owned by the CCIPTokenPoolConfig policy and
///         the OHM administrator is the OCG timelock (the mainnet state after the CCIP Token Pool
///         Config Activation proposal), none of them is available to a multisig batch: each reverts
///         with the path to use instead. Route configuration runs through `CCIPRouteReconcileBatch`
///         (config timelock), containment and re-enable through `CCIPTokenPoolConfigBatch`, and the
///         registry, the rebalancer and liquidity withdrawals through an OCG proposal.
contract CCIPTokenPool is BatchScriptV2 {
    using SafeCast for uint256;

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
                "CCIPTokenPool: the batch owner is not the pool owner (",
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
                "CCIPTokenPool: the batch owner is not the OHM administrator (",
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
    function install(bool useDaoMS_) external setUpWithChainId(useDaoMS_) {
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
    function acceptAdminRole(bool useDaoMS_) external setUpWithChainId(useDaoMS_) {
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
                    "CCIPTokenPool: the batch owner is not the pending OHM administrator (administrator ",
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
    function setPool(bool useDaoMS_) external setUpWithChainId(useDaoMS_) {
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
    function transferTokenPoolAdminRoleToDaoMS() external setUpWithChainId(false) {
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
    function transferTokenPoolOwnershipToDaoMS() external setUpWithChainId(false) {
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
    function transferTokenPoolOwnershipToConfig() external setUpWithChainId(false) {
        // The batch touches only the CCIP pool, which cannot affect the heartbeat; the
        // burn/mint chains also deploy no OlympusHeart to validate against.
        _skipHeartbeatValidation = true;

        address tokenPool = _getTokenPoolAddressNotZero(chain);
        address config = _configAddress();
        require(
            config != address(0),
            "CCIPTokenPool: no CCIPTokenPoolConfig is recorded for this chain; deploy it first"
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
    function acceptTokenPoolOwnership() external setUpWithChainId(false) {
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
                    "CCIPTokenPool: the batch owner is not the pending owner of the pool (",
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

        // If the remote chain is already configured, then remove it first
        if (isSupportedChain) {
            console2.log(
                "Removing remote chain",
                remoteChain_,
                "from token pool",
                tokenPoolAddress
            );
            _addRemoveChain(tokenPoolAddress, remoteChainSelector);
        }

        // Prepare the chain update
        bytes[] memory remotePoolAddresses = new bytes[](1);
        remotePoolAddresses[0] = CCIPConfigLib.encodeEvmAddress(remotePoolAddress);
        _addAddChain(
            tokenPoolAddress,
            remoteChain_,
            remoteChainSelector,
            remotePoolAddresses,
            CCIPConfigLib.encodeEvmAddress(remoteTokenAddress)
        );
    }

    /// @notice Configures the TokenPool to add support for the specified EVM remote chain
    /// @dev    Direct pool owner path only; see the contract NatSpec.
    function configureRemoteChainEVM(
        bool useDaoMS_,
        string calldata remoteChain_
    ) external setUpWithChainId(useDaoMS_) {
        // Configure the remote chain
        _configureRemoteChainEVM(remoteChain_, false);

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

        // If the remote chain is already configured, then remove it first
        if (isSupportedChain) {
            console2.log(
                "Removing remote chain",
                remoteChain_,
                "from token pool",
                tokenPoolAddress
            );
            _addRemoveChain(tokenPoolAddress, remoteChainSelector);
        }

        // Prepare the chain update
        bytes[] memory remotePoolAddresses = new bytes[](1);
        remotePoolAddresses[0] = CCIPConfigLib.defaultRemotePool(env, remoteChain_);
        _addAddChain(
            tokenPoolAddress,
            remoteChain_,
            remoteChainSelector,
            remotePoolAddresses,
            CCIPConfigLib.defaultRemoteToken(env, remoteChain_)
        );
    }

    /// @notice Configures the TokenPool to add support for the specified SVM remote chain
    /// @dev    Direct pool owner path only; see the contract NatSpec.
    function configureRemoteChainSVM(
        bool useDaoMS_,
        string calldata remoteChain_
    ) external setUpWithChainId(useDaoMS_) {
        // Configure the remote chain
        _configureRemoteChainSVM(remoteChain_, false);

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
    /// @dev    Direct pool owner path only; see the contract NatSpec.
    ///         This function skips the function call if the remote chain is already configured
    ///         This function removes the remote chain if the chain is not in the trusted chains listed in the config
    function configureAllRemoteChains(bool useDaoMS_) external setUpWithChainId(useDaoMS_) {
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

    function _addAddChain(
        address tokenPool_,
        string memory remoteChain_,
        uint64 remoteChainSelector_,
        bytes[] memory remotePoolAddresses_,
        bytes memory remoteTokenAddress_
    ) internal {
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
        console2.log("Applying chain update for", remoteChain_, "to token pool", tokenPool_);
        addToBatch(
            tokenPool_,
            abi.encodeWithSelector(
                ICCIPTokenPoolAdmin.applyChainUpdates.selector,
                new uint64[](0),
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
        bool signOnly_,
        string calldata argsFilePath_,
        string calldata ledgerDerivationPath_,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFilePath_, ledgerDerivationPath_, signature_) {
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
    ///         To restore the token pool functionality, the `configureRemoteChainEVM` or `configureRemoteChainSVM` functions can be used.
    function emergencyShutdown(
        bool useDaoMS_,
        string calldata remoteChain_
    ) external setUpWithChainId(useDaoMS_) {
        uint64 remoteChainSelector = CCIPConfigLib.chainSelector(env, remoteChain_);

        _emergencyShutdown(remoteChainSelector);

        // Run
        proposeBatch();

        console2.log("Completed");
    }

    /// @notice Performs an emergency shutdown of the TokenPool for all remote chains by enabling the rate limiter with a very low capacity
    /// @dev    Direct pool owner path only: once the pool is owned by CCIPTokenPoolConfig, use
    ///         `CCIPTokenPoolConfigBatch.disableAllChains` (the DAO MS as `bridge_admin`) or
    ///         `disableAllChainsEmergencyMS` (the Emergency MS).
    ///         To restore the token pool functionality, the `configureRemoteChainEVM` or `configureRemoteChainSVM` functions can be used.
    function emergencyShutdownAll(bool useDaoMS_) external setUpWithChainId(useDaoMS_) {
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

    /// @notice Funds the canonical lock/release pool up to the minimum backing declared in
    ///         `env.json` (`olympus.config.CCIP.minimumPoolBacking`): the OHM supply outstanding
    ///         on the burn/mint chains that the pool must be able to release.
    /// @dev    The shortfall is computed from the live pool balance at simulation time, so the
    ///         batch is idempotent by construction: a second run on a funded pool proposes
    ///         nothing. The transfer is a plain `OHM.transfer` from the batch owner; the pool
    ///         keeps no internal liquidity accounting and reads `balanceOf`, so no rebalancer
    ///         role is needed to deposit. Re-read `shell/calc_bridged_supply.sh` and update the
    ///         `env.json` target immediately before running this.
    ///
    ///         Reverts if:
    ///         - The args file is not empty.
    ///         - The chain is not canonical (burn/mint pools hold no backing).
    ///         - The batch owner's OHM balance does not cover the shortfall.
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    /// @param signOnly_ Whether to only sign the batch without proposing/executing it.
    /// @param argsFile_ Path to the arguments file (unused, must be empty).
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    /// @param signature_ Optional pre-computed signature for the batch.
    function fundPool(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath_, signature_) {
        _validateArgsFileEmpty(argsFile_);
        // The batch touches only the OHM balance of the pool
        _skipHeartbeatValidation = true;
        require(
            ChainUtils._isCanonicalChain(chain),
            "CCIPTokenPool: funding applies to the canonical lock/release pool only"
        );

        address ohm = _envAddressNotZero("olympus.legacy.OHM");
        address tokenPool = _getTokenPoolAddressNotZero(chain);
        uint256 target = CCIPConfigLib.minimumPoolBacking(env, chain);
        uint256 poolBalance = IERC20(ohm).balanceOf(tokenPool);

        console2.log("\n=== Fund the CCIP lock/release pool ===");
        console2.log("Pool:", tokenPool);
        console2.log("Target backing (env.json):", target);
        console2.log("Current pool balance:", poolBalance);

        if (poolBalance >= target) {
            console2.log("The pool already holds the target backing. Nothing to do.");
        } else {
            uint256 shortfall = target - poolBalance;
            uint256 ownerBalance = IERC20(ohm).balanceOf(_owner);
            require(
                ownerBalance >= shortfall,
                string.concat(
                    "CCIPTokenPool: the batch owner holds ",
                    vm.toString(ownerBalance),
                    " OHM, below the funding shortfall ",
                    vm.toString(shortfall)
                )
            );
            addToBatch(ohm, abi.encodeWithSelector(IERC20.transfer.selector, tokenPool, shortfall));
            console2.log("Added: OHM.transfer(pool,", shortfall, ")");
        }

        _setPostBatchValidateSelector(this._validateFunded.selector);

        // Run
        proposeBatch();

        console2.log("Completed");
    }

    /// @notice Validates the state after `fundPool`.
    function _validateFunded() external view {
        address ohm = _envAddressNotZero("olympus.legacy.OHM");
        address tokenPool = _getTokenPoolAddressNotZero(chain);
        uint256 target = CCIPConfigLib.minimumPoolBacking(env, chain);
        uint256 poolBalance = IERC20(ohm).balanceOf(tokenPool);
        require(
            poolBalance >= target,
            string.concat(
                "The pool balance ",
                vm.toString(poolBalance),
                " is below the target backing ",
                vm.toString(target)
            )
        );
        console2.log("The pool holds the target backing:", poolBalance);
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
                    "CCIPTokenPool: the batch owner is not the rebalancer of the pool (",
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
    function withdrawAllLiquidity(bool useDaoMS_) external setUpWithChainId(useDaoMS_) {
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
    function withdrawLiquidity(
        bool useDaoMS_,
        uint256 amount_
    ) external setUpWithChainId(useDaoMS_) {
        // Withdraw liquidity
        _withdrawLiquidity(amount_);

        // Run
        proposeBatch();

        console2.log("Completed");
    }

    // ===== INTERNAL HELPERS ===== //

    function _pendingOwner(address tokenPool_) internal view returns (address pending) {
        return CCIPConfigLib.pendingOwner(tokenPool_);
    }
}
