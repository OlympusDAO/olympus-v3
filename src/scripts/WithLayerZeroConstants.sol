// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

abstract contract WithLayerZeroConstants {
    /// @notice Returns the LayerZero endpoint ID for a given chain
    /// @dev    Endpoint IDs are defined here: https://docs.layerzero.network/v1/developers/evm/technical-reference/deployed-contracts
    function _getRemoteEndpointId(string memory chain_) internal pure returns (uint16) {
        if (keccak256(abi.encodePacked(chain_)) == keccak256(abi.encodePacked("arbitrum"))) {
            return 110;
        }

        if (
            keccak256(abi.encodePacked(chain_)) == keccak256(abi.encodePacked("arbitrum-sepolia"))
        ) {
            return 10231;
        }

        if (keccak256(abi.encodePacked(chain_)) == keccak256(abi.encodePacked("base"))) {
            return 184;
        }

        if (keccak256(abi.encodePacked(chain_)) == keccak256(abi.encodePacked("base-sepolia"))) {
            return 10245;
        }

        if (keccak256(abi.encodePacked(chain_)) == keccak256(abi.encodePacked("berachain"))) {
            return 362;
        }

        if (
            keccak256(abi.encodePacked(chain_)) == keccak256(abi.encodePacked("berachain-bartio"))
        ) {
            return 10291;
        }

        if (keccak256(abi.encodePacked(chain_)) == keccak256(abi.encodePacked("mainnet"))) {
            return 101;
        }

        if (keccak256(abi.encodePacked(chain_)) == keccak256(abi.encodePacked("sepolia"))) {
            return 10161;
        }

        if (keccak256(abi.encodePacked(chain_)) == keccak256(abi.encodePacked("optimism"))) {
            return 111;
        }

        if (
            keccak256(abi.encodePacked(chain_)) == keccak256(abi.encodePacked("optimism-sepolia"))
        ) {
            return 10232;
        }

        if (keccak256(abi.encodePacked(chain_)) == keccak256(abi.encodePacked("polygon"))) {
            return 109;
        }

        if (keccak256(abi.encodePacked(chain_)) == keccak256(abi.encodePacked("solana-devnet"))) {
            return 40168;
        }

        if (keccak256(abi.encodePacked(chain_)) == keccak256(abi.encodePacked("solana"))) {
            return 30168;
        }

        // solhint-disable-next-line custom-errors
        revert(string.concat("Unsupported chain: ", chain_));
    }
}
