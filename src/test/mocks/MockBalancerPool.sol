// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import {IBasePool, IWeightedPool, IStablePool} from "src/modules/PRICE/submodules/feeds/BalancerPoolTokenPrice.sol";

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
}
