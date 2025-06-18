// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {IPoolV1} from "@chainlink-ccip-1.6.0/ccip/interfaces/IPool.sol";

import {BurnMintTokenPoolAbstract} from "@chainlink-ccip-1.6.0/ccip/pools/BurnMintTokenPoolAbstract.sol";
import {Pool} from "@chainlink-ccip-1.6.0/ccip/libraries/Pool.sol";

/// @title  BurnMintTokenPoolBase
/// @notice Base contract for creating BurnMintTokenPools.
/// @dev    This extends the `BurnMintTokenPoolAbstract` contract to allow for a customisable mint call.
abstract contract BurnMintTokenPoolBase is BurnMintTokenPoolAbstract {
    /// @notice           Specific mint call for a pool.
    /// @dev              Overriding this method allows us to create pools with different mint signatures without duplicating the underlying logic.
    ///
    /// @param receiver_  The address to mint the tokens to.
    /// @param amount_    The amount of tokens to mint.
    function _mint(address receiver_, uint256 amount_) internal virtual;

    /// @inheritdoc IPoolV1
    /// @dev        This is the same as the `releaseOrMint` function in the `BurnMintTokenPoolAbstract` contract, with the direct `mint()` call replaced by the call to the virtual `_mint()` function.
    function releaseOrMint(
        Pool.ReleaseOrMintInV1 calldata releaseOrMintIn
    ) public virtual override returns (Pool.ReleaseOrMintOutV1 memory) {
        _validateReleaseOrMint(releaseOrMintIn);

        // Calculate the local amount
        uint256 localAmount = _calculateLocalAmount(
            releaseOrMintIn.amount,
            _parseRemoteDecimals(releaseOrMintIn.sourcePoolData)
        );

        // Mint to the receiver
        _mint(releaseOrMintIn.receiver, localAmount);

        emit Minted(msg.sender, releaseOrMintIn.receiver, localAmount);

        return Pool.ReleaseOrMintOutV1({destinationAmount: localAmount});
    }
}
