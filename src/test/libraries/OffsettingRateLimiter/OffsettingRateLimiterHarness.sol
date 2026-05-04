// SPDX-License-Identifier: MIT
pragma solidity >=0.8.18;

// Interfaces
import {IOffsettingRateLimiter} from "src/interfaces/IOffsettingRateLimiter.sol";

// Contracts
import {OffsettingRateLimiter} from "src/libraries/OffsettingRateLimiter.sol";

/// @notice Test harness exposing every internal function of `OffsettingRateLimiter` as
///         an external pass-through with no extra logic. Intended for unit, fuzz
///         and invariant tests.
contract OffsettingRateLimiterHarness is OffsettingRateLimiter {
    function setOutRateLimits(IOffsettingRateLimiter.RateLimitConfig[] memory configs_) external {
        _setOutRateLimits(configs_);
    }

    function setInRateLimits(IOffsettingRateLimiter.RateLimitConfig[] memory configs_) external {
        _setInRateLimits(configs_);
    }

    function clearOutboundInFlight(uint32[] memory eids_) external {
        _clearOutboundInFlight(eids_);
    }

    function clearInboundInFlight(uint32[] memory eids_) external {
        _clearInboundInFlight(eids_);
    }

    function outflow(uint32 dstEid_, uint256 amount_) external {
        _outflow(dstEid_, amount_);
    }

    function inflow(uint32 srcEid_, uint256 amount_) external {
        _inflow(srcEid_, amount_);
    }

    function currentState(
        uint256 inFlight_,
        uint256 limit_,
        uint32 window_,
        uint48 lastUpdated_
    ) external view returns (uint256 inFlight, uint256 available) {
        return _currentState(inFlight_, limit_, window_, lastUpdated_);
    }
}
