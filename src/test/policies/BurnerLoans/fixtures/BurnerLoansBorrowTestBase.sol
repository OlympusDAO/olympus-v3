// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Actions} from "src/Kernel.sol";

import {BurnerLoansTest} from "../BurnerLoansTest.sol";
import {MinterAdminPolicy} from "./MinterAdminPolicy.sol";

abstract contract BurnerLoansBorrowTestBase is BurnerLoansTest {
    MinterAdminPolicy internal minterAdminPolicy;

    function setUp() public virtual override {
        super.setUp();
        _addDefaultUsdsAsset();
        _configurePrice(address(ohm), 10e18);

        vm.startPrank(admin);
        minterAdminPolicy = new MinterAdminPolicy(kernel);
        kernel.executeAction(Actions.ActivatePolicy, address(minterAdminPolicy));
        vm.stopPrank();
    }
}
