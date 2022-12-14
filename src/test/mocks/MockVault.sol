// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.0;

import {MockERC20, ERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {JoinPoolRequest, ExitPoolRequest} from "src/interfaces/IBalancerVault.sol";

contract MockVault {
    MockERC20 public bpt;

    constructor(address bpt_) {
        bpt = MockERC20(bpt_);
    }

    function joinPool(
        bytes32 poolId,
        address sender,
        address recipient,
        JoinPoolRequest calldata request
    ) external {
        ERC20(request.assets[0]).transferFrom(sender, address(this), request.maxAmountsIn[0]);
        ERC20(request.assets[1]).transferFrom(sender, address(this), request.maxAmountsIn[1]);
        bpt.mint(recipient, 1e18);
    }

    function exitPool(
        bytes32 poolId,
        address sender,
        address recipient,
        ExitPoolRequest calldata request
    ) external {
        (, uint256 bptAmount) = abi.decode(request.userData, (uint256, uint256));
        bpt.burn(sender, bptAmount);
        ERC20(request.assets[0]).transfer(
            recipient,
            ERC20(request.assets[0]).balanceOf(address(this))
        );
        ERC20(request.assets[1]).transfer(
            recipient,
            ERC20(request.assets[1]).balanceOf(address(this))
        );
    }
}
