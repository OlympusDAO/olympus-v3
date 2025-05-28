// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "@chainlink-ccip-1.6.0/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {ICCIPTokenPool} from "src/policies/interfaces/ICCIPTokenPool.sol";

// Libraries
import {SafeERC20} from "@chainlink-ccip-1.6.0/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/utils/SafeERC20.sol";

// Periphery
import {PeripheryEnabler} from "src/periphery/PeripheryEnabler.sol";

// CCIP
import {LockReleaseTokenPool} from "@chainlink-ccip-1.6.0/ccip/pools/LockReleaseTokenPool.sol";
import {Pool} from "@chainlink-ccip-1.6.0/ccip/libraries/Pool.sol";

/// @title  CCIPLockReleaseTokenPool
/// @notice A `LockReleaseTokenPool` that is enabled and disabled via the `PeripheryEnabler` contract.
///         It is a periphery contract, as it does not require any privileged access to the Olympus protocol.
///         It is also configured to return an appropriate value for the `getBridgedSupply()` function.
contract CCIPLockReleaseTokenPool is LockReleaseTokenPool, PeripheryEnabler, ICCIPTokenPool {
    using SafeERC20 for IERC20;

    // NOTE: This should ideally override the `typeAndVersion` function, but it is not possible to do so
    //       as the `LockReleaseTokenPool` contract does not have a virtual `typeAndVersion` function

    // ========= CONSTRUCTOR ========= //

    constructor(
        address ohm_,
        address rmnProxy_,
        address ccipRouter_
    ) LockReleaseTokenPool(IERC20(ohm_), 9, new address[](0), rmnProxy_, true, ccipRouter_) {
        // Disabled by default
        // Owner is set to msg.sender
        // The current owner must call `transferOwnership` to transfer ownership to the desired address
    }

    // ========= TOKENPOOL FUNCTIONS ========= //

    /// @inheritdoc LockReleaseTokenPool
    /// @dev        This function overrides the `LockReleaseTokenPool` implementation to validate the enabled state
    function lockOrBurn(
        Pool.LockOrBurnInV1 calldata lockOrBurnIn
    ) public virtual override onlyEnabled returns (Pool.LockOrBurnOutV1 memory) {
        // The following code is taken from the `LockReleaseTokenPool` contract
        // The `lockOrBurn` function is external, which prevents `super.lockOrBurn()` from being called
        _validateLockOrBurn(lockOrBurnIn);

        emit Locked(msg.sender, lockOrBurnIn.amount);

        return
            Pool.LockOrBurnOutV1({
                destTokenAddress: getRemoteToken(lockOrBurnIn.remoteChainSelector),
                destPoolData: _encodeLocalDecimals()
            });
    }

    /// @inheritdoc LockReleaseTokenPool
    /// @dev        This function overrides the `LockReleaseTokenPool` implementation to validate the enabled state
    function releaseOrMint(
        Pool.ReleaseOrMintInV1 calldata releaseOrMintIn
    ) public virtual override onlyEnabled returns (Pool.ReleaseOrMintOutV1 memory) {
        // The following code is taken from the `LockReleaseTokenPool` contract
        // The `releaseOrMint` function is external, which prevents `super.releaseOrMint()` from being called
        _validateReleaseOrMint(releaseOrMintIn);

        // Calculate the local amount
        uint256 localAmount = _calculateLocalAmount(
            releaseOrMintIn.amount,
            _parseRemoteDecimals(releaseOrMintIn.sourcePoolData)
        );

        // Release to the recipient
        getToken().safeTransfer(releaseOrMintIn.receiver, localAmount);

        emit Released(msg.sender, releaseOrMintIn.receiver, localAmount);

        return Pool.ReleaseOrMintOutV1({destinationAmount: localAmount});
    }

    // ========= ENABLER FUNCTIONS ========= //

    /// @inheritdoc PeripheryEnabler
    /// @dev        No custom logic required
    function _enable(bytes calldata) internal virtual override {}

    /// @inheritdoc PeripheryEnabler
    /// @dev        No custom logic required
    function _disable(bytes calldata) internal virtual override {}

    /// @inheritdoc PeripheryEnabler
    /// @dev        Reverts if the caller is not the owner set by {Ownable2Step}
    function _onlyOwner() internal view virtual override {
        if (owner() != msg.sender) revert OnlyCallableByOwner();
    }

    // ========= ICCIPTokenPool ========= //

    /// @inheritdoc ICCIPTokenPool
    /// @dev        The bridged supply is equivalent to the balance of the token in the contract.
    function getBridgedSupply() external view returns (uint256) {
        return i_token.balanceOf(address(this));
    }
}
