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
    string public constant TEST_GOERLI = "goerli";
    string public constant TEST_SOLANA = "solana-devnet";

    /// @notice Returns an array of testnet chains
    function _getTestnetChains() internal pure returns (string[] memory) {
        string[] memory chains = new string[](6);
        chains[0] = TEST_SEPOLIA;
        chains[1] = TEST_BASE_SEPOLIA;
        chains[2] = TEST_ARBITRUM_SEPOLIA;
        chains[3] = TEST_BERACHAIN_BARTIO;
        chains[4] = TEST_GOERLI;
        chains[5] = TEST_SOLANA;

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
}
