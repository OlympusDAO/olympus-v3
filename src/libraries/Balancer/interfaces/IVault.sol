// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import {IAsset} from "src/libraries/Balancer/interfaces/IAsset.sol";

interface IVault {
    enum UserBalanceOpKind {
        DEPOSIT_INTERNAL,
        WITHDRAW_INTERNAL,
        TRANSFER_INTERNAL,
        TRANSFER_EXTERNAL
    }

    /**
     * @dev Data for `manageUserBalance` operations, which include the possibility for ETH to be sent and received
     without manual WETH wrapping or unwrapping.
     */
    struct UserBalanceOp {
        UserBalanceOpKind kind;
        IAsset asset;
        uint256 amount;
        address sender;
        address payable recipient;
    }

    function manageUserBalance(UserBalanceOp[] memory ops) external payable;

    function getPoolTokens(
        bytes32 poolId
    )
        external
        view
        returns (address[] memory tokens, uint256[] memory balances, uint256 lastChangeBlock);
}
