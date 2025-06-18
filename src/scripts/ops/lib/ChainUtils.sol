// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.15;

import {ArrayUtils} from "./ArrayUtils.sol";

library ChainUtils {
    string public constant PROD_MAINNET = "mainnet";
    string public constant PROD_BASE = "base";
    string public constant PROD_ARBITRUM = "arbitrum";
    string public constant PROD_BERACHAIN = "berachain";
    string public constant PROD_OPTIMISM = "optimism";
    string public constant PROD_SOLANA = "solana";

    string public constant TEST_SEPOLIA = "sepolia";
    string public constant TEST_BASE_SEPOLIA = "base-sepolia";
    string public constant TEST_ARBITRUM_SEPOLIA = "arbitrum-sepolia";
    string public constant TEST_BERACHAIN_BARTIO = "berachain-bartio";
    string public constant TEST_SOLANA = "solana-devnet";

    uint256 public constant CHAIN_MAINNET = 1;
    uint256 public constant CHAIN_SEPOLIA = 11155111;
    uint256 public constant CHAIN_BASE = 8453;
    uint256 public constant CHAIN_BASE_SEPOLIA = 84532;
    uint256 public constant CHAIN_ARBITRUM = 42161;
    uint256 public constant CHAIN_ARBITRUM_SEPOLIA = 421614;
    uint256 public constant CHAIN_BERACHAIN = 80094;
    uint256 public constant CHAIN_BERACHAIN_BEPOLIA = 80069;
    uint256 public constant CHAIN_OPTIMISM = 10;
    uint256 public constant CHAIN_OPTIMISM_SEPOLIA = 11155420;
    uint256 public constant CHAIN_POLYGON = 137;
    uint256 public constant CHAIN_POLYGON_AMOY = 80002;

    /// @notice Returns an array of testnet chains
    function _getTestnetChains() internal pure returns (string[] memory) {
        string[] memory chains = new string[](5);
        chains[0] = TEST_SEPOLIA;
        chains[1] = TEST_BASE_SEPOLIA;
        chains[2] = TEST_ARBITRUM_SEPOLIA;
        chains[3] = TEST_BERACHAIN_BARTIO;
        chains[4] = TEST_SOLANA;

        return chains;
    }

    /// @notice Returns an array of production chains
    function _getProductionChains() internal pure returns (string[] memory) {
        string[] memory chains = new string[](6);
        chains[0] = PROD_MAINNET;
        chains[1] = PROD_BASE;
        chains[2] = PROD_ARBITRUM;
        chains[3] = PROD_BERACHAIN;
        chains[4] = PROD_OPTIMISM;
        chains[5] = PROD_SOLANA;

        return chains;
    }

    /// @notice Returns all of the production or testnet chains, based on whether `chain_` is a production or testnet chain
    function _getChains(string memory chain_) internal pure returns (string[] memory) {
        if (_isProductionChain(chain_)) {
            return _getProductionChains();
        } else if (_isTestnetChain(chain_)) {
            return _getTestnetChains();
        } else {
            // solhint-disable-next-line gas-custom-errors
            revert("_getChains: Chain is not a production or testnet chain");
        }
    }

    /// @notice Returns true if the chain is canonical chain upon which new OHM is minted (mainnet or sepolia)
    function _isCanonicalChain(string memory chain_) internal pure returns (bool) {
        return keccak256(abi.encodePacked(chain_)) == keccak256(abi.encodePacked(PROD_MAINNET)) ||
            keccak256(abi.encodePacked(chain_)) == keccak256(abi.encodePacked(TEST_SEPOLIA));
    }

    /// @notice Returns true if the chain is a production chain
    function _isProductionChain(string memory chain_) internal pure returns (bool) {
        return ArrayUtils.contains(_getProductionChains(), chain_);
    }

    /// @notice Returns true if the chain is a testnet chain
    function _isTestnetChain(string memory chain_) internal pure returns (bool) {
        return ArrayUtils.contains(_getTestnetChains(), chain_);
    }

    /// @notice Returns true if the chain is an SVM chain
    function _isSVMChain(string memory chain_) internal pure returns (bool) {
        return keccak256(abi.encodePacked(chain_)) == keccak256(abi.encodePacked(PROD_SOLANA)) ||
            keccak256(abi.encodePacked(chain_)) == keccak256(abi.encodePacked(TEST_SOLANA));
    }

    /// @notice Returns the name of the chain for a given chain ID
    function _getChainName(uint256 chainId_) internal pure returns (string memory) {
        if (chainId_ == CHAIN_MAINNET) {
            return PROD_MAINNET;
        } else if (chainId_ == CHAIN_SEPOLIA) {
            return TEST_SEPOLIA;
        } else if (chainId_ == CHAIN_BASE) {
            return PROD_BASE;
        } else if (chainId_ == CHAIN_BASE_SEPOLIA) {
            return TEST_BASE_SEPOLIA;
        } else if (chainId_ == CHAIN_ARBITRUM) {
            return PROD_ARBITRUM;
        } else if (chainId_ == CHAIN_ARBITRUM_SEPOLIA) {
            return TEST_ARBITRUM_SEPOLIA;
        } else if (chainId_ == CHAIN_BERACHAIN) {
            return PROD_BERACHAIN;
        } else if (chainId_ == CHAIN_OPTIMISM) {
            return PROD_OPTIMISM;
        } else {
            // solhint-disable-next-line gas-custom-errors
            revert("_getChainId: Chain ID not found");
        }
    }
}
