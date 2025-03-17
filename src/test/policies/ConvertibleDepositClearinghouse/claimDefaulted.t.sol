// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {ConvertibleDepositClearinghouseTest} from "./ConvertibleDepositClearinghouseTest.sol";

import {Actions} from "src/Kernel.sol";
import {IGenericClearinghouse} from "src/policies/interfaces/IGenericClearinghouse.sol";
import {CDClearinghouse} from "src/policies/CDClearinghouse.sol";
import {CoolerCallback} from "src/external/cooler/CoolerCallback.sol";
import {CoolerFactory} from "src/external/cooler/CoolerFactory.sol";
import {ICooler} from "src/external/cooler/interfaces/ICooler.sol";

contract ClaimDefaultedCDClearinghouseTest is ConvertibleDepositClearinghouseTest {
    // when the cooler and loans arrays are of different lengths
    //  [X] it reverts
    // given any cooler was not issued by the factory
    //  [X] it reverts
    // given any loan was not issued by the Clearinghouse
    //  [X] it reverts
    // given the Clearinghouse is not enabled
    //  [X] it succeeds
    // given the keeper reward for a loan is greater than maxRewardPerLoan
    //  [X] it caps the keeper reward for a loan to maxRewardPerLoan
    // given the time since expiry is less than 7 days
    //  [X] the keeper reward is proportional to the time since expiry
    // [X] the loans are repaid
    // [X] the collateral is burned
    // [X] the debt on CDEPO is manually reduced
    // [X] the keeper receives 5% of the collateral
    // [X] the principal receivables are decremented
    // [X] the interest receivables are decremented

    function test_arrayLengthsMismatch_reverts() public {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(IGenericClearinghouse.LengthDiscrepancy.selector));

        // Prepare inputs
        address[] memory coolers = new address[](1);
        coolers[0] = address(cooler);
        uint256[] memory loans = new uint256[](2);
        loans[0] = 0;
        loans[1] = 1;

        // Call function
        clearinghouse.claimDefaulted(coolers, loans);
    }

    function test_coolerNotFromFactory_reverts() public givenUserHasCollateral(4e18) {
        CoolerFactory maliciousFactory = new CoolerFactory();
        vm.prank(USER);
        ICooler newCooler = ICooler(maliciousFactory.generateCooler(cdToken, vault));

        // Set up a new Clearinghouse
        CDClearinghouse newClearinghouse = new CDClearinghouse(
            address(vault),
            address(maliciousFactory),
            address(kernel),
            0,
            121 days,
            1e18,
            1e18
        );
        vm.prank(EXECUTOR);
        kernel.executeAction(Actions.ActivatePolicy, address(newClearinghouse));
        vm.prank(ADMIN);
        newClearinghouse.enable("");
        vm.label(address(newClearinghouse), "newClearinghouse");

        // Take a loan from the new Clearinghouse
        vm.startPrank(USER);
        cdToken.approve(address(newClearinghouse), 2e18);
        newClearinghouse.lendToCooler(newCooler, 1e18);
        vm.stopPrank();

        // Prepare inputs
        address[] memory coolers = new address[](1);
        coolers[0] = address(newCooler);
        uint256[] memory loans = new uint256[](1);
        loans[0] = 0;

        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(CoolerCallback.OnlyFromFactory.selector));

        // Call function
        vm.prank(USER);
        clearinghouse.claimDefaulted(coolers, loans);
    }

    function test_notFromClearinghouse_reverts()
        public
        givenUserHasCollateral(4e18)
        givenUserHasApprovedDebtSpendingToClearinghouse(1e18)
    {
        // Set up a new Clearinghouse
        CDClearinghouse newClearinghouse = new CDClearinghouse(
            address(vault),
            address(coolerFactory),
            address(kernel),
            0,
            121 days,
            1e18,
            1e18
        );
        vm.prank(EXECUTOR);
        kernel.executeAction(Actions.ActivatePolicy, address(newClearinghouse));
        vm.prank(ADMIN);
        newClearinghouse.enable("");
        vm.label(address(newClearinghouse), "newClearinghouse");

        // Take a loan from the new Clearinghouse
        vm.startPrank(USER);
        cdToken.approve(address(newClearinghouse), 2e18);
        newClearinghouse.lendToCooler(cooler, 1e18);
        vm.stopPrank();

        // Prepare inputs
        address[] memory coolers = new address[](1);
        coolers[0] = address(cooler);
        uint256[] memory loans = new uint256[](1);
        loans[0] = 0;

        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(IGenericClearinghouse.NotLender.selector));

        // Call function
        vm.prank(USER);
        clearinghouse.claimDefaulted(coolers, loans);
    }

    function test_elapsedGreaterThan7Days(
        uint256 elapsed_
    )
        public
        givenUserHasApprovedCollateralSpending(8e18)
        givenUserHasCollateral(8e18)
        givenUserHasDebt(1e18)
        givenUserHasDebt(1e18)
        givenUserHasApprovedDebtSpendingToClearinghouse(2e18)
    {
        // Warp to beyond the expiry
        ICooler.Loan memory loanZero = cooler.getLoan(0);
        ICooler.Loan memory loanOne = cooler.getLoan(1);
        uint256 expiry = loanZero.expiry;
        uint256 elapsed = bound(elapsed_, expiry + 7 days, expiry + 100 days);
        vm.warp(elapsed);

        // Prepare inputs
        address[] memory coolers = new address[](2);
        coolers[0] = address(cooler);
        coolers[1] = address(cooler);
        uint256[] memory loans = new uint256[](2);
        loans[0] = 0;
        loans[1] = 1;

        uint256 cdepoTotalSupply = cdToken.totalSupply();
        uint256 expectedUserCDEPOBalance = cdToken.balanceOf(USER);

        uint256 keeperRewardZero = (loanZero.collateral * 5e16) / 1e18;
        uint256 keeperRewardOne = (loanOne.collateral * 5e16) / 1e18;

        // Call function
        clearinghouse.claimDefaulted(coolers, loans);

        // Assertions
        // Loan
        assertEq(cooler.getLoan(0).principal, 0, "principal");
        assertEq(cooler.getLoan(0).interestDue, 0, "interestDue");
        assertEq(cooler.getLoan(0).collateral, 0, "collateral");
        assertEq(cooler.getLoan(0).expiry, expiry, "expiry");

        // Receivables
        assertEq(clearinghouse.interestReceivables(), 0, "interestReceivables");
        assertEq(clearinghouse.principalReceivables(), 0, "principalReceivables");

        // Collateral
        assertEq(cdToken.balanceOf(address(clearinghouse)), 0, "clearinghouse collateral");
        assertEq(cdToken.balanceOf(address(cooler)), 0, "cooler collateral");
        assertEq(
            cdToken.balanceOf(address(this)),
            keeperRewardZero + keeperRewardOne,
            "keeper collateral"
        );
        assertEq(cdToken.balanceOf(USER), expectedUserCDEPOBalance, "USER collateral");

        // CDEPO
        assertEq(
            cdToken.totalSupply(),
            cdepoTotalSupply -
                loanZero.collateral -
                loanOne.collateral +
                keeperRewardZero +
                keeperRewardOne,
            "CDEPO total supply"
        );

        // Debt
        assertEq(CDEPO.debt(iAsset, address(clearinghouse)), 0, "CDEPO debt");
    }

    function test_elapsedLessThan7Days(
        uint256 elapsed_
    )
        public
        givenUserHasApprovedCollateralSpending(8e18)
        givenUserHasCollateral(8e18)
        givenUserHasDebt(1e18)
        givenUserHasDebt(1e18)
        givenUserHasApprovedDebtSpendingToClearinghouse(2e18)
    {
        // Warp to beyond the expiry
        ICooler.Loan memory loanZero = cooler.getLoan(0);
        ICooler.Loan memory loanOne = cooler.getLoan(1);
        uint256 expiry = loanZero.expiry;
        uint256 elapsed = bound(elapsed_, expiry + 1, expiry + 7 days - 1);
        vm.warp(elapsed);

        // Prepare inputs
        address[] memory coolers = new address[](2);
        coolers[0] = address(cooler);
        coolers[1] = address(cooler);
        uint256[] memory loans = new uint256[](2);
        loans[0] = 0;
        loans[1] = 1;

        uint256 cdepoTotalSupply = cdToken.totalSupply();
        uint256 expectedUserCDEPOBalance = cdToken.balanceOf(USER);

        uint256 keeperRewardZero = (((loanZero.collateral * 5e16) / 1e18) * (elapsed - expiry)) /
            7 days;
        uint256 keeperRewardOne = (((loanOne.collateral * 5e16) / 1e18) * (elapsed - expiry)) /
            7 days;

        // Call function
        clearinghouse.claimDefaulted(coolers, loans);

        // Assertions
        // Loan
        assertEq(cooler.getLoan(0).principal, 0, "principal");
        assertEq(cooler.getLoan(0).interestDue, 0, "interestDue");
        assertEq(cooler.getLoan(0).collateral, 0, "collateral");
        assertEq(cooler.getLoan(0).expiry, expiry, "expiry");

        // Receivables
        assertEq(clearinghouse.interestReceivables(), 0, "interestReceivables");
        assertEq(clearinghouse.principalReceivables(), 0, "principalReceivables");

        // Collateral
        assertEq(cdToken.balanceOf(address(clearinghouse)), 0, "clearinghouse collateral");
        assertEq(cdToken.balanceOf(address(cooler)), 0, "cooler collateral");
        assertEq(
            cdToken.balanceOf(address(this)),
            keeperRewardZero + keeperRewardOne,
            "keeper collateral"
        );
        assertEq(cdToken.balanceOf(USER), expectedUserCDEPOBalance, "USER collateral");

        // CDEPO
        assertEq(
            cdToken.totalSupply(),
            cdepoTotalSupply -
                loanZero.collateral -
                loanOne.collateral +
                keeperRewardZero +
                keeperRewardOne,
            "CDEPO total supply"
        );

        // Debt
        assertEq(CDEPO.debt(iAsset, address(clearinghouse)), 0, "CDEPO debt");
    }

    function test_exceedsMaxReward()
        public
        givenUserHasApprovedCollateralSpending(8e18)
        givenUserHasCollateral(8e18)
        givenUserHasDebt(1e18)
        givenUserHasDebt(1e18)
        givenUserHasApprovedDebtSpendingToClearinghouse(2e18)
    {
        // Warp to beyond the expiry
        ICooler.Loan memory loanZero = cooler.getLoan(0);
        ICooler.Loan memory loanOne = cooler.getLoan(1);
        uint256 expiry = loanZero.expiry;
        uint256 elapsed = expiry + 100 days;
        vm.warp(elapsed);

        // Set the max reward per loan to be lower than the keeper reward per loan
        // 5% of 2666666666666666666 = 133333333333333333
        vm.prank(ADMIN);
        clearinghouse.setMaxRewardPerLoan(1e17);

        // Prepare inputs
        address[] memory coolers = new address[](2);
        coolers[0] = address(cooler);
        coolers[1] = address(cooler);
        uint256[] memory loans = new uint256[](2);
        loans[0] = 0;
        loans[1] = 1;

        uint256 cdepoTotalSupply = cdToken.totalSupply();
        uint256 expectedUserCDEPOBalance = cdToken.balanceOf(USER);

        uint256 keeperRewardZero = 1e17;
        uint256 keeperRewardOne = 1e17;

        // Call function
        clearinghouse.claimDefaulted(coolers, loans);

        // Assertions
        // Loan
        assertEq(cooler.getLoan(0).principal, 0, "principal");
        assertEq(cooler.getLoan(0).interestDue, 0, "interestDue");
        assertEq(cooler.getLoan(0).collateral, 0, "collateral");
        assertEq(cooler.getLoan(0).expiry, expiry, "expiry");

        // Receivables
        assertEq(clearinghouse.interestReceivables(), 0, "interestReceivables");
        assertEq(clearinghouse.principalReceivables(), 0, "principalReceivables");

        // Collateral
        assertEq(cdToken.balanceOf(address(clearinghouse)), 0, "clearinghouse collateral");
        assertEq(cdToken.balanceOf(address(cooler)), 0, "cooler collateral");
        assertEq(
            cdToken.balanceOf(address(this)),
            keeperRewardZero + keeperRewardOne,
            "keeper collateral"
        );
        assertEq(cdToken.balanceOf(USER), expectedUserCDEPOBalance, "USER collateral");

        // CDEPO
        assertEq(
            cdToken.totalSupply(),
            cdepoTotalSupply -
                loanZero.collateral -
                loanOne.collateral +
                keeperRewardZero +
                keeperRewardOne,
            "CDEPO total supply"
        );

        // Debt
        assertEq(CDEPO.debt(iAsset, address(clearinghouse)), 0, "CDEPO debt");
    }

    function test_givenDisabled()
        public
        givenUserHasApprovedCollateralSpending(8e18)
        givenUserHasCollateral(8e18)
        givenUserHasDebt(1e18)
        givenUserHasDebt(1e18)
        givenUserHasApprovedDebtSpendingToClearinghouse(2e18)
        givenDisabled
    {
        // Warp to beyond the expiry
        ICooler.Loan memory loanZero = cooler.getLoan(0);
        ICooler.Loan memory loanOne = cooler.getLoan(1);
        uint256 expiry = loanZero.expiry;
        uint256 elapsed = expiry + 7 days;
        vm.warp(elapsed);

        // Prepare inputs
        address[] memory coolers = new address[](2);
        coolers[0] = address(cooler);
        coolers[1] = address(cooler);
        uint256[] memory loans = new uint256[](2);
        loans[0] = 0;
        loans[1] = 1;

        uint256 cdepoTotalSupply = cdToken.totalSupply();
        uint256 expectedUserCDEPOBalance = cdToken.balanceOf(USER);

        uint256 keeperRewardZero = ((loanZero.collateral * 5e16) / 1e18);
        uint256 keeperRewardOne = ((loanOne.collateral * 5e16) / 1e18);

        // Call function
        clearinghouse.claimDefaulted(coolers, loans);

        // Assertions
        // Loan
        assertEq(cooler.getLoan(0).principal, 0, "principal");
        assertEq(cooler.getLoan(0).interestDue, 0, "interestDue");
        assertEq(cooler.getLoan(0).collateral, 0, "collateral");
        assertEq(cooler.getLoan(0).expiry, expiry, "expiry");

        // Receivables
        assertEq(clearinghouse.interestReceivables(), 0, "interestReceivables");
        assertEq(clearinghouse.principalReceivables(), 0, "principalReceivables");

        // Collateral
        assertEq(cdToken.balanceOf(address(clearinghouse)), 0, "clearinghouse collateral");
        assertEq(cdToken.balanceOf(address(cooler)), 0, "cooler collateral");
        assertEq(
            cdToken.balanceOf(address(this)),
            keeperRewardZero + keeperRewardOne,
            "keeper collateral"
        );
        assertEq(cdToken.balanceOf(USER), expectedUserCDEPOBalance, "USER collateral");

        // CDEPO
        assertEq(
            cdToken.totalSupply(),
            cdepoTotalSupply -
                loanZero.collateral -
                loanOne.collateral +
                keeperRewardZero +
                keeperRewardOne,
            "CDEPO total supply"
        );

        // Debt
        assertEq(CDEPO.debt(iAsset, address(clearinghouse)), 0, "CDEPO debt");
    }
}
