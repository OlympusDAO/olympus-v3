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

    // --- consolidateWithFlashLoan --------------------------------------------

    function test_consolidateWithFlashLoan_DAI_funding() public {
        uint256[] memory idsA = _idsA();
        uint256 initPrincipal = dai.balanceOf(walletA);

        // Pretend that owners wallets doen't have enough funds to consolidate so they have to use a flashloan
        deal(address(dai), walletA, 0);

        // Check that coolerA has 3 open loans
        Cooler.Loan memory loan = coolerA.getLoan(0);
        assertEq(loan.collateral, 2_000 * 1e18);
        loan = coolerA.getLoan(1);
        assertEq(loan.collateral, 1_000 * 1e18);
        loan = coolerA.getLoan(2);
        assertEq(loan.collateral, 333 * 1e18);
        vm.expectRevert();
        loan = coolerA.getLoan(3);

        // -------------------------------------------------------------------------
        //                 NECESSARY USER SETUP BEFORE CONSOLIDATING
        // -------------------------------------------------------------------------

        // Ensure that walletA grants gOHM approval
        (address coolerOwner, uint256 gohmApproval, uint256 totalDebt, ) = utils.requiredApprovals(
            address(coolerA),
            idsA
        );
        assertEq(coolerOwner, walletA);

        // Ensure that owner has enough DAI to consolidate and grant necessary approval
        deal(address(dai), walletA, totalDebt);

        vm.startPrank(walletA);
        dai.approve(address(utils), totalDebt);
        gohm.approve(address(utils), gohmApproval);
        vm.stopPrank();

        // -------------------------------------------------------------------------

        // Consolidate loans for coolers A, B, and C into coolerC
        vm.prank(walletA);
        utils.consolidateWithFlashLoan(address(clearinghouse), address(coolerA), idsA, 0, false);

        // Check that coolerA has a single open loan
        loan = coolerA.getLoan(0);
        assertEq(loan.collateral, 0);
        loan = coolerA.getLoan(1);
        assertEq(loan.collateral, 0);
        loan = coolerA.getLoan(2);
        assertEq(loan.collateral, 0);
        loan = coolerA.getLoan(3);
        assertEq(loan.collateral, 3_333 * 1e18);
        vm.expectRevert();
        loan = coolerA.getLoan(4);

        // Check token balances
        assertEq(dai.balanceOf(address(utils)), 0);
        assertEq(dai.balanceOf(walletA), initPrincipal);
        assertEq(gohm.balanceOf(address(coolerA)), 3_333 * 1e18);
        assertEq(gohm.balanceOf(address(utils)), 0);
    }

    // --- AUX FUNCTIONS -----------------------------------------------------------

    function _idsA() internal pure returns (uint256[] memory) {
        uint256[] memory ids = new uint256[](3);
        ids[0] = 0;
        ids[1] = 1;
        ids[2] = 2;
        return ids;
    }
}
