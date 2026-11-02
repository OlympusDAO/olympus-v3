// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;
import {MockPriceCache} from "src/test/mocks/MockPriceCache.sol";

/// @dev One-shot price-refresh callback; STATICCALL quotes cannot invoke it.
contract BurnerLoansCallbackCache is MockPriceCache {
    address internal _target;
    bytes internal _data;
    bool internal _armed;
    bool internal _propagate;
    bytes public rejection;

    constructor(address kernel_) MockPriceCache(kernel_) {}

    function arm(address target_, bytes memory data_, bool propagate_) external {
        _target = target_;
        _data = data_;
        _armed = true;
        _propagate = propagate_;
    }

    function cachePriceIfNecessary(
        address asset_,
        address quote_,
        uint48 maxAge_
    ) public override returns (CachedPrice memory) {
        if (_armed) {
            _armed = false;
            (bool success, bytes memory result) = _target.call(_data);
            if (!success) {
                rejection = result;
                if (_propagate)
                    assembly ("memory-safe") {
                        revert(add(result, 32), mload(result))
                    }
            }
        }
        return super.cachePriceIfNecessary(asset_, quote_, maxAge_);
    }
}
