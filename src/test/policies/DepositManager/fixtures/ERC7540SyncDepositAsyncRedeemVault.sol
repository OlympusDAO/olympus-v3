// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

// Interfaces
import {IERC20} from "@openzeppelin-5.7.0/token/ERC20/IERC20.sol";

// Contracts
import {ERC20} from "@openzeppelin-5.7.0/token/ERC20/ERC20.sol";
import {ERC7540} from "@openzeppelin-community-contracts-0.0.1/token/ERC20/extensions/ERC7540.sol";
import {ERC7540AdminRedeem} from "@openzeppelin-community-contracts-0.0.1/token/ERC20/extensions/ERC7540AdminRedeem.sol";
import {ERC7540SyncDeposit} from "@openzeppelin-community-contracts-0.0.1/token/ERC20/extensions/ERC7540SyncDeposit.sol";

/// @notice Concrete OpenZeppelin Community ERC-7540 synchronous-deposit/async-redeem fixture.
/// @dev Interoperability fixture only. OpenZeppelin Community Contracts is experimental and is not
///      a production dependency or endorsement for protocol use.
contract ERC7540SyncDepositAsyncRedeemVault is ERC7540SyncDeposit, ERC7540AdminRedeem {
    constructor(IERC20 asset_) ERC20("Community Vault Share", "CVS") ERC7540(asset_) {}

    function _requestRedeem(
        uint256 shares_,
        address controller_,
        address owner_,
        uint256 requestId_
    ) internal virtual override(ERC7540, ERC7540AdminRedeem) returns (uint256) {
        return super._requestRedeem(shares_, controller_, owner_, requestId_);
    }
}
