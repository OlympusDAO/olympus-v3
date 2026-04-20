// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable, unwrapped-modifier-logic)
pragma solidity >=0.8.15;

import {ChainlinkOracleFactoryTest} from "../ChainlinkOracleFactory/ChainlinkOracleFactoryTest.sol";
import {IChainlinkOracle} from "src/policies/interfaces/price/IChainlinkOracle.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";

/// @notice Parent test contract for ChainlinkOracleCloneable tests
/// @dev    Provides setup, helper functions, and modifiers for all cloneable oracle test files
contract ChainlinkOracleCloneableTest is ChainlinkOracleFactoryTest {
    // ========== STATE ========== //

    IChainlinkOracle public oracle;

    uint48 public lastStoredTimestamp;
    uint80 public lastStoredRoundId;

    // ========== SETUP ========== //

    function setUp() public virtual override {
        super.setUp();

        // Enable factory
        _enableFactory();

        vm.warp(1000);

        // Create oracle
        oracle = IChainlinkOracle(
            _createOracle(address(baseToken), address(quoteToken), DEFAULT_MAX_AGE)
        );
    }

    function _storePrices() internal {
        priceModule.cachePrice(address(baseToken), address(quoteToken));
        (, lastStoredTimestamp) = priceModule.getPriceIn(
            address(baseToken),
            address(quoteToken),
            IPRICEv2.Variant.LAST
        );
        (, , , lastStoredRoundId) = priceModule.getCachedPrice(
            address(baseToken),
            address(quoteToken)
        );
    }

    function _warp() internal {
        vm.warp(block.timestamp + 1);
    }

    modifier givenPricesAreStored() {
        _storePrices();
        _;
    }

    modifier warp() {
        _warp();
        _;
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable, unwrapped-modifier-logic)
