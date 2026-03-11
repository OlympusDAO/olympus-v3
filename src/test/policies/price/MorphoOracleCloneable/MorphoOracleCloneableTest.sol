// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable, unwrapped-modifier-logic)
pragma solidity >=0.8.15;

import {MorphoOracleFactoryTest} from "../MorphoOracleFactory/MorphoOracleFactoryTest.sol";
import {IMorphoOracle} from "src/policies/interfaces/price/IMorphoOracle.sol";

/// @notice Parent test contract for MorphoOracleCloneable tests
/// @dev    Provides setup, helper functions, and modifiers for all cloneable oracle test files
contract MorphoOracleCloneableTest is MorphoOracleFactoryTest {
    // ========== STATE ========== //

    IMorphoOracle public oracle;

    // ========== SETUP ========== //

    function setUp() public virtual override {
        super.setUp();

        // Enable factory
        _enableFactory();

        // Create oracle
        oracle = IMorphoOracle(_createOracle(address(collateralToken), address(loanToken)));
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable, unwrapped-modifier-logic)
