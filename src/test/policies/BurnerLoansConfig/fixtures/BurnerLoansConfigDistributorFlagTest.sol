// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Contracts
import {BurnerLoansDistributorConfigTest} from "src/test/policies/BurnerLoans/fixtures/BurnerLoansDistributorConfigTest.sol";

abstract contract BurnerLoansConfigDistributorFlagTest is BurnerLoansDistributorConfigTest {
    address internal configOperator;

    function setUp() public virtual override {
        super.setUp();
        configOperator = makeAddr("configOperator");
        _setConfigOperator(configOperator);
    }

    function _permittedCaller(bool useAdmin_) internal view returns (address) {
        return useAdmin_ ? admin : configOperator;
    }
}
