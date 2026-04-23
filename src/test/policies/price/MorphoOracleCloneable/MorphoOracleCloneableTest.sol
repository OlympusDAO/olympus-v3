// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable, unwrapped-modifier-logic)
pragma solidity >=0.8.15;

import {MorphoOracleFactoryTest} from "../MorphoOracleFactory/MorphoOracleFactoryTest.sol";
import {IMorphoOracle} from "src/policies/interfaces/price/IMorphoOracle.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";

/// @notice Parent test contract for MorphoOracleCloneable tests
/// @dev    Provides setup, helper functions, and modifiers for all cloneable oracle test files
contract MorphoOracleCloneableTest is MorphoOracleFactoryTest {
    // ========== STATE ========== //

    IMorphoOracle public oracle;
    bytes4 internal _PRICE_ASSET_NOT_APPROVED_SELECTOR = IPRICEv2.PRICE_AssetNotApproved.selector;

    // ========== SETUP ========== //

    function setUp() public virtual override {
        super.setUp();

        // Enable factory
        _enableFactory();

        // Create oracle
        oracle = IMorphoOracle(
            _createOracle(address(collateralToken), address(loanToken), DEFAULT_MAX_AGE)
        );
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable, unwrapped-modifier-logic)
