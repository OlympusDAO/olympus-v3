// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable, unwrapped-modifier-logic)
pragma solidity >=0.8.15;

import {ChainlinkOracleFactoryTest} from "../ChainlinkOracleFactory/ChainlinkOracleFactoryTest.sol";
import {IChainlinkOracle} from "src/policies/interfaces/price/IChainlinkOracle.sol";

/// @notice Parent test contract for ChainlinkOracleCloneable tests
/// @dev    Provides setup, helper functions, and modifiers for all cloneable oracle test files
contract ChainlinkOracleCloneableTest is ChainlinkOracleFactoryTest {
    // ========== STATE ========== //

    IChainlinkOracle public oracle;

    uint48 public lastStoredTimestamp;

    // ========== SETUP ========== //

    function setUp() public virtual override {
        super.setUp();

        // Enable factory
        _enableFactory();

        vm.warp(1000);

        // Create oracle
        oracle = IChainlinkOracle(_createOracle(address(baseToken), address(quoteToken)));
    }

    function _storePrices() internal {
        priceModule.storePrice(address(baseToken));
        priceModule.storePrice(address(quoteToken));
        lastStoredTimestamp = uint48(block.timestamp);
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
