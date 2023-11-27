// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import {IBasePool} from "src/libraries/Balancer/interfaces/IBasePool.sol";
import {IWeightedPool} from "src/libraries/Balancer/interfaces/IWeightedPool.sol";
import {IStablePool} from "src/libraries/Balancer/interfaces/IStablePool.sol";

contract MockBalancerPool is IBasePool {
    bytes32 internal _poolId;
    uint256 internal _totalSupply;
    uint8 internal _decimals;

    function setPoolId(bytes32 poolId_) public {
        _poolId = poolId_;
    }

    function setTotalSupply(uint256 totalSupply_) public {
        _totalSupply = totalSupply_;
    }

    function setDecimals(uint8 decimals_) public {
        _decimals = decimals_;
    }

    function getPoolId() external view override returns (bytes32) {
        return _poolId;
    }

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }
}

contract MockBalancerWeightedPool is IWeightedPool, MockBalancerPool {
    uint256[] internal _normalizedWeights;
    uint256 internal _invariant;

    function setNormalizedWeights(uint256[] memory weights_) public {
        _normalizedWeights = weights_;
    }

    function getNormalizedWeights() external view override returns (uint256[] memory) {
        return _normalizedWeights;
    }

    function setInvariant(uint256 invariant_) public {
        _invariant = invariant_;
    }

    function getInvariant() external view override returns (uint256) {
        return _invariant;
    }
}

contract MockBalancerStablePool is IStablePool, MockBalancerPool {
    uint256 private _invariant;
    uint256 private _ampFactor;
    uint256 private _rate;
    uint256[] private _scalingFactors;

    function setLastInvariant(uint256 invariant_, uint256 ampFactor_) public {
        _invariant = invariant_;
        _ampFactor = ampFactor_;
    }

    function getLastInvariant() external view override returns (uint256, uint256) {
        return (_invariant, _ampFactor);
    }

    function setRate(uint256 rate_) public {
        _rate = rate_;
    }

    function getRate() external view override returns (uint256) {
        return (_rate);
    }

    function setScalingFactors(uint256[] memory scalingFactors_) public {
        _scalingFactors = scalingFactors_;
    }

    function getScalingFactors() external view override returns (uint256[] memory) {
        return _scalingFactors;
    }
}

/// @notice         Barebones implementation of the Balancer Composable Stable Pool
/// @dev            Original: https://github.com/balancer/balancer-v2-monorepo/blob/c4cc3d466eaa3c1e5fa62d303208c6c4a10db48a/pkg/pool-stable/contracts/ComposableStablePool.sol#L4
contract MockBalancerComposableStablePool is MockBalancerPool {
    uint256 private _rate;
    uint256[] private _scalingFactors;
    uint256 private _actualSupply;

    function setRate(uint256 rate_) public {
        _rate = rate_;
    }

    function getRate() external view returns (uint256) {
        return (_rate);
    }

    function setScalingFactors(uint256[] memory scalingFactors_) public {
        _scalingFactors = scalingFactors_;
    }

    function getScalingFactors() external view returns (uint256[] memory) {
        return _scalingFactors;
    }

    function setActualSupply(uint256 actualSupply_) public {
        _actualSupply = actualSupply_;
    }

    function getActualSupply() external view returns (uint256) {
        return _actualSupply;
    }
}
