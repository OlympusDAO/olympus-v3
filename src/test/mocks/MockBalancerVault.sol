// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import {IVault} from "src/libraries/Balancer/interfaces/IVault.sol";
import {BalancerReentrancyGuard} from "src/libraries/Balancer/contracts/BalancerReentrancyGuard.sol";

contract MockBalancerVault is IVault, BalancerReentrancyGuard {
    address[] internal tokens;
    uint256[] internal balances;
    uint256 internal lastChangeBlock;

    function setTokens(address[] memory _tokens) public {
        tokens = _tokens;
    }

    function setBalances(uint256[] memory _balances) public {
        balances = _balances;
    }

    function setLastChangeBlock(uint256 _lastChangeBlock) public {
        lastChangeBlock = _lastChangeBlock;
    }

    function getPoolTokens(
        bytes32
    ) external view override returns (address[] memory, uint256[] memory, uint256) {
        return (tokens, balances, lastChangeBlock);
    }

    function manageUserBalance(UserBalanceOp[] memory ops) external payable override nonReentrant {
        // Implementation not required
    }
}

contract MockMultiplePoolBalancerVault is IVault, BalancerReentrancyGuard {
    mapping(bytes32 => address[]) internal tokens;
    mapping(bytes32 => uint256[]) internal balances;
    mapping(bytes32 => uint256) internal lastChangeBlock;

    function setTokens(bytes32 poolId, address[] memory _tokens) public {
        tokens[poolId] = _tokens;
    }

    function setBalances(bytes32 poolId, uint256[] memory _balances) public {
        balances[poolId] = _balances;
    }

    function setLastChangeBlock(bytes32 poolId, uint256 _lastChangeBlock) public {
        lastChangeBlock[poolId] = _lastChangeBlock;
    }

    function getPoolTokens(
        bytes32 poolId
    ) external view override returns (address[] memory, uint256[] memory, uint256) {
        return (tokens[poolId], balances[poolId], lastChangeBlock[poolId]);
    }

    function manageUserBalance(UserBalanceOp[] memory ops) external payable override nonReentrant {
        // Implementation not required
    }
}
