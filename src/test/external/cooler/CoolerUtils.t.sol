// SPDX-License-Identifier: GLP-3.0
pragma solidity ^0.8.15;

import {Test, console2} from "forge-std/Test.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {IERC4626} from "forge-std/interfaces/IERC4626.sol";

import {IERC3156FlashBorrower} from "src/interfaces/maker-dao/IERC3156FlashBorrower.sol";
import {IERC3156FlashLender} from "src/interfaces/maker-dao/IERC3156FlashLender.sol";
import {CoolerFactory} from "src/external/cooler/CoolerFactory.sol";
import {Clearinghouse} from "src/policies/Clearinghouse.sol";
import {Cooler} from "src/external/cooler/Cooler.sol";

import {CoolerUtils} from "src/external/cooler/CoolerUtils.sol";

contract CoolerUtilsTest is Test {
    CoolerUtils public utils;

    ERC20 public gohm;
    ERC20 public dai;
    IERC4626 public sdai;

    CoolerFactory public coolerFactory;
    Clearinghouse public clearinghouse;

    address public owner;
    address public lender;
    address public collector;

    address public walletA;
    Cooler public coolerA;

    function setUp() public {
        // Mainnet Fork at current block.
        vm.createSelectFork("https://eth.llamarpc.com", 18762666);

        // Required Contracts
        coolerFactory = CoolerFactory(0x30Ce56e80aA96EbbA1E1a74bC5c0FEB5B0dB4216);
        clearinghouse = Clearinghouse(0xE6343ad0675C9b8D3f32679ae6aDbA0766A2ab4c);
        gohm = ERC20(0x0ab87046fBb341D058F17CBC4c1133F25a20a52f);
        dai = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        sdai = IERC4626(0x83F20F44975D03b1b09e64809B757c47f942BEeA);
        lender = 0x60744434d6339a6B27d73d9Eda62b6F66a0a04FA;

        owner = vm.addr(0x1);
        collector = vm.addr(0xC);

        // Deploy CoolerUtils
        utils = new CoolerUtils(
            address(gohm),
            address(sdai),
            address(dai),
            owner,
            lender,
            collector,
            0
        );

        walletA = vm.addr(0xA);

        // Fund wallets with gOHM
        deal(address(gohm), walletA, 3_333 * 1e18);

        // Ensure Clearinghouse has enough DAI
        deal(address(dai), address(clearinghouse), 18_000_000 * 1e18);

        vm.startPrank(walletA);
        // Deploy a cooler for walletA
        address coolerA_ = coolerFactory.generateCooler(gohm, dai);
        coolerA = Cooler(coolerA_);

        // Approve clearinghouse to spend gOHM
        gohm.approve(address(clearinghouse), 3_333 * 1e18);
        // Loan 0 for coolerA (collateral: 2,000 gOHM)
        (uint256 loan, ) = clearinghouse.getLoanForCollateral(2_000 * 1e18);
        clearinghouse.lendToCooler(coolerA, loan);
        // Loan 1 for coolerA (collateral: 1,000 gOHM)
        (loan, ) = clearinghouse.getLoanForCollateral(1_000 * 1e18);
        clearinghouse.lendToCooler(coolerA, loan);
        // Loan 2 for coolerA (collateral: 333 gOHM)
        (loan, ) = clearinghouse.getLoanForCollateral(333 * 1e18);
        clearinghouse.lendToCooler(coolerA, loan);
        vm.stopPrank();
    }

    // ===== MODIFIERS ===== //

    modifier givenProtocolFee(uint256 fee_) {
        vm.prank(owner);
        utils.setFeePercentage(fee_);
        _;
    }

    function _grantCallerApprovals(uint256[] memory ids) internal {
        // Will revert if there are less than 2 loans
        if (ids.length < 2) {
            return;
        }

        (, uint256 gohmApproval, uint256 totalDebtWithFee, , ) = utils.requiredApprovals(
            address(coolerA),
            ids
        );

        vm.startPrank(walletA);
        dai.approve(address(utils), totalDebtWithFee);
        gohm.approve(address(utils), gohmApproval);
        vm.stopPrank();
    }

    function _grantCallerApprovals(uint256 gOhmAmount_, uint256 daiAmount_) internal {
        vm.startPrank(walletA);
        dai.approve(address(utils), daiAmount_);
        gohm.approve(address(utils), gOhmAmount_);
        vm.stopPrank();
    }

    function _consolidate(uint256[] memory ids_) internal {
        _consolidate(ids_, 0, false);
    }

    function _consolidate(uint256[] memory ids_, uint256 useFunds_, bool sDai_) internal {
        vm.prank(walletA);
        utils.consolidateWithFlashLoan(
            address(clearinghouse),
            address(coolerA),
            ids_,
            useFunds_,
            sDai_
        );
    }

    function _getInterestDue(uint256[] memory ids_) internal view returns (uint256) {
        uint256 interestDue;

        for (uint256 i = 0; i < ids_.length; i++) {
            Cooler.Loan memory loan = coolerA.getLoan(ids_[i]);
            interestDue += loan.interestDue;
        }

        return interestDue;
    }

    // ===== ASSERTIONS ===== //

    function _assertCoolerLoans() internal {
        // Check that coolerA has a single open loan
        Cooler.Loan memory loan = coolerA.getLoan(0);
        assertEq(loan.collateral, 0, "loan 0: collateral");
        loan = coolerA.getLoan(1);
        assertEq(loan.collateral, 0, "loan 1: collateral");
        loan = coolerA.getLoan(2);
        assertEq(loan.collateral, 0, "loan 2: collateral");
        loan = coolerA.getLoan(3);
        assertEq(loan.collateral, 3_333 * 1e18, "loan 3: collateral");
        vm.expectRevert();
        loan = coolerA.getLoan(4);
    }

    function _assertTokenBalances(
        uint256 walletABalance,
        uint256 lenderBalance,
        uint256 collectorBalance
    ) internal {
        assertEq(dai.balanceOf(address(utils)), 0, "dai: utils");
        assertEq(dai.balanceOf(walletA), walletABalance, "dai: walletA");
        assertEq(dai.balanceOf(address(coolerA)), 0, "dai: coolerA");
        assertEq(dai.balanceOf(lender), lenderBalance, "dai: lender");
        assertEq(dai.balanceOf(collector), collectorBalance, "dai: collector");
        assertEq(sdai.balanceOf(address(utils)), 0, "sdai: utils");
        assertEq(sdai.balanceOf(walletA), 0, "sdai: walletA");
        assertEq(sdai.balanceOf(address(coolerA)), 0, "sdai: coolerA");
        assertEq(sdai.balanceOf(lender), 0, "sdai: lender");
        assertEq(sdai.balanceOf(collector), 0, "sdai: collector");
        assertEq(gohm.balanceOf(address(utils)), 0, "gohm: utils");
        assertEq(gohm.balanceOf(walletA), 0, "gohm: walletA");
        assertEq(gohm.balanceOf(address(coolerA)), 3_333 * 1e18, "gohm: coolerA");
        assertEq(gohm.balanceOf(lender), 0, "gohm: lender");
        assertEq(gohm.balanceOf(collector), 0, "gohm: collector");
    }

    function _assertApprovals() internal {
        assertEq(
            dai.allowance(address(utils), address(coolerA)),
            0,
            "dai allowance: utils -> coolerA"
        );
        assertEq(
            dai.allowance(address(utils), address(clearinghouse)),
            0,
            "dai allowance: utils -> clearinghouse"
        );
        assertEq(
            dai.allowance(address(utils), address(lender)),
            0,
            "dai allowance: utils -> lender"
        );
        assertEq(gohm.allowance(walletA, address(utils)), 0, "gohm allowance: walletA -> utils");
        assertEq(
            gohm.allowance(address(utils), address(coolerA)),
            0,
            "gohm allowance: utils -> coolerA"
        );
        assertEq(
            gohm.allowance(address(utils), address(clearinghouse)),
            0,
            "gohm allowance: utils -> clearinghouse"
        );
        assertEq(
            gohm.allowance(address(utils), address(lender)),
            0,
            "gohm allowance: utils -> lender"
        );
    }

    // ===== TESTS ===== //

    // consolidateWithFlashLoan
    // given the caller has no loans
    //  [X] it reverts
    // given the caller has 1 loan
    //  [X] it reverts
    // given the caller is not the cooler owner
    //  [X] it reverts
    // given DAI spending approval has not been given to CoolerUtils
    //  [X] it reverts
    // given gOHM spending approval has not been given to CoolerUtils
    //  [X] it reverts
    // given the protocol fee is non-zero
    //  [X] it transfers the protocol fee to the collector
    // given the lender fee is non-zero
    //  [ ] it transfers the lender fee to the lender
    // when useFunds is non-zero
    //  when sDAI is true
    //   given sDAI spending approval has not been given to CoolerUtils
    //    [X] it reverts
    //   given the sDAI amount is greater than required for fees
    //    [X] it returns the surplus as DAI to the caller
    //   given the sDAI amount is less than required for fees
    //    [X] it reduces the flashloan amount by the redeemed DAI amount
    //   [X] it redeems the specified amount of sDAI into DAI, and reduces the flashloan amount by the amount
    //  when sDAI is false
    //   given the DAI amount is greater than required for fees
    //    [X] it returns the surplus as DAI to the caller
    //   given the DAI amount is less than required for fees
    //    [X] it reduces the flashloan amount by the redeemed DAI amount
    //   [X] it transfers the specified amount of DAI into the contract, and reduces the flashloan amount by the balance
    // when the protocol fee is zero
    //  [X] it succeeds, but does not transfer additional DAI for the fee
    // [X] it takes a flashloan for the total debt amount + CoolerUtils fee, and consolidates the loans into one

    // --- consolidateWithFlashLoan --------------------------------------------

    function test_consolidate_noLoans_reverts() public {
        // Grant approvals
        _grantCallerApprovals(type(uint256).max, type(uint256).max);

        // Expect revert since no loan ids are given
        bytes memory err = abi.encodeWithSelector(CoolerUtils.InsufficientCoolerCount.selector);
        vm.expectRevert(err);

        // Consolidate loans, but give no ids
        uint256[] memory ids = new uint256[](0);
        _consolidate(ids);
    }

    function test_consolidate_oneLoan_reverts() public {
        // Grant approvals
        _grantCallerApprovals(type(uint256).max, type(uint256).max);

        // Expect revert since no loan ids are given
        bytes memory err = abi.encodeWithSelector(CoolerUtils.InsufficientCoolerCount.selector);
        vm.expectRevert(err);

        // Consolidate loans, but give one id
        uint256[] memory ids = new uint256[](1);
        ids[0] = 0;
        _consolidate(ids);
    }

    function test_consolidate_callerNotOwner_reverts() public {
        uint256[] memory idsA = _idsA();

        // Grant approvals
        (, uint256 gohmApproval, uint256 totalDebtWithFee, , ) = utils.requiredApprovals(
            address(coolerA),
            idsA
        );

        _grantCallerApprovals(gohmApproval, totalDebtWithFee);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(CoolerUtils.OnlyCoolerOwner.selector);
        vm.expectRevert(err);

        // Consolidate loans for coolers A, B, and C into coolerC
        // Do not perform as the cooler owner
        utils.consolidateWithFlashLoan(address(clearinghouse), address(coolerA), idsA, 0, false);
    }

    function test_consolidate_insufficientGOhmApproval_reverts() public {
        uint256[] memory idsA = _idsA();

        // Grant approvals
        (, uint256 gohmApproval, uint256 totalDebtWithFee, , ) = utils.requiredApprovals(
            address(coolerA),
            idsA
        );

        _grantCallerApprovals(gohmApproval - 1, totalDebtWithFee);

        // Expect revert
        vm.expectRevert("ERC20: transfer amount exceeds allowance");

        _consolidate(idsA);
    }

    function test_consolidate_insufficientDaiApproval_reverts() public {
        uint256[] memory idsA = _idsA();

        // Grant approvals
        (, uint256 gohmApproval, , , ) = utils.requiredApprovals(address(coolerA), idsA);

        _grantCallerApprovals(gohmApproval, 1);

        // Expect revert
        vm.expectRevert("Dai/insufficient-allowance");

        _consolidate(idsA, 2, false);
    }

    function test_consolidate_insufficientSdaiApproval_reverts() public {
        uint256[] memory idsA = _idsA();

        // Grant approvals
        (, uint256 gohmApproval, , , ) = utils.requiredApprovals(address(coolerA), idsA);

        _grantCallerApprovals(gohmApproval, 0);
        vm.prank(walletA);
        sdai.approve(address(utils), 1);

        // Expect revert
        vm.expectRevert("SavingsDai/insufficient-balance");

        _consolidate(idsA, 2, true);
    }

    function test_consolidate_noProtocolFee() public {
        uint256[] memory idsA = _idsA();

        // Grant approvals
        (, uint256 gohmApproval, uint256 totalDebtWithFee, , ) = utils.requiredApprovals(
            address(coolerA),
            idsA
        );

        // Record the amount of DAI in the wallet
        uint256 initPrincipal = dai.balanceOf(walletA);
        uint256 interestDue = _getInterestDue(idsA);

        _grantCallerApprovals(gohmApproval, totalDebtWithFee);

        // Consolidate loans for coolers A, B, and C into coolerC
        _consolidate(idsA);

        _assertCoolerLoans();
        _assertTokenBalances(initPrincipal - interestDue, 0, 0);
        _assertApprovals();
    }

    function test_consolidate_protocolFee()
        public
        givenProtocolFee(1000) // 1%
    {
        uint256[] memory idsA = _idsA();

        // Grant approvals
        (, uint256 gohmApproval, uint256 totalDebtWithFee, , uint256 protocolFee) = utils
            .requiredApprovals(address(coolerA), idsA);

        // Record the amount of DAI in the wallet
        uint256 initPrincipal = dai.balanceOf(walletA);
        uint256 interestDue = _getInterestDue(idsA);

        _grantCallerApprovals(gohmApproval, totalDebtWithFee);

        // Consolidate loans for coolers A, B, and C into coolerC
        _consolidate(idsA);

        _assertCoolerLoans();
        _assertTokenBalances(initPrincipal - interestDue - protocolFee, 0, protocolFee);
        _assertApprovals();
    }

    function test_consolidate_whenUseFundsGreaterThanRequired() public {
        uint256[] memory idsA = _idsA();

        // Grant approvals
        (, uint256 gohmApproval, uint256 totalDebtWithFee, , ) = utils.requiredApprovals(
            address(coolerA),
            idsA
        );

        // Record the amount of DAI in the wallet
        uint256 initPrincipal = dai.balanceOf(walletA);
        uint256 interestDue = _getInterestDue(idsA);

        _grantCallerApprovals(gohmApproval, totalDebtWithFee);

        // Consolidate loans for coolers A, B, and C into coolerC
        _consolidate(idsA, interestDue + 1, false);

        _assertCoolerLoans();
        _assertTokenBalances(initPrincipal - interestDue, 0, 0);
        _assertApprovals();
    }

    function test_consolidate_whenUseFundsLessThanRequired() public {
        uint256[] memory idsA = _idsA();

        // Grant approvals
        (, uint256 gohmApproval, uint256 totalDebtWithFee, , ) = utils.requiredApprovals(
            address(coolerA),
            idsA
        );

        // Record the amount of DAI in the wallet
        uint256 initPrincipal = dai.balanceOf(walletA);
        uint256 interestDue = _getInterestDue(idsA);

        _grantCallerApprovals(gohmApproval, totalDebtWithFee);

        // Consolidate loans for coolers A, B, and C into coolerC
        _consolidate(idsA, interestDue - 1, false);

        _assertCoolerLoans();
        _assertTokenBalances(initPrincipal - interestDue, 0, 0);
        _assertApprovals();
    }

    function test_consolidate_whenUseFundsEqualToRequired() public {
        uint256[] memory idsA = _idsA();

        // Grant approvals
        (, uint256 gohmApproval, uint256 totalDebtWithFee, , ) = utils.requiredApprovals(
            address(coolerA),
            idsA
        );

        // Record the amount of DAI in the wallet
        uint256 initPrincipal = dai.balanceOf(walletA);
        uint256 interestDue = _getInterestDue(idsA);

        _grantCallerApprovals(gohmApproval, totalDebtWithFee);

        // Consolidate loans for coolers A, B, and C into coolerC
        _consolidate(idsA, interestDue, false);

        _assertCoolerLoans();
        _assertTokenBalances(initPrincipal - interestDue, 0, 0);
        _assertApprovals();
    }

    function test_consolidate_protocolFee_whenUseFundsGreaterThanRequired()
        public
        givenProtocolFee(1000) // 1%
    {
        uint256[] memory idsA = _idsA();

        // Grant approvals
        (, uint256 gohmApproval, uint256 totalDebtWithFee, , uint256 protocolFee) = utils
            .requiredApprovals(address(coolerA), idsA);

        // Record the amount of DAI in the wallet
        uint256 initPrincipal = dai.balanceOf(walletA);
        uint256 interestDue = _getInterestDue(idsA);

        _grantCallerApprovals(gohmApproval, totalDebtWithFee);

        // Consolidate loans for coolers A, B, and C into coolerC
        uint256 useFunds = protocolFee + 1;
        _consolidate(idsA, useFunds, false);

        // Assertions
        uint256 protocolFeeActual = (initPrincipal + interestDue - useFunds) * utils.feePercentage() / 1e5;

        _assertCoolerLoans();
        _assertTokenBalances(initPrincipal - interestDue - protocolFeeActual, 0, protocolFeeActual);
        _assertApprovals();
    }

    function test_consolidate_protocolFee_whenUseFundsLessThanRequired()
        public
        givenProtocolFee(1000) // 1%
    {
        uint256[] memory idsA = _idsA();

        // Grant approvals
        (, uint256 gohmApproval, uint256 totalDebtWithFee, , uint256 protocolFee) = utils
            .requiredApprovals(address(coolerA), idsA);

        // Record the amount of DAI in the wallet
        uint256 initPrincipal = dai.balanceOf(walletA);
        uint256 interestDue = _getInterestDue(idsA);

        _grantCallerApprovals(gohmApproval, totalDebtWithFee);

        // Consolidate loans for coolers A, B, and C into coolerC
        uint256 useFunds = protocolFee - 1;
        _consolidate(idsA, useFunds, false);

        // Assertions
        uint256 protocolFeeActual = (initPrincipal + interestDue - useFunds) * utils.feePercentage() / 1e5;

        _assertCoolerLoans();
        _assertTokenBalances(initPrincipal - interestDue - protocolFeeActual, 0, protocolFeeActual);
        _assertApprovals();
    }

    function test_consolidate_protocolFee_whenUseFundsEqualToRequired()
        public
        givenProtocolFee(1000) // 1%
    {
        uint256[] memory idsA = _idsA();

        // Grant approvals
        (, uint256 gohmApproval, uint256 totalDebtWithFee, , uint256 protocolFee) = utils
            .requiredApprovals(address(coolerA), idsA);

        // Record the amount of DAI in the wallet
        uint256 initPrincipal = dai.balanceOf(walletA);
        uint256 interestDue = _getInterestDue(idsA);

        _grantCallerApprovals(gohmApproval, totalDebtWithFee);

        // Consolidate loans for coolers A, B, and C into coolerC
        uint256 useFunds = protocolFee;
        _consolidate(idsA, useFunds, false);

        // Assertions
        uint256 protocolFeeActual = (initPrincipal + interestDue - useFunds) * utils.feePercentage() / 1e5;

        _assertCoolerLoans();
        _assertTokenBalances(initPrincipal - interestDue - protocolFeeActual, 0, protocolFeeActual);
        _assertApprovals();
    }

    function test_consolidate_protocolFee_whenUseFundsEqualToRequired_usingSDai()
        public
        givenProtocolFee(1000) // 1%
    {
        uint256[] memory idsA = _idsA();

        // Grant approvals
        (, uint256 gohmApproval, uint256 totalDebtWithFee, , uint256 protocolFee) = utils
            .requiredApprovals(address(coolerA), idsA);

        // Record the amount of DAI in the wallet
        uint256 initPrincipal = dai.balanceOf(walletA);
        uint256 interestDue = _getInterestDue(idsA);

        _grantCallerApprovals(gohmApproval, totalDebtWithFee);

        // Mint SDai
        uint256 useFunds = protocolFee;
        uint256 useFundsSDai = sdai.previewWithdraw(useFunds);
        deal(address(sdai), walletA, useFundsSDai);

        // Approve SDai spending
        vm.prank(walletA);
        sdai.approve(address(utils), useFundsSDai);

        // Consolidate loans for coolers A, B, and C into coolerC
        _consolidate(idsA, useFundsSDai, true);

        // Assertions
        uint256 protocolFeeActual = (initPrincipal + interestDue - useFunds) * utils.feePercentage() / 1e5;

        _assertCoolerLoans();
        _assertTokenBalances(initPrincipal - interestDue - protocolFeeActual, 0, protocolFeeActual);
        _assertApprovals();
    }

    function test_consolidate_protocolFee_whenUseFundsGreaterThanRequired_usingSDai()
        public
        givenProtocolFee(1000) // 1%
    {
        uint256[] memory idsA = _idsA();

        // Grant approvals
        (, uint256 gohmApproval, uint256 totalDebtWithFee, , uint256 protocolFee) = utils
            .requiredApprovals(address(coolerA), idsA);

        // Record the amount of DAI in the wallet
        uint256 initPrincipal = dai.balanceOf(walletA);
        uint256 interestDue = _getInterestDue(idsA);

        _grantCallerApprovals(gohmApproval, totalDebtWithFee);

        // Mint SDai
        uint256 useFunds = protocolFee + 1e9;
        uint256 useFundsSDai = sdai.previewWithdraw(useFunds);
        deal(address(sdai), walletA, useFundsSDai);

        // Approve SDai spending
        vm.prank(walletA);
        sdai.approve(address(utils), useFundsSDai);

        // Consolidate loans for coolers A, B, and C into coolerC
        _consolidate(idsA, useFundsSDai, true);

        // Assertions
        uint256 protocolFeeActual = (initPrincipal + interestDue - useFunds) * utils.feePercentage() / 1e5;

        _assertCoolerLoans();
        _assertTokenBalances(initPrincipal - interestDue - protocolFeeActual, 0, protocolFeeActual);
        _assertApprovals();
    }

    function test_consolidate_protocolFee_whenUseFundsLessThanRequired_usingSDai()
        public
        givenProtocolFee(1000) // 1%
    {
        uint256[] memory idsA = _idsA();

        // Grant approvals
        (, uint256 gohmApproval, uint256 totalDebtWithFee, , uint256 protocolFee) = utils
            .requiredApprovals(address(coolerA), idsA);

        // Record the amount of DAI in the wallet
        uint256 initPrincipal = dai.balanceOf(walletA);
        uint256 interestDue = _getInterestDue(idsA);

        _grantCallerApprovals(gohmApproval, totalDebtWithFee);

        // Mint SDai
        uint256 useFunds = protocolFee - 1e9;
        uint256 useFundsSDai = sdai.previewWithdraw(useFunds);
        deal(address(sdai), walletA, useFundsSDai);

        // Approve SDai spending
        vm.prank(walletA);
        sdai.approve(address(utils), useFundsSDai);

        // Consolidate loans for coolers A, B, and C into coolerC
        _consolidate(idsA, useFundsSDai, true);

        // Assertions
        uint256 protocolFeeActual = (initPrincipal + interestDue - useFunds) * utils.feePercentage() / 1e5;

        _assertCoolerLoans();
        _assertTokenBalances(initPrincipal - interestDue - protocolFeeActual, 0, protocolFeeActual);
        _assertApprovals();
    }

    // setFeePercentage
    // when the caller is not the owner
    //  [ ] it reverts
    // when the fee is > 100%
    //  [ ] it reverts
    // [ ] it sets the fee percentage

    // setCollector
    // when the caller is not the owner
    //  [ ] it reverts
    // when the new collector is the zero address
    //  [ ] it reverts
    // [ ] it sets the collector

    // requiredApprovals
    // when the caller has no loans
    //  [ ] it reverts
    // when the caller has 1 loan
    //  [ ] it reverts
    // when the protocol fee is zero
    //  [ ] it returns the correct values
    // when the protocol fee is non-zero
    //  [ ] it returns the correct values
    // [ ] it returns the correct values for owner, gOHM amount, total DAI debt and sDAI amount

    // --- AUX FUNCTIONS -----------------------------------------------------------

    function _idsA() internal pure returns (uint256[] memory) {
        uint256[] memory ids = new uint256[](3);
        ids[0] = 0;
        ids[1] = 1;
        ids[2] = 2;
        return ids;
    }
}
