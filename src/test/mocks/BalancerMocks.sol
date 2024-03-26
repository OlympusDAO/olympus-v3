// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.0;

import {MockERC20, ERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {JoinPoolRequest, ExitPoolRequest} from "policies/BoostedLiquidity/interfaces/IBalancer.sol";

// Define Mock Balancer Vault
contract MockVault {
    MockERC20 public bpt;
    address public token0;
    address public token1;
    uint256 public token0Amount;
    uint256 public token1Amount;

    constructor(address bpt_, address token0_, address token1_) {
        bpt = MockERC20(bpt_);
        token0 = token0_;
        token1 = token1_;
    }

    function joinPool(
        bytes32 poolId,
        address sender,
        address recipient,
        JoinPoolRequest calldata request
    ) external virtual {
        ERC20(request.assets[0]).transferFrom(sender, address(this), request.maxAmountsIn[0]);
        ERC20(request.assets[1]).transferFrom(sender, address(this), request.maxAmountsIn[1]);
        bpt.mint(recipient, request.maxAmountsIn[1]);
    }

    function exitPool(
        bytes32 poolId,
        address sender,
        address recipient,
        ExitPoolRequest calldata request
    ) external virtual {
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

    function getPoolTokens(
        bytes32 poolId
    ) external view returns (address[] memory, uint256[] memory, uint256) {
        address[] memory tokens = new address[](2);
        tokens[0] = token0;
        tokens[1] = token1;

        uint256[] memory balances = new uint256[](2);
        balances[0] = token0Amount;
        balances[1] = token1Amount;

        return (tokens, balances, block.timestamp);
    }

    function setPoolAmounts(uint256 token0Amount_, uint256 token1Amount_) external {
        token0Amount = token0Amount_;
        token1Amount = token1Amount_;
    }
}

/// @notice     Mock Balancer Vault with fixed BPT amount
contract MockBalancerVault is MockVault {
    uint256 public _bptMultiplier;

    constructor(
        address bpt_,
        address token0_,
        address token1_,
        uint256 bptMultiplier_
    ) MockVault(bpt_, token0_, token1_) {
        _bptMultiplier = bptMultiplier_;
    }

    /// @dev    Calculate BPT amount based on token amounts
    ///         This ensures that if the inputs change, the resulting number also changes
    function _calculateBptOut(
        uint256 token0Amount_,
        uint256 token1Amount_
    ) internal view returns (uint256) {
        return (token0Amount_ * _bptMultiplier) + (token1Amount_ * _bptMultiplier);
    }

    function joinPool(
        bytes32 poolId,
        address sender,
        address recipient,
        JoinPoolRequest calldata request
    ) external override {
        ERC20(request.assets[0]).transferFrom(sender, address(this), request.maxAmountsIn[0]);
        ERC20(request.assets[1]).transferFrom(sender, address(this), request.maxAmountsIn[1]);
        bpt.mint(recipient, _calculateBptOut(request.maxAmountsIn[0], request.maxAmountsIn[1]));
    }

    function exitPool(
        bytes32 poolId,
        address sender,
        address recipient,
        ExitPoolRequest calldata request
    ) external override {
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

// Define Mock Balancer Pool
contract MockBalancerPool is MockERC20 {
    constructor() MockERC20("Mock Balancer Pool", "BPT", 18) {}

    function getPoolId() external pure returns (bytes32) {
        return bytes32(0);
    }

    function setTotalSupply(uint256 totalSupply_) external {
        totalSupply = totalSupply_;
    }
}
