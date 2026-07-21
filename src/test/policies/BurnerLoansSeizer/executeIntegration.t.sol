// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Actions} from "src/Kernel.sol";
import {BurnerLoansSeizer} from "src/policies/BurnerLoansSeizer.sol";
import {BURNER_LOANS_SEIZER_ROLE, HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {BurnerLoansSeizureTestBase} from "src/test/policies/BurnerLoans/fixtures/BurnerLoansSeizureTestBase.sol";

contract BurnerLoansSeizerExecuteIntegrationTest is BurnerLoansSeizureTestBase {
    BurnerLoansSeizer internal seizer;
    address internal heart;

    function setUp() public override {
        super.setUp();
        heart = makeAddr("heart");

        vm.startPrank(admin);
        seizer = new BurnerLoansSeizer(kernel, address(burnerLoans), 10, 5);
        kernel.executeAction(Actions.ActivatePolicy, address(seizer));
        rolesAdmin.grantRole(HEART_ROLE, heart);
        rolesAdmin.grantRole(BURNER_LOANS_SEIZER_ROLE, address(seizer));
        seizer.addAsset(address(usds));
        vm.stopPrank();
    }

    function test_givenMaturedPosition_seizesWithoutKeeperReward() public {
        _makeMatured(alice);
        uint256 treasuryBefore = usds.balanceOf(address(trsry));

        vm.prank(heart);
        seizer.execute();

        assertEq(burnerLoans.getPosition(address(usds), alice).debtOhm, 0, "position debt");
        assertEq(
            burnerLoans.getPosition(address(usds), alice).depositedCollateral,
            0,
            "position collateral"
        );
        assertEq(burnerLoans.totalActiveDebtOhm(), 0, "global active debt");
        assertEq(burnerLoans.assetActiveDebtOhm(address(usds)), 0, "asset active debt");
        assertEq(usds.balanceOf(address(seizer)), 0, "seizer reward balance");
        assertEq(usds.balanceOf(address(trsry)), treasuryBefore + 2_000e18, "treasury collateral");
    }
}
