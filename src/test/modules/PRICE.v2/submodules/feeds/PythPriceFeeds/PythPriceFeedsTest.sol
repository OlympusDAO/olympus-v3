// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-variable,mixed-case-function)
pragma solidity >=0.8.0;

// Test
import {Test} from "@forge-std-1.9.6/Test.sol";
import {ModuleTestFixtureGenerator} from "src/test/lib/ModuleTestFixtureGenerator.sol";

// Mocks
import {MockPrice} from "src/test/mocks/MockPrice.v2.sol";
import {MockPyth} from "src/test/mocks/MockPyth.sol";

// Libraries
import {FullMath} from "src/libraries/FullMath.sol";

// Bophades
import {Kernel} from "src/Kernel.sol";
import {PythPriceFeeds} from "src/modules/PRICE/submodules/feeds/PythPriceFeeds.sol";

contract PythPriceFeedsTest is Test {
    using FullMath for uint256;
    using ModuleTestFixtureGenerator for PythPriceFeeds;

    MockPyth internal pyth;
    MockPyth internal secondPyth;

    Kernel internal kernel;
    MockPrice internal mockPrice;
    PythPriceFeeds internal pythSubmodule;

    bytes32 internal constant PRICE_ID_1 = keccak256("PRICE_ID_1");
    bytes32 internal constant PRICE_ID_2 = keccak256("PRICE_ID_2");
    bytes32 internal constant PRICE_ID_3 = keccak256("PRICE_ID_3");

    // Example: price=123456789, expo=-8 represents 1.23456789
    int64 internal constant PRICE_1 = 123456789;
    int32 internal constant EXPO_1 = -8;
    uint64 internal constant CONF_1 = 1000000;
    uint256 internal constant EXPECTED_PRICE_1_18_DEC = 1234567890000000000; // 1.23456789 * 10^18

    // Example: price=100000000, expo=8 represents 100000000 * 10^8
    int64 internal constant PRICE_2 = 100000000;
    int32 internal constant EXPO_2 = 8;
    uint64 internal constant CONF_2 = 2000000;

    // Example: price=500000000, expo=-18 represents 0.0000000005
    int64 internal constant PRICE_3 = 500000000;
    int32 internal constant EXPO_3 = -18;
    uint64 internal constant CONF_3 = 500000;

    uint8 internal constant PRICE_DECIMALS = 18;
    uint48 internal constant UPDATE_THRESHOLD = 100;
    // MAX_CONFIDENCE is in output decimals (18 decimals)
    // CONF_1 = 1000000 with expo=-8
    // In decimal: 1000000 * 10^-8 = 0.01
    // In output decimals (18): 0.01 * 10^18 = 10000000000000000 (1e16)
    // Set MAX_CONFIDENCE to 2e16 to allow CONF_1 but reject higher values
    uint64 internal constant MAX_CONFIDENCE = 20000000000000000; // 2 * 10^16 in 18 decimals

    function setUp() public virtual {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021

        // Set up the Pyth submodule
        {
            // Deploy kernel
            kernel = new Kernel();

            // Deploy mockPrice
            mockPrice = new MockPrice(kernel, uint8(18), uint32(8 hours));
            mockPrice.setTimestamp(uint48(block.timestamp));
            mockPrice.setPriceDecimals(PRICE_DECIMALS);

            // Deploy Pyth submodule
            pythSubmodule = new PythPriceFeeds(mockPrice);
        }

        // Set up the Pyth contracts
        {
            pyth = new MockPyth();
            secondPyth = new MockPyth();

            // With the default update threshold, these prices will NOT be stale

            // Set up price feed 1: 1.23456789 (expo=-8)
            pyth.setPrice(PRICE_ID_1, PRICE_1, CONF_1, EXPO_1, block.timestamp - UPDATE_THRESHOLD);

            // Set up price feed 2: 100000000 * 10^8 (expo=8)
            pyth.setPrice(PRICE_ID_2, PRICE_2, CONF_2, EXPO_2, block.timestamp - UPDATE_THRESHOLD);

            // Set up price feed 3: 0.0000000005 (expo=-18)
            pyth.setPrice(PRICE_ID_3, PRICE_3, CONF_3, EXPO_3, block.timestamp - UPDATE_THRESHOLD);
        }
    }

    // =========  HELPER METHODS ========= //

    function encodeOneFeedParams(
        address pyth_,
        bytes32 priceFeedId_,
        uint48 updateThreshold_,
        uint256 maxConfidence_
    ) internal pure returns (bytes memory params) {
        return abi.encode(pyth_, priceFeedId_, updateThreshold_, maxConfidence_);
    }

    function encodeTwoFeedParams(
        address firstPyth_,
        bytes32 firstPriceFeedId_,
        uint48 firstUpdateThreshold_,
        uint256 firstMaxConfidence_,
        address secondPyth_,
        bytes32 secondPriceFeedId_,
        uint48 secondUpdateThreshold_,
        uint256 secondMaxConfidence_
    ) internal pure returns (bytes memory params) {
        return
            abi.encode(
                firstPyth_,
                firstPriceFeedId_,
                firstUpdateThreshold_,
                firstMaxConfidence_,
                secondPyth_,
                secondPriceFeedId_,
                secondUpdateThreshold_,
                secondMaxConfidence_
            );
    }
}
/// forge-lint: disable-end(mixed-case-variable,mixed-case-function)
