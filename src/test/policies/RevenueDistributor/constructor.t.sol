// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Kernel} from "src/Kernel.sol";
import {RevenueDistributorHarness} from "./fixtures/RevenueDistributorHarness.sol";

import {Test} from "@forge-std-1.16.2/Test.sol";

contract RevenueDistributorConstructorTest is Test {
    uint32 private constant DEFAULT_GRACE_PERIOD = 7 days;

    // Scenarios: RD-CTOR-P01
    function test_whenConstructedWithKernel_initializesDefaults() public {
        Kernel kernel = new Kernel();
        RevenueDistributorHarness distributor = new RevenueDistributorHarness(kernel);

        assertEq(address(distributor.kernel()), address(kernel), "Kernel pointer equals input");
        assertFalse(distributor.isEnabled(), "distributor starts disabled");
        assertEq(
            distributor.gracePeriod(),
            DEFAULT_GRACE_PERIOD,
            "grace period starts at seven days"
        );
        assertEq(distributor.lastTransitionAt(), 0, "transition timestamp starts at zero");
        assertEq(distributor.configOperator(), address(0), "config operator starts unset");
        assertEq(distributor.getActiveAssets().length, 0, "active asset set starts empty");
        assertEq(distributor.getPendingPayoutAssets().length, 0, "pending asset set starts empty");
    }

    // Scenarios: RD-CTOR-P02
    function test_whenConstructedWithZeroKernel_preservesZeroPointer() public {
        RevenueDistributorHarness distributor = new RevenueDistributorHarness(Kernel(address(0)));

        assertEq(address(distributor.kernel()), address(0), "zero Kernel pointer is preserved");
        assertFalse(distributor.isEnabled(), "zero-Kernel distributor starts disabled");
        assertEq(distributor.gracePeriod(), DEFAULT_GRACE_PERIOD, "grace period still initializes");
        assertEq(distributor.lastTransitionAt(), 0, "transition timestamp starts at zero");
        assertEq(distributor.configOperator(), address(0), "config operator starts unset");
    }
}
