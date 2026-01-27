// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

// Test
import {Test} from "@forge-std-1.9.6/Test.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";

// Mocks
import {MockPrice} from "test/mocks/MockPrice.v2.sol";

// Libraries
import {FullMath} from "libraries/FullMath.sol";
import {Math} from "libraries/Balancer/math/Math.sol";
import {QuickSort} from "libraries/QuickSort.sol";

// Bophades
import {Kernel} from "src/Kernel.sol";
import {SimplePriceFeedStrategy} from "modules/PRICE/submodules/strategies/SimplePriceFeedStrategy.sol";
import {ISimplePriceFeedStrategy} from "modules/PRICE/submodules/strategies/ISimplePriceFeedStrategy.sol";

/// @title Base test contract for SimplePriceFeedStrategy
/// @notice Contains shared setup, helpers, and common test infrastructure
abstract contract SimplePriceFeedStrategyBase is Test {
    using ModuleTestFixtureGenerator for SimplePriceFeedStrategy;
    using Math for uint256;
    using FullMath for uint256;
    using QuickSort for uint256[];

    MockPrice internal mockPrice;
    SimplePriceFeedStrategy internal strategy;

    uint8 internal constant PRICE_DECIMALS = 18;
    uint256 internal constant DEVIATION_MIN = 0;
    uint256 internal constant DEVIATION_MAX = 10_000;

    function setUp() public virtual {
        Kernel kernel = new Kernel();
        mockPrice = new MockPrice(kernel, uint8(18), uint32(8 hours));
        mockPrice.setTimestamp(uint48(block.timestamp));
        mockPrice.setPriceDecimals(PRICE_DECIMALS);

        strategy = new SimplePriceFeedStrategy(mockPrice);
    }

    // =========  HELPER METHODS ========= //

    function _encodeDeviationParams(
        uint256 deviationBps
    ) internal pure returns (bytes memory params) {
        return abi.encode(deviationBps);
    }

    function _encodeDeviationParams(
        uint16 deviationBps,
        bool revertOnInsufficientCount
    ) internal pure returns (bytes memory params) {
        ISimplePriceFeedStrategy.DeviationParams memory p = ISimplePriceFeedStrategy
            .DeviationParams({
                deviationBps: deviationBps,
                revertOnInsufficientCount: revertOnInsufficientCount
            });
        return abi.encode(p);
    }

    function _encodeStrictModeParams(bool strictMode_) internal pure returns (bytes memory) {
        return abi.encode(strictMode_);
    }

    function _expectRevertParams(bytes memory params_) internal {
        bytes memory err = abi.encodeWithSelector(
            SimplePriceFeedStrategy.SimpleStrategy_ParamsInvalid.selector,
            params_
        );
        vm.expectRevert(err);
    }

    function _expectRevertPriceCount(uint256 pricesLen_, uint256 minPricesLen_) internal {
        bytes memory err = abi.encodeWithSelector(
            SimplePriceFeedStrategy.SimpleStrategy_PriceCountInvalid.selector,
            pricesLen_,
            minPricesLen_
        );
        vm.expectRevert(err);
    }

    /// @notice              Indicates whether the supplied values are deviating
    /// @param deviationBps_ The deviation in basis points, where 0 = 0% and 10_000 = 100%
    function _isDeviating(
        uint256 valueOne_,
        uint256 referenceValue_,
        uint256 deviationBps_
    ) internal pure returns (bool) {
        uint256 largerValue = valueOne_.max(referenceValue_);
        uint256 smallerValue = valueOne_.min(referenceValue_);

        // 10_000 = 100%
        uint256 deviationBase = 10_000;

        return (largerValue - smallerValue).mulDiv(deviationBase, referenceValue_) > deviationBps_;
    }
}
