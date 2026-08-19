// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.24;

import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";
import {console2} from "@forge-std-1.16.2/console2.sol";
import {Base58} from "@base58-solidity-1.0.3/Base58.sol";

import {Kernel, Actions} from "src/Kernel.sol";
import {ITokenAdminRegistry} from "@chainlink-ccip-1.6.0/ccip/interfaces/ITokenAdminRegistry.sol";
import {TokenPool} from "@chainlink-ccip-1.6.0/ccip/pools/TokenPool.sol";
import {RateLimiter} from "@chainlink-ccip-1.6.0/ccip/libraries/RateLimiter.sol";
import {LockReleaseTokenPool} from "@chainlink-ccip-1.6.0/ccip/pools/LockReleaseTokenPool.sol";
import {Ownable2Step} from "@chainlink-ccip-1.6.0/shared/access/Ownable2Step.sol";
import {TokenAdminRegistry} from "@chainlink-ccip-1.6.0/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {ChainUtils} from "src/scripts/ops/lib/ChainUtils.sol";
import {ArrayUtils} from "src/scripts/ops/lib/ArrayUtils.sol";
import {SafeCast} from "src/libraries/SafeCast.sol";

/// @title ConfigureCCIPTokenPool
/// @notice Multi-sig batch to configure the CCIP bridge
///         This scripts is designed to define the desired configuration,
///         and the script will execute the necessary transactions to
///         configure the CCIP bridge to the desired state.
contract CCIPTokenPool is BatchScriptV2 {
    using SafeCast for uint256;

    /// @dev Returns true if the chain is canonical chain upon which new OHM is minted (mainnet or sepolia)
    function _isChainCanonical(string memory chain_) internal pure returns (bool) {
        return
            keccak256(abi.encodePacked(chain_)) == keccak256(abi.encodePacked("mainnet")) ||
            keccak256(abi.encodePacked(chain_)) == keccak256(abi.encodePacked("sepolia"));
    }

    function _getTokenPoolAddressNotZero(string memory chain_) internal view returns (address) {
        if (_isChainCanonical(chain_)) {
            return _envAddressNotZero(chain_, "olympus.periphery.CCIPLockReleaseTokenPool");
        } else {
            return _envAddressNotZero(chain_, "olympus.policies.CCIPBurnMintTokenPool");
        }
    }

    function _getTokenPoolAddress(string memory chain_) internal view returns (address) {
        if (_isChainCanonical(chain_)) {
            return _envAddress(chain_, "olympus.periphery.CCIPLockReleaseTokenPool");
        } else {
            return _envAddress(chain_, "olympus.policies.CCIPBurnMintTokenPool");
        }
    }

    function _getTokenAdminRegistryConfig()
        internal
        view
        returns (TokenAdminRegistry.TokenConfig memory)
    {
        address tokenRegistry = _envAddressNotZero("external.ccip.TokenAdminRegistry");
        address token = _envAddressNotZero("olympus.legacy.OHM");

        return TokenAdminRegistry(tokenRegistry).getTokenConfig(token);
    }

    /// @notice Default rate limiter config for a TokenPool
    /// @dev    The rate limiter is disabled by default, hence there is no rate limit
    function _getRateLimiterConfigDefault() internal pure returns (RateLimiter.Config memory) {
        return RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0});
    }

    /// @notice Rate limiter config for emergency shutdown
    /// @dev    The rate limiter is enabled, with a very low capacity, which means the bridge is effectively disabled
    function _getRateLimiterConfigEmergencyShutdown()
        internal
        pure
        returns (RateLimiter.Config memory)
    {
        return RateLimiter.Config({isEnabled: true, capacity: 2, rate: 1});
    }

    // [X] Declarative configuration of a token pool
    // [X] Set the owner as the rebalancer of the lock release token pool
    // [X] Add emergency disable/enable
    // [X] Determine local chain from block.chainid

    /// @notice Performs installation and initial configuration of the TokenPool
    /// @dev    On a non-canonical chain: the TokenPool is activated in the Kernel
    ///         On a canonical chain: the TokenPool is a periphery contract and
    ///         does not need activation. The rebalancer is set to the DAO multisig.
    function install(bool useDaoMS_) external setUpWithChainId(useDaoMS_) {
        // Assumptions
        // - The token pool has been linked to OHM in the CCIP token admin registry
        // - The token pool is already configured

        // Load contract addresses from the environment file
        address kernel = _envAddressNotZero("olympus.Kernel");
        address tokenPool = _getTokenPoolAddressNotZero(chain);

        if (!_isChainCanonical(chain)) {
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

            // Set the owner as the rebalancer on the LockReleaseTokenPool
            // Allows for withdrawing OHM from the LockReleaseTokenPool
            addToBatch(
                tokenPool,
                abi.encodeWithSelector(
                    LockReleaseTokenPool.setRebalancer.selector,
                    _envAddressNotZero("olympus.multisig.dao")
                )
            );
            console2.log(
                "Canonical chain: Set the owner as the rebalancer of the LockReleaseTokenPool"
            );
        }

        // Run
        proposeBatch();

        console2.log("Completed");

        // Next steps:
        // - Non-canonical chains: Governance to enable the TokenPool policy
    }

    /// @notice Accepts the admin role for the OHM token
    function acceptAdminRole(bool useDaoMS_) external setUpWithChainId(useDaoMS_) {
        // Load contract addresses from the environment file
        address tokenRegistry = _envAddressNotZero("external.ccip.TokenAdminRegistry");
        address token = _envAddressNotZero("olympus.legacy.OHM");

        // Check if the owner is already the administrator
        if (_getTokenAdminRegistryConfig().administrator == _owner) {
            console2.log("Owner", _owner, "is already the administrator. Skipping.");
            return;
        }

        // Accept the admin role
        console2.log("Accepting admin role for", token, "to", _owner);
        addToBatch(
            tokenRegistry,
            abi.encodeWithSelector(ITokenAdminRegistry.acceptAdminRole.selector, token)
        );

        // Run
        proposeBatch();

        console2.log("Completed");
    }

    /// @notice Sets the token pool for the OHM token
    function setPool(bool useDaoMS_) external setUpWithChainId(useDaoMS_) {
        // Load contract addresses from the environment file
        address tokenRegistry = _envAddressNotZero("external.ccip.TokenAdminRegistry");
        address token = _envAddressNotZero("olympus.legacy.OHM");
        address tokenPool = _getTokenPoolAddressNotZero(chain);

        // Check if the pool is already set
        if (_getTokenAdminRegistryConfig().tokenPool == tokenPool) {
            console2.log("Pool", tokenPool, "is already set. Skipping.");
            return;
        }

        // Set the pool
        console2.log("Setting pool for", token, "to", tokenPool);
        addToBatch(
            tokenRegistry,
            abi.encodeWithSelector(ITokenAdminRegistry.setPool.selector, token, tokenPool)
        );

        // Run
        proposeBatch();

        console2.log("Completed");
    }

    /// @notice Transfers the admin role for the OHM token to the DAO multisig
    function transferTokenPoolAdminRoleToDaoMS() external setUpWithChainId(false) {
        address tokenRegistry = _envAddressNotZero("external.ccip.TokenAdminRegistry");
        address token = _envAddressNotZero("olympus.legacy.OHM");
        address daoMS = _envAddressNotZero("olympus.multisig.dao");

        // Check if the admin role is already transferred
        if (_getTokenAdminRegistryConfig().administrator == daoMS) {
            console2.log("Admin role already transferred to", daoMS, ". Skipping.");
            return;
        }

        console2.log("Transferring admin role for", token, "to", daoMS);
        addToBatch(
            tokenRegistry,
            abi.encodeWithSelector(ITokenAdminRegistry.transferAdminRole.selector, token, daoMS)
        );

        // Run
        proposeBatch();

        console2.log("Completed");

        // Next steps:
        // - DAO MS must accept the admin role
    }

    /// @notice Transfers the ownership of the TokenPool to the DAO multisig
    function transferTokenPoolOwnershipToDaoMS() external setUpWithChainId(false) {
        address tokenPool = _getTokenPoolAddressNotZero(chain);
        address daoMS = _envAddressNotZero("olympus.multisig.dao");

        // Check if the owner is already the DAO MS
        if (LockReleaseTokenPool(tokenPool).owner() == daoMS) {
            console2.log("Owner already transferred to", daoMS, ". Skipping.");
            return;
        }

        console2.log("Transferring ownership of", tokenPool, "to", daoMS);
        addToBatch(
            tokenPool,
            abi.encodeWithSelector(Ownable2Step.transferOwnership.selector, daoMS)
        );

        // Run
        proposeBatch();

        console2.log("Completed");

        // Next steps:
        // - DAO MS must accept the ownership
    }

    /// @notice Accepts the ownership of the TokenPool
    function acceptTokenPoolOwnership() external setUpWithChainId(false) {
        address tokenPool = _getTokenPoolAddressNotZero(chain);
        address daoMS = _envAddressNotZero("olympus.multisig.dao");

        // Check if the owner is already the DAO MS
        if (LockReleaseTokenPool(tokenPool).owner() == daoMS) {
            console2.log("Owner already transferred to", daoMS, ". Skipping.");
            return;
        }

        console2.log("Accepting ownership of", tokenPool, "to", daoMS);
        addToBatch(tokenPool, abi.encodeWithSelector(Ownable2Step.acceptOwnership.selector));

        // Run
        proposeBatch();

        console2.log("Completed");
    }

    function _configureRemoteChainEVM(string memory remoteChain_, bool shouldReset_) internal {
        console2.log("\n");
        console2.log("Configuring remote chain", remoteChain_);

        address tokenPoolAddress = _getTokenPoolAddress(chain);
        // If the token pool is the zero address, then there is nothing to do
        if (tokenPoolAddress == address(0)) {
            console2.log("Token pool address is the zero address. Skipping.");
            return;
        }

        address remotePoolAddress = _getTokenPoolAddress(remoteChain_);
        // If the remote pool is the zero address, then there is nothing to do
        if (remotePoolAddress == address(0)) {
            console2.log("Remote pool address is the zero address. Skipping.");
            return;
        }

        address remoteTokenAddress = _envAddressNotZero(remoteChain_, "olympus.legacy.OHM");
        uint64 remoteChainSelector = uint64(
            _envUintNotZero(remoteChain_, "external.ccip.ChainSelector")
        );
        bool isSupportedChain = TokenPool(tokenPoolAddress).isSupportedChain(remoteChainSelector);

        // If resetting, then it should be removed
        if (shouldReset_) {
            if (!isSupportedChain) {
                console2.log("Remote chain is not configured. Skipping.");
                return;
            }

            uint64[] memory remoteChainSelectors = new uint64[](1);
            remoteChainSelectors[0] = remoteChainSelector;

            addToBatch(
                tokenPoolAddress,
                abi.encodeWithSelector(
                    TokenPool.applyChainUpdates.selector,
                    remoteChainSelectors,
                    new TokenPool.ChainUpdate[](0)
                )
            );

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

            uint64[] memory remoteChainSelectors = new uint64[](1);
            remoteChainSelectors[0] = remoteChainSelector;

            addToBatch(
                tokenPoolAddress,
                abi.encodeWithSelector(
                    TokenPool.applyChainUpdates.selector,
                    remoteChainSelectors,
                    new TokenPool.ChainUpdate[](0)
                )
            );
        }

        // Prepare the chain update
        TokenPool.ChainUpdate[] memory chainUpdates = new TokenPool.ChainUpdate[](1);
        {
            // Prepare the remote pool addresses
            bytes[] memory remotePoolAddresses = new bytes[](1);
            remotePoolAddresses[0] = abi.encode(remotePoolAddress);

            // Prepare the chain update
            TokenPool.ChainUpdate memory chainUpdate = TokenPool.ChainUpdate({
                remoteChainSelector: remoteChainSelector,
                remotePoolAddresses: remotePoolAddresses,
                remoteTokenAddress: abi.encode(remoteTokenAddress),
                outboundRateLimiterConfig: _getRateLimiterConfigDefault(),
                inboundRateLimiterConfig: _getRateLimiterConfigDefault()
            });
            chainUpdates[0] = chainUpdate;
        }

        // Apply the chain update
        console2.log("Applying chain update for", remoteChain_, "to token pool", tokenPoolAddress);
        addToBatch(
            tokenPoolAddress,
            abi.encodeWithSelector(
                TokenPool.applyChainUpdates.selector,
                new uint64[](0),
                chainUpdates
            )
        );
    }

    /// @notice Configures the TokenPool to add support for the specified EVM remote chain
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

        address tokenPoolAddress = _getTokenPoolAddress(chain);
        // If the local pool is the zero address, then there is nothing to do
        if (tokenPoolAddress == address(0)) {
            console2.log("Token pool address is the zero address. Skipping.");
            return;
        }

        bytes32 remotePoolAddress = bytes32(
            Base58.decodeFromString(_envStringNotEmpty(remoteChain_, "olympus.periphery.TokenPool"))
        );
        // If the remote pool is the zero address, then there is nothing to do
        if (remotePoolAddress == bytes32(0)) {
            console2.log("Remote pool address is the zero address. Skipping.");
            return;
        }

        bytes32 remoteTokenAddress = bytes32(
            Base58.decodeFromString(_envStringNotEmpty(remoteChain_, "olympus.legacy.OHM"))
        );
        uint64 remoteChainSelector = uint64(
            _envUintNotZero(remoteChain_, "external.ccip.ChainSelector")
        );
        bool isSupportedChain = TokenPool(tokenPoolAddress).isSupportedChain(remoteChainSelector);

        // If resetting, then it should be removed
        if (shouldReset_) {
            if (!isSupportedChain) {
                console2.log("Remote chain is not configured. Skipping.");
                return;
            }

            uint64[] memory remoteChainSelectors = new uint64[](1);
            remoteChainSelectors[0] = remoteChainSelector;

            addToBatch(
                tokenPoolAddress,
                abi.encodeWithSelector(
                    TokenPool.applyChainUpdates.selector,
                    remoteChainSelectors,
                    new TokenPool.ChainUpdate[](0)
                )
            );

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

            uint64[] memory remoteChainSelectors = new uint64[](1);
            remoteChainSelectors[0] = remoteChainSelector;

            addToBatch(
                tokenPoolAddress,
                abi.encodeWithSelector(
                    TokenPool.applyChainUpdates.selector,
                    remoteChainSelectors,
                    new TokenPool.ChainUpdate[](0)
                )
            );
        }

        // Prepare the chain update
        TokenPool.ChainUpdate[] memory chainUpdates = new TokenPool.ChainUpdate[](1);
        {
            // Prepare the remote pool addresses
            bytes[] memory remotePoolAddresses = new bytes[](1);
            remotePoolAddresses[0] = abi.encodePacked(remotePoolAddress);

            TokenPool.ChainUpdate memory chainUpdate = TokenPool.ChainUpdate({
                remoteChainSelector: remoteChainSelector,
                remotePoolAddresses: remotePoolAddresses,
                remoteTokenAddress: abi.encodePacked(remoteTokenAddress),
                outboundRateLimiterConfig: _getRateLimiterConfigDefault(),
                inboundRateLimiterConfig: _getRateLimiterConfigDefault()
            });
            chainUpdates[0] = chainUpdate;
        }

        // Apply the chain update
        console2.log("Applying chain update for", remoteChain_, "to token pool", tokenPoolAddress);
        addToBatch(
            tokenPoolAddress,
            abi.encodeWithSelector(
                TokenPool.applyChainUpdates.selector,
                new uint64[](0),
                chainUpdates
            )
        );
    }

    /// @notice Configures the TokenPool to add support for the specified SVM remote chain
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
    /// @dev    This function skips the function call if the remote chain is already configured
    ///         This function removes the remote chain if the chain is not in the trusted chains listed in the config
    function configureAllRemoteChains(bool useDaoMS_) external setUpWithChainId(useDaoMS_) {
        // Configure the remote chains
        _configureRemoteChains(chain);

        // Run
        proposeBatch();
    }

    // ===== EMERGENCY SHUTDOWN ===== //

    function _emergencyShutdown(uint64 remoteChainSelector_) internal {
        address tokenPoolAddress = _getTokenPoolAddressNotZero(chain);

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
                TokenPool.setChainRateLimiterConfig.selector,
                remoteChainSelector_,
                _getRateLimiterConfigEmergencyShutdown(),
                _getRateLimiterConfigEmergencyShutdown()
            )
        );
    }

    function _readRateLimiterConfig(
        string memory functionName_,
        string memory argPrefix_
    ) internal view returns (RateLimiter.Config memory) {
        // capacity and rate are OHM local token units with 9 decimals, matching the CCIP OHM token decimals.
        return
            RateLimiter.Config({
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
        RateLimiter.Config memory config_
    ) internal pure {
        console2.log(label_);
        console2.log("  Enabled:", config_.isEnabled);
        console2.log("  Capacity:", config_.capacity);
        console2.log("  Rate:", config_.rate);
    }

    /// @notice Sets the outbound and inbound TokenPool rate limits for a remote chain
    /// @dev    The local chain is determined from block.chainid. `capacity` is the max bucket size and `rate` is the
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
            // solhint-disable-next-line gas-custom-errors
            revert("Local chain arg does not match the execution chain");
        }
        _skipHeartbeatValidation = true;

        string memory remoteChain = _readBatchArgString("setRateLimits", "remoteChain");
        uint64 remoteChainSelector = uint64(
            _envUintNotZero(remoteChain, "external.ccip.ChainSelector")
        );
        address tokenPoolAddress = _getTokenPoolAddressNotZero(chain);

        if (!TokenPool(tokenPoolAddress).isSupportedChain(remoteChainSelector)) {
            // solhint-disable-next-line gas-custom-errors
            revert("Remote chain is not configured on the TokenPool");
        }

        RateLimiter.Config memory outboundRateLimiterConfig = _readRateLimiterConfig(
            "setRateLimits",
            "outboundRateLimiterConfig"
        );
        RateLimiter.Config memory inboundRateLimiterConfig = _readRateLimiterConfig(
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
                TokenPool.setChainRateLimiterConfig.selector,
                remoteChainSelector,
                outboundRateLimiterConfig,
                inboundRateLimiterConfig
            )
        );

        // Run
        proposeBatch();

        console2.log("Completed");
    }

    /// @notice Performs an emergency shutdown of the TokenPool for a specific remote chain by enabling the rate limiter with a very low capacity
    /// @dev    To restore the token pool functionality, the `configureRemoteChainEVM` or `configureRemoteChainSVM` functions can be used.
    function emergencyShutdown(
        bool useDaoMS_,
        string calldata remoteChain_
    ) external setUpWithChainId(useDaoMS_) {
        uint64 remoteChainSelector = uint64(
            _envUintNotZero(remoteChain_, "external.ccip.ChainSelector")
        );

        _emergencyShutdown(remoteChainSelector);

        // Run
        proposeBatch();

        console2.log("Completed");
    }

    /// @notice Performs an emergency shutdown of the TokenPool for all remote chains by enabling the rate limiter with a very low capacity
    /// @dev    To restore the token pool functionality, the `configureRemoteChainEVM` or `configureRemoteChainSVM` functions can be used.
    function emergencyShutdownAll(bool useDaoMS_) external setUpWithChainId(useDaoMS_) {
        // Determine the remote chains that are configured
        uint64[] memory remoteChainSelectors = TokenPool(_getTokenPoolAddressNotZero(chain))
            .getSupportedChains();

        for (uint256 i = 0; i < remoteChainSelectors.length; i++) {
            _emergencyShutdown(remoteChainSelectors[i]);
        }

        // Run
        proposeBatch();

        console2.log("Completed");
    }

    function _withdrawLiquidity(uint256 liquidity_) internal {
        // Validate that the chain is canonical
        if (!_isChainCanonical(chain)) {
            // solhint-disable-next-line gas-custom-errors
            revert(
                "Withdrawing liquidity is only supported on the LockReleaseTokenPool on canonical chains"
            );
        }

        address tokenPoolAddress = _getTokenPoolAddressNotZero(chain);

        // Withdraw liquidity
        console2.log(
            "Withdrawing liquidity of",
            liquidity_,
            "OHM from token pool",
            tokenPoolAddress
        );
        addToBatch(
            tokenPoolAddress,
            abi.encodeWithSelector(LockReleaseTokenPool.withdrawLiquidity.selector, liquidity_)
        );
    }

    /// @notice Withdraws the total balance of OHM from a LockReleaseTokenPool
    /// @dev    This function can only be called on canonical chains
    function withdrawAllLiquidity(bool useDaoMS_) external setUpWithChainId(useDaoMS_) {
        uint256 liquidity = IERC20(_getTokenPoolAddressNotZero(chain)).balanceOf(_owner);

        // Withdraw liquidity
        _withdrawLiquidity(liquidity);

        // Run
        proposeBatch();

        console2.log("Completed");
    }

    /// @notice Withdraws a specific amount of OHM from a LockReleaseTokenPool
    /// @dev    This function can only be called on canonical chains
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
}
