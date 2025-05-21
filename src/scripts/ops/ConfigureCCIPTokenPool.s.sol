// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

import {WithEnvironment} from "src/scripts/WithEnvironment.s.sol";
import {console2} from "forge-std/console2.sol";

import {TokenPool} from "@chainlink-ccip-1.6.0/ccip/pools/TokenPool.sol";
import {RateLimiter} from "@chainlink-ccip-1.6.0/ccip/libraries/RateLimiter.sol";
import {ITokenAdminRegistry} from "@chainlink-ccip-1.6.0/ccip/interfaces/ITokenAdminRegistry.sol";

contract ConfigureCCIPTokenPool is WithEnvironment {
    uint64 public constant SOLANA_DEVNET_CHAIN_SELECTOR = 16423721717087811551;
    bytes32 public constant SOLANA_DEV_TOKEN_POOL_ADDRESS =
        bytes32(0x0000000000000000000000000000000000000000000000000000000000000000);
    bytes32 public constant SOLANA_DEV_TOKEN_ADDRESS =
        bytes32(0x0000000000000000000000000000000000000000000000000000000000000000);

    function acceptAdminRole() external {
        _loadEnv("sepolia");

        ITokenAdminRegistry registry = ITokenAdminRegistry(
            _envAddressNotZero("olympus.ccip.TokenAdminRegistry")
        );
        address token = _envAddressNotZero("olympus.legacy.OHM");

        registry.acceptAdminRole(token);

        console2.log("Admin role accepted");
    }

    function setPool() external {
        _loadEnv("sepolia");

        address token = _envAddressNotZero("olympus.legacy.OHM");
        address tokenPoolAddress = _envAddressNotZero("olympus.policies.CCIPMintBurnTokenPool");

        ITokenAdminRegistry registry = ITokenAdminRegistry(
            _envAddressNotZero("olympus.ccip.TokenAdminRegistry")
        );
        registry.setPool(token, tokenPoolAddress);

        console2.log("Pool set");
    }

    /// @dev temp function. Finalise the declarative configurator before production.
    function configureRemotePoolSolanaDevnet() external {
        _loadEnv("sepolia");

        address tokenPoolAddress = _envAddressNotZero("olympus.policies.CCIPMintBurnTokenPool");
        TokenPool tokenPool = TokenPool(tokenPoolAddress);

        bytes[] memory remotePoolAddresses = new bytes[](1);
        remotePoolAddresses[0] = abi.encodePacked(SOLANA_DEV_TOKEN_POOL_ADDRESS);

        TokenPool.ChainUpdate memory solanaTestnetChainUpdate = TokenPool.ChainUpdate({
            remoteChainSelector: SOLANA_DEVNET_CHAIN_SELECTOR,
            remotePoolAddresses: remotePoolAddresses,
            remoteTokenAddress: abi.encodePacked(SOLANA_DEV_TOKEN_POOL_ADDRESS),
            outboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0}),
            inboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0})
        });
        TokenPool.ChainUpdate[] memory chainUpdates = new TokenPool.ChainUpdate[](1);
        chainUpdates[0] = solanaTestnetChainUpdate;

        // Apply the chain update
        console2.log("Applying chain update\n");
        vm.startBroadcast();
        tokenPool.applyChainUpdates(new uint64[](0), chainUpdates);
        vm.stopBroadcast();
        console2.log("\nChain update applied");
    }
}
