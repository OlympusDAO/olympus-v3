// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable, unwrapped-modifier-logic)
pragma solidity >=0.8.15;

import {ChainlinkOracleFactoryTest} from "../ChainlinkOracleFactory/ChainlinkOracleFactoryTest.sol";
import {IChainlinkOracle} from "src/policies/interfaces/price/IChainlinkOracle.sol";
import {IPriceCache} from "src/interfaces/IPriceCache.sol";

/// @notice Parent test contract for ChainlinkOracleCloneable tests
/// @dev    Provides setup, helper functions, and modifiers for all cloneable oracle test files
contract ChainlinkOracleCloneableTest is ChainlinkOracleFactoryTest {
    // ========== STATE ========== //

    IChainlinkOracle public oracle;
    bytes4 internal constant PRICE_ASSET_NOT_APPROVED_SELECTOR =
        bytes4(keccak256("PRICE_AssetNotApproved(address)"));

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
        priceCache.cachePrice(address(baseToken), address(quoteToken));
        IPriceCache.CachedPrice memory cachedPrice = priceCache.getCachedPrice(
            address(baseToken),
            address(quoteToken)
        );
        lastStoredTimestamp = cachedPrice.updatedAt;
        lastStoredRoundId = cachedPrice.roundId;
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
