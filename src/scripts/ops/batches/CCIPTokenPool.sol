// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.24;

import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";
import {console2} from "@forge-std-1.9.6/console2.sol";
import {Base58} from "@base58-solidity-1.0.3/Base58.sol";

import {Kernel, Actions} from "src/Kernel.sol";
import {ITokenAdminRegistry} from "@chainlink-ccip-1.6.0/ccip/interfaces/ITokenAdminRegistry.sol";
import {TokenPool} from "@chainlink-ccip-1.6.0/ccip/pools/TokenPool.sol";
import {RateLimiter} from "@chainlink-ccip-1.6.0/ccip/libraries/RateLimiter.sol";
import {LockReleaseTokenPool} from "@chainlink-ccip-1.6.0/ccip/pools/LockReleaseTokenPool.sol";
import {TokenAdminRegistry} from "@chainlink-ccip-1.6.0/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IPolicyEnabler} from "src/policies/interfaces/utils/IPolicyEnabler.sol";

/// @title ConfigureCCIPTokenPool
/// @notice Multi-sig batch to configure the CCIP bridge
///         This scripts is designed to define the desired configuration,
///         and the script will execute the necessary transactions to
///         configure the CCIP bridge to the desired state.
contract CCIPTokenPoolBatch is BatchScriptV2 {
    /// @dev Returns true if the chain is canonical chain upon which new OHM is minted (mainnet or sepolia)
    function _isChainCanonical(string memory chain_) internal pure returns (bool) {
        return
            keccak256(abi.encodePacked(chain_)) == keccak256(abi.encodePacked("mainnet")) ||
            keccak256(abi.encodePacked(chain_)) == keccak256(abi.encodePacked("sepolia"));
    }

    function _getTokenPoolAddress(string memory chain_) internal view returns (address) {
        if (_isChainCanonical(chain_)) {
            return _envAddressNotZero(chain_, "olympus.periphery.CCIPLockReleaseTokenPool");
        } else {
            return _envAddressNotZero(chain_, "olympus.policies.CCIPBurnMintTokenPool");
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

    // TODOs
    // [ ] Declarative configuration of a token pool
    // [X] Set the owner as the rebalancer of the lock release token pool
    // [X] Add emergency disable/enable

    /// @notice Performs installation and initial configuration of the TokenPool
    /// @dev    On a non-canonical chain: the TokenPool is activated in the Kernel
    ///         On a canonical chain: the TokenPool is a periphery contract and
    ///         does not need activation. The rebalancer is set to the DAO multisig.
    function install(string calldata chain_, bool useDaoMS_) external setUp(chain_, useDaoMS_) {
        // Assumptions
        // - The token pool has been linked to OHM in the CCIP token admin registry
        // - The token pool is already configured

        // Load contract addresses from the environment file
        address kernel = _envAddressNotZero("olympus.Kernel");
        address tokenPool = _getTokenPoolAddress(chain);

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
            addToBatch(tokenPool, abi.encodeWithSelector(IPolicyEnabler.enable.selector, ""));
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
    function acceptAdminRole(
        string calldata chain_,
        bool useDaoMS_
    ) external setUp(chain_, useDaoMS_) {
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
    function setPool(string calldata chain_, bool useDaoMS_) external setUp(chain_, useDaoMS_) {
        // Load contract addresses from the environment file
        address tokenRegistry = _envAddressNotZero("external.ccip.TokenAdminRegistry");
        address token = _envAddressNotZero("olympus.legacy.OHM");
        address tokenPool = _getTokenPoolAddress(chain);

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
    function transferTokenPoolAdminRoleToDaoMS(
        string calldata chain_
    ) external setUp(chain_, false) {
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

    /// @notice Configures the TokenPool to add support for the specified EVM remote chain
    function configureRemoteChainEVM(
        string calldata chain_,
        bool useDaoMS_,
        string calldata remoteChain_
    ) external setUp(chain_, useDaoMS_) {
        address tokenPoolAddress = _getTokenPoolAddress(chain_);
        address remotePoolAddress = _getTokenPoolAddress(remoteChain_);
        address remoteTokenAddress = _envAddressNotZero(remoteChain_, "olympus.legacy.OHM");
        uint64 remoteChainSelector = uint64(
            _envUintNotZero(remoteChain_, "external.ccip.ChainSelector")
        );

        bytes[] memory remotePoolAddresses = new bytes[](1);
        remotePoolAddresses[0] = abi.encode(remotePoolAddress);

        TokenPool.ChainUpdate memory chainUpdate = TokenPool.ChainUpdate({
            remoteChainSelector: remoteChainSelector,
            remotePoolAddresses: remotePoolAddresses,
            remoteTokenAddress: abi.encode(remoteTokenAddress),
            outboundRateLimiterConfig: _getRateLimiterConfigDefault(),
            inboundRateLimiterConfig: _getRateLimiterConfigDefault()
        });
        TokenPool.ChainUpdate[] memory chainUpdates = new TokenPool.ChainUpdate[](1);
        chainUpdates[0] = chainUpdate;

        // If the remote chain is already configured, remove it
        if (TokenPool(tokenPoolAddress).isSupportedChain(remoteChainSelector)) {
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

        // Run
        proposeBatch();

        console2.log("Completed");
    }

    /// @notice Configures the TokenPool to add support for the specified SVM remote chain
    function configureRemoteChainSVM(
        string calldata chain_,
        bool useDaoMS_,
        string calldata remoteChain_
    ) external setUp(chain_, useDaoMS_) {
        address tokenPoolAddress = _getTokenPoolAddress(chain_);
        bytes32 remotePoolAddress = bytes32(
            Base58.decodeFromString(_envStringNotEmpty(remoteChain_, "olympus.periphery.TokenPool"))
        );
        bytes32 remoteTokenAddress = bytes32(
            Base58.decodeFromString(_envStringNotEmpty(remoteChain_, "olympus.legacy.OHM"))
        );
        uint64 remoteChainSelector = uint64(
            _envUintNotZero(remoteChain_, "external.ccip.ChainSelector")
        );

        bytes[] memory remotePoolAddresses = new bytes[](1);
        remotePoolAddresses[0] = abi.encodePacked(remotePoolAddress);

        TokenPool.ChainUpdate memory chainUpdate = TokenPool.ChainUpdate({
            remoteChainSelector: remoteChainSelector,
            remotePoolAddresses: remotePoolAddresses,
            remoteTokenAddress: abi.encodePacked(remoteTokenAddress),
            outboundRateLimiterConfig: _getRateLimiterConfigDefault(),
            inboundRateLimiterConfig: _getRateLimiterConfigDefault()
        });
        TokenPool.ChainUpdate[] memory chainUpdates = new TokenPool.ChainUpdate[](1);
        chainUpdates[0] = chainUpdate;

        // If the remote chain is already configured, remove it
        if (TokenPool(tokenPoolAddress).isSupportedChain(remoteChainSelector)) {
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

        // Run
        proposeBatch();

        console2.log("Completed");
    }

    // ===== EMERGENCY SHUTDOWN ===== //

    function _emergencyShutdown(uint64 remoteChainSelector_) internal {
        address tokenPoolAddress = _getTokenPoolAddress(chain);

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

    /// @notice Performs an emergency shutdown of the TokenPool for a specific remote chain by enabling the rate limiter with a very low capacity
    /// @dev    To restore the token pool functionality, the `configureRemoteChainEVM` or `configureRemoteChainSVM` functions can be used.
    function emergencyShutdown(
        string calldata chain_,
        bool useDaoMS_,
        string calldata remoteChain_
    ) external setUp(chain_, useDaoMS_) {
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
    function emergencyShutdownAll(
        string calldata chain_,
        bool useDaoMS_
    ) external setUp(chain_, useDaoMS_) {
        // Determine the remote chains that are configured
        uint64[] memory remoteChainSelectors = TokenPool(_getTokenPoolAddress(chain))
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

        address tokenPoolAddress = _getTokenPoolAddress(chain);

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
    function withdrawAllLiquidity(
        string calldata chain_,
        bool useDaoMS_
    ) external setUp(chain_, useDaoMS_) {
        uint256 liquidity = IERC20(_getTokenPoolAddress(chain)).balanceOf(_owner);

        // Withdraw liquidity
        _withdrawLiquidity(liquidity);

        // Run
        proposeBatch();

        console2.log("Completed");
    }

    /// @notice Withdraws a specific amount of OHM from a LockReleaseTokenPool
    /// @dev    This function can only be called on canonical chains
    function withdrawLiquidity(
        string calldata chain_,
        bool useDaoMS_,
        uint256 amount_
    ) external setUp(chain_, useDaoMS_) {
        // Withdraw liquidity
        _withdrawLiquidity(amount_);

        // Run
        proposeBatch();

        console2.log("Completed");
    }
}
