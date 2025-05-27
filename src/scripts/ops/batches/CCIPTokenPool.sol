// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.24;

import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";
import {console2} from "forge-std/console2.sol";
import {Base58Decoder} from "src/scripts/ops/lib/Base58Decoder.sol";

import {Kernel, Actions} from "src/Kernel.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {ITokenAdminRegistry} from "@chainlink-ccip-1.6.0/ccip/interfaces/ITokenAdminRegistry.sol";
import {TokenPool} from "@chainlink-ccip-1.6.0/ccip/pools/TokenPool.sol";
import {RateLimiter} from "@chainlink-ccip-1.6.0/ccip/libraries/RateLimiter.sol";

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
            return _envAddressNotZero("olympus.policies.CCIPLockReleaseTokenPool");
        } else {
            return _envAddressNotZero("olympus.policies.CCIPBurnMintTokenPool");
        }
    }

    function install(string calldata chain_, bool useDaoMS_) external setUp(chain_, useDaoMS_) {
        // Assumptions
        // - The token pool has been linked to OHM in the CCIP token admin registry
        // - The token pool is already configured

        // Load contract addresses from the environment file
        address kernel = _envAddressNotZero("olympus.Kernel");
        address tokenPool = _getTokenPoolAddress(chain);
        address crossChainBridge = _envAddressNotZero("olympus.periphery.CCIPCrossChainBridge");

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

        // Accept the admin role
        addToBatch(
            tokenRegistry,
            abi.encodeWithSelector(ITokenAdminRegistry.acceptAdminRole.selector, token)
        );

        // Run
        proposeBatch();

        console2.log("Completed");
    }

    /// @notice Sets the pool for the OHM token
    function setPool(string calldata chain_, bool useDaoMS_) external setUp(chain_, useDaoMS_) {
        // Load contract addresses from the environment file
        address tokenRegistry = _envAddressNotZero("external.ccip.TokenAdminRegistry");
        address token = _envAddressNotZero("olympus.legacy.OHM");
        address tokenPool = _getTokenPoolAddress(chain);

        // Set the pool
        addToBatch(
            tokenRegistry,
            abi.encodeWithSelector(ITokenAdminRegistry.setPool.selector, token, tokenPool)
        );

        // Run
        proposeBatch();

        console2.log("Completed");
    }

    function transferTokenPoolAdminRole(
        string calldata chain_,
        bool useDaoMS_
    ) external setUp(chain_, useDaoMS_) {
        address tokenRegistry = _envAddressNotZero("external.ccip.TokenAdminRegistry");
        address token = _envAddressNotZero("olympus.legacy.OHM");
        address newOwner = _envAddressNotZero("olympus.multisig.dao");

        addToBatch(
            tokenRegistry,
            abi.encodeWithSelector(ITokenAdminRegistry.transferAdminRole.selector, token, newOwner)
        );

        // Run
        proposeBatch();

        console2.log("Transferred admin role to DAO MS");

        // Next steps:
        // - DAO MS must accept the admin role
    }

    function configureRemotePool(
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
        remotePoolAddresses[0] = abi.encodePacked(remotePoolAddress);

        TokenPool.ChainUpdate memory chainUpdate = TokenPool.ChainUpdate({
            remoteChainSelector: remoteChainSelector,
            remotePoolAddresses: remotePoolAddresses,
            remoteTokenAddress: abi.encodePacked(remoteTokenAddress),
            outboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0}),
            inboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0})
        });
        TokenPool.ChainUpdate[] memory chainUpdates = new TokenPool.ChainUpdate[](1);
        chainUpdates[0] = chainUpdate;

        // Apply the chain update
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

    /// @dev temp function. Finalise the declarative configurator before production.
    function configureRemotePoolSolana(
        string calldata chain_,
        bool useDaoMS_,
        string calldata remoteChain_
    ) external setUp(chain_, useDaoMS_) {
        address tokenPoolAddress = _getTokenPoolAddress(chain_);
        bytes32 remotePoolAddress = Base58Decoder.decode(
            _envStringNotEmpty(remoteChain_, "olympus.periphery.TokenPool")
        );
        bytes32 remoteTokenAddress = Base58Decoder.decode(
            _envStringNotEmpty(remoteChain_, "olympus.legacy.OHM")
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
            outboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0}),
            inboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0})
        });
        TokenPool.ChainUpdate[] memory chainUpdates = new TokenPool.ChainUpdate[](1);
        chainUpdates[0] = chainUpdate;

        // Apply the chain update
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
}
