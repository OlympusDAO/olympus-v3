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

import {OlympusContractRegistry} from "src/modules/RGSTY/OlympusContractRegistry.sol";
import {ContractRegistryAdmin} from "src/policies/ContractRegistryAdmin.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";
import {Kernel, Actions, toKeycode} from "src/Kernel.sol";

import {LoanConsolidator} from "src/policies/LoanConsolidator.sol";

contract LoanConsolidatorForkTest is Test {
    LoanConsolidator public utils;

    ERC20 public ohm;
    ERC20 public gohm;
    ERC20 public dai;
    IERC4626 public sdai;

    CoolerFactory public coolerFactory;
    Clearinghouse public clearinghouse;

    OlympusContractRegistry public RGSTY;
    ContractRegistryAdmin public rgstyAdmin;
    RolesAdmin public rolesAdmin;
    TRSRYv1 public TRSRY;
    Kernel public kernel;

    address public staking;
    address public lender;
    address public admin;
    address public emergency;
    address public kernelExecutor;

    address public walletA;
    Cooler public coolerA;

    uint256 internal constant _GOHM_AMOUNT = 3_333 * 1e18;
    uint256 internal constant _ONE_HUNDRED_PERCENT = 100e2;

    uint256 internal trsryDaiBalance;
    uint256 internal trsryGOhmBalance;
    uint256 internal trsrySDaiBalance;

    string RPC_URL = vm.envString("FORK_TEST_RPC_URL");

    // These are replicated here so that if they are updated, the tests will fail
    bytes32 public constant ROLE_ADMIN = "loan_consolidator_admin";
    bytes32 public constant ROLE_EMERGENCY_SHUTDOWN = "emergency_shutdown";

    function setUp() public {
        // Mainnet Fork at a fixed block
        // Prior to actual deployment of LoanConsolidator and RGSTY
        vm.createSelectFork(RPC_URL, 18762666);

        // Required Contracts
        coolerFactory = CoolerFactory(0x30Ce56e80aA96EbbA1E1a74bC5c0FEB5B0dB4216);
        clearinghouse = Clearinghouse(0xE6343ad0675C9b8D3f32679ae6aDbA0766A2ab4c);

        ohm = ERC20(0x64aa3364F17a4D01c6f1751Fd97C2BD3D7e7f1D5);
        gohm = ERC20(0x0ab87046fBb341D058F17CBC4c1133F25a20a52f);
        dai = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        sdai = IERC4626(0x83F20F44975D03b1b09e64809B757c47f942BEeA);
        lender = 0x60744434d6339a6B27d73d9Eda62b6F66a0a04FA;
        staking = 0xB63cac384247597756545b500253ff8E607a8020;

        kernel = Kernel(0x2286d7f9639e8158FaD1169e76d1FbC38247f54b);
        rolesAdmin = RolesAdmin(0xb216d714d91eeC4F7120a732c11428857C659eC8);
        TRSRY = TRSRYv1(address(kernel.getModuleForKeycode(toKeycode("TRSRY"))));

        // Cache the TRSRY balances
        trsryDaiBalance = dai.balanceOf(address(TRSRY));
        trsryGOhmBalance = gohm.balanceOf(address(TRSRY));
        trsrySDaiBalance = sdai.balanceOf(address(TRSRY));

        // Determine the kernel executor
        kernelExecutor = Kernel(kernel).executor();

        // Install RGSTY (since block is pinned, it won't be installed)
        RGSTY = new OlympusContractRegistry(address(kernel));
        vm.prank(kernelExecutor);
        kernel.executeAction(Actions.InstallModule, address(RGSTY));

        // Set up and install the contract registry admin policy
        rgstyAdmin = new ContractRegistryAdmin(address(kernel));
        vm.prank(kernelExecutor);
        kernel.executeAction(Actions.ActivatePolicy, address(rgstyAdmin));

        // Grant the contract registry admin role to this contract
        vm.prank(kernelExecutor);
        rolesAdmin.grantRole("contract_registry_admin", address(this));

        // Register the tokens with RGSTY
        vm.startPrank(address(this));
        rgstyAdmin.registerImmutableContract("dai", address(dai));
        rgstyAdmin.registerImmutableContract("sdai", address(sdai));
        rgstyAdmin.registerImmutableContract("gohm", address(gohm));
        rgstyAdmin.registerContract("flash", address(lender));
        vm.stopPrank();

        admin = vm.addr(0x2);

        // Deploy LoanConsolidator
        utils = new LoanConsolidator(address(kernel), 0);

        walletA = vm.addr(0xA);

        // Fund wallets with gOHM
        deal(address(gohm), walletA, _GOHM_AMOUNT);

        // Ensure the Clearinghouse has enough DAI
        deal(address(dai), address(clearinghouse), 18_000_000 * 1e18);

        _createCoolers(clearinghouse, coolerFactory, walletA);
    }

    // ===== MODIFIERS ===== //

    modifier givenAdminHasRole() {
        vm.prank(kernelExecutor);
        rolesAdmin.grantRole(ROLE_ADMIN, admin);
        _;
    }

    modifier givenEmergencyHasRole() {
        vm.prank(kernelExecutor);
        rolesAdmin.grantRole(ROLE_EMERGENCY_SHUTDOWN, emergency);
        _;
    }

    modifier givenProtocolFee(uint256 feePercent_) {
        vm.prank(admin);
        utils.setFeePercentage(feePercent_);
        _;
    }

    function _setLenderFee(uint256 borrowAmount_, uint256 fee_) internal {
        vm.mockCall(
            lender,
            abi.encodeWithSelector(
                IERC3156FlashLender.flashFee.selector,
                address(dai),
                borrowAmount_
            ),
            abi.encode(fee_)
        );
    }

    function _grantCallerApprovals(uint256[] memory ids) internal {
        // Will revert if there are less than 2 loans
        if (ids.length < 2) {
            return;
        }

        (, uint256 gohmApproval, uint256 totalDebtWithFee, , ) = utils.requiredApprovals(
            address(clearinghouse),
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

    function _consolidate(
        address clearinghouseFrom_,
        address clearinghouseTo_,
        address coolerFrom_,
        address coolerTo_,
        uint256[] memory ids_,
        uint256 useFunds_,
        bool sDai_
    ) internal {
        vm.prank(walletA);
        utils.consolidateWithFlashLoan(
            clearinghouseFrom_,
            clearinghouseTo_,
            coolerFrom_,
            coolerTo_,
            ids_,
            useFunds_,
            sDai_
        );
    }

    function _consolidate(uint256[] memory ids_, uint256 useFunds_, bool sDai_) internal {
        _consolidate(
            address(clearinghouse),
            address(clearinghouse),
            address(coolerA),
            address(coolerA),
            ids_,
            useFunds_,
            sDai_
        );
    }

    function _getInterestDue(
        address cooler_,
        uint256[] memory ids_
    ) internal view returns (uint256) {
        uint256 interestDue;

        for (uint256 i = 0; i < ids_.length; i++) {
            Cooler.Loan memory loan = Cooler(cooler_).getLoan(ids_[i]);
            interestDue += loan.interestDue;
        }

        return interestDue;
    }

    function _getInterestDue(uint256[] memory ids_) internal view returns (uint256) {
        return _getInterestDue(address(coolerA), ids_);
    }

    modifier givenPolicyActive() {
        vm.prank(kernelExecutor);
        kernel.executeAction(Actions.ActivatePolicy, address(utils));
        _;
    }

    modifier givenActivated() {
        vm.prank(emergency);
        utils.activate();
        _;
    }

    modifier givenDeactivated() {
        vm.prank(emergency);
        utils.deactivate();
        _;
    }

    function _createCoolers(
        Clearinghouse clearinghouse_,
        CoolerFactory coolerFactory_,
        address wallet_
    ) internal {
        // Create coolers
        vm.startPrank(wallet_);
        // Deploy a cooler for wallet_
        address coolerA_ = coolerFactory_.generateCooler(gohm, dai);
        coolerA = Cooler(coolerA_);

        // Approve clearinghouse to spend gOHM
        gohm.approve(address(clearinghouse_), _GOHM_AMOUNT);
        // Loan 0 for coolerA (collateral: 2,000 gOHM)
        (uint256 loan, ) = clearinghouse_.getLoanForCollateral(2_000 * 1e18);
        clearinghouse_.lendToCooler(coolerA, loan);
        // Loan 1 for coolerA (collateral: 1,000 gOHM)
        (loan, ) = clearinghouse_.getLoanForCollateral(1_000 * 1e18);
        clearinghouse_.lendToCooler(coolerA, loan);
        // Loan 2 for coolerA (collateral: 333 gOHM)
        (loan, ) = clearinghouse_.getLoanForCollateral(333 * 1e18);
        clearinghouse_.lendToCooler(coolerA, loan);
        vm.stopPrank();
    }

    // ===== ASSERTIONS ===== //

    function _assertCoolerLoans(uint256 collateral_) internal {
        // Check that coolerA has a single open loan
        Cooler.Loan memory loan = coolerA.getLoan(0);
        assertEq(loan.collateral, 0, "loan 0: collateral");
        loan = coolerA.getLoan(1);
        assertEq(loan.collateral, 0, "loan 1: collateral");
        loan = coolerA.getLoan(2);
        assertEq(loan.collateral, 0, "loan 2: collateral");
        loan = coolerA.getLoan(3);
        assertEq(loan.collateral, collateral_, "loan 3: collateral");
        vm.expectRevert();
        loan = coolerA.getLoan(4);
    }

    function _assertTokenBalances(
        uint256 walletABalance,
        uint256 lenderBalance,
        uint256 collectorBalance,
        uint256 collateralBalance
    ) internal {
        assertEq(dai.balanceOf(address(utils)), 0, "dai: utils");
        assertEq(dai.balanceOf(walletA), walletABalance, "dai: walletA");
        assertEq(dai.balanceOf(address(coolerA)), 0, "dai: coolerA");
        assertEq(dai.balanceOf(lender), lenderBalance, "dai: lender");
        assertEq(
            dai.balanceOf(address(TRSRY)),
            trsryDaiBalance + collectorBalance,
            "dai: collector"
        );
        assertEq(sdai.balanceOf(address(utils)), 0, "sdai: utils");
        assertEq(sdai.balanceOf(walletA), 0, "sdai: walletA");
        assertEq(sdai.balanceOf(address(coolerA)), 0, "sdai: coolerA");
        assertEq(sdai.balanceOf(lender), 0, "sdai: lender");
        assertEq(sdai.balanceOf(address(TRSRY)), trsrySDaiBalance, "sdai: collector");
        assertEq(gohm.balanceOf(address(utils)), 0, "gohm: utils");
        assertEq(gohm.balanceOf(walletA), 0, "gohm: walletA");
        assertEq(gohm.balanceOf(address(coolerA)), collateralBalance, "gohm: coolerA");
        assertEq(gohm.balanceOf(lender), 0, "gohm: lender");
        assertEq(gohm.balanceOf(address(TRSRY)), trsryGOhmBalance, "gohm: collector");
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
    // given the contract has not been activated as a policy
    //  [X] it reverts
    // given the contract has been disabled
    //  [X] it reverts
    // when the clearinghouse is not registered with CHREG
    //  [X] it reverts
    // when the cooler was not created by a valid CoolerFactory
    //  [X] it reverts
    // given the caller has no loans
    //  [X] it reverts
    // given the caller has 1 loan
    //  [X] it reverts
    // given the caller is not the cooler owner
    //  [X] it reverts
    // given DAI spending approval has not been given to LoanConsolidator
    //  [X] it reverts
    // given gOHM spending approval has not been given to LoanConsolidator
    //  [X] it reverts
    // given the protocol fee is non-zero
    //  [X] it transfers the protocol fee to the collector
    // given the lender fee is non-zero
    //  [ ] it transfers the lender fee to the lender
    // when useFunds is non-zero
    //  when sDAI is true
    //   given sDAI spending approval has not been given to LoanConsolidator
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
    // when the Clearinghouse is disabled
    //  [X] it reverts
    // [X] it takes a flashloan for the total debt amount + LoanConsolidator fee, and consolidates the loans into one

    // TODO tests for DAI<->USDS migration

    // --- consolidateWithFlashLoan --------------------------------------------

    function test_consolidate_policyNotActive_reverts() public {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(LoanConsolidator.OnlyPolicyActive.selector));

        // Consolidate loans for coolerA
        uint256[] memory idsA = _idsA();
        _consolidate(idsA);
    }

    function test_consolidate_deactivated_reverts()
        public
        givenAdminHasRole
        givenEmergencyHasRole
        givenPolicyActive
        givenDeactivated
    {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(LoanConsolidator.OnlyConsolidatorActive.selector));

        // Consolidate loans for coolerA
        uint256[] memory idsA = _idsA();
        _consolidate(idsA);
    }

    function test_consolidate_thirdPartyClearinghouse_reverts() public givenPolicyActive {
        // Create a new Clearinghouse
        // It is not registered with CHREG, so should be rejected
        Clearinghouse newClearinghouse = new Clearinghouse(
            address(ohm),
            address(gohm),
            staking,
            address(sdai),
            address(coolerFactory),
            address(kernel)
        );

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(LoanConsolidator.Params_InvalidClearinghouse.selector)
        );

        // Consolidate loans for coolers A, B, and C into coolerC
        uint256[] memory idsA = _idsA();
        vm.prank(walletA);
        utils.consolidateWithFlashLoan(
            address(newClearinghouse),
            address(newClearinghouse),
            address(coolerA),
            address(coolerA),
            idsA,
            0,
            false
        );
    }

    function test_consolidate_thirdPartyCooler_reverts() public givenPolicyActive {
        // Create a new Cooler
        // It was not created by the Clearinghouse's CoolerFactory, so should be rejected
        Cooler newCooler = new Cooler();

        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(LoanConsolidator.Params_InvalidCooler.selector));

        // Consolidate loans for coolerA into newCooler
        uint256[] memory idsA = _idsA();
        vm.prank(walletA);
        utils.consolidateWithFlashLoan(
            address(clearinghouse),
            address(clearinghouse),
            address(newCooler),
            address(newCooler),
            idsA,
            0,
            false
        );
    }

    function test_consolidate_noLoans_reverts() public givenPolicyActive {
        // Grant approvals
        _grantCallerApprovals(type(uint256).max, type(uint256).max);

        // Expect revert since no loan ids are given
        vm.expectRevert(
            abi.encodeWithSelector(LoanConsolidator.Params_InsufficientCoolerCount.selector)
        );

        // Consolidate loans, but give no ids
        uint256[] memory ids = new uint256[](0);
        _consolidate(ids);
    }

    function test_consolidate_oneLoan_reverts() public givenPolicyActive {
        // Grant approvals
        _grantCallerApprovals(type(uint256).max, type(uint256).max);

        // Expect revert since no loan ids are given
        vm.expectRevert(
            abi.encodeWithSelector(LoanConsolidator.Params_InsufficientCoolerCount.selector)
        );

        // Consolidate loans, but give one id
        uint256[] memory ids = new uint256[](1);
        ids[0] = 0;
        _consolidate(ids);
    }

    function test_consolidate_callerNotOwner_reverts() public givenPolicyActive {
        uint256[] memory idsA = _idsA();

        // Grant approvals
        (, uint256 gohmApproval, uint256 totalDebtWithFee, , ) = utils.requiredApprovals(
            address(clearinghouse),
            address(coolerA),
            idsA
        );

        _grantCallerApprovals(gohmApproval, totalDebtWithFee);

        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(LoanConsolidator.OnlyCoolerOwner.selector));

        // Consolidate loans for coolers A, B, and C into coolerC
        // Do not perform as the cooler owner
        utils.consolidateWithFlashLoan(
            address(clearinghouse),
            address(clearinghouse),
            address(coolerA),
            address(coolerA),
            idsA,
            0,
            false
        );
    }

    function test_consolidate_insufficientGOhmApproval_reverts() public givenPolicyActive {
        uint256[] memory idsA = _idsA();

        // Grant approvals
        (, uint256 gohmApproval, uint256 totalDebtWithFee, , ) = utils.requiredApprovals(
            address(clearinghouse),
            address(coolerA),
            idsA
        );

        _grantCallerApprovals(gohmApproval - 1, totalDebtWithFee);

        // Expect revert
        vm.expectRevert("ERC20: transfer amount exceeds allowance");

        _consolidate(idsA);
    }

    function test_consolidate_insufficientDaiApproval_reverts() public givenPolicyActive {
        uint256[] memory idsA = _idsA();

        // Grant approvals
        (, uint256 gohmApproval, , , ) = utils.requiredApprovals(
            address(clearinghouse),
            address(coolerA),
            idsA
        );

        _grantCallerApprovals(gohmApproval, 1);

        // Expect revert
        vm.expectRevert("Dai/insufficient-allowance");

        _consolidate(idsA, 2, false);
    }

    function test_consolidate_insufficientSdaiApproval_reverts() public givenPolicyActive {
        uint256[] memory idsA = _idsA();

        // Grant approvals
        (, uint256 gohmApproval, , , ) = utils.requiredApprovals(
            address(clearinghouse),
            address(coolerA),
            idsA
        );

        _grantCallerApprovals(gohmApproval, 0);
        vm.prank(walletA);
        sdai.approve(address(utils), 1);

        // Expect revert
        vm.expectRevert("SavingsDai/insufficient-balance");

        _consolidate(idsA, 2, true);
    }

    function test_consolidate_noProtocolFee() public givenPolicyActive {
        uint256[] memory idsA = _idsA();

        // Grant approvals
        (, uint256 gohmApproval, uint256 totalDebtWithFee, , ) = utils.requiredApprovals(
            address(clearinghouse),
            address(coolerA),
            idsA
        );

        // Record the amount of DAI in the wallet
        uint256 initPrincipal = dai.balanceOf(walletA);
        uint256 interestDue = _getInterestDue(idsA);

        _grantCallerApprovals(gohmApproval, totalDebtWithFee);

        // Consolidate loans for coolers A, B, and C into coolerC
        _consolidate(idsA);

        _assertCoolerLoans(_GOHM_AMOUNT);
        _assertTokenBalances(initPrincipal - interestDue, 0, 0, _GOHM_AMOUNT);
        _assertApprovals();
    }

    function test_consolidate_noProtocolFee_fuzz(
        uint256 loanOneCollateral_,
        uint256 loanTwoCollateral_
    ) public givenPolicyActive {
        // Bound the collateral values
        loanOneCollateral_ = bound(loanOneCollateral_, 1, 1e18);
        loanTwoCollateral_ = bound(loanTwoCollateral_, 1, 1e18);

        // Set up a new wallet
        address walletB = vm.addr(0xB);

        // Fund the wallet with gOHM
        deal(address(gohm), walletB, loanOneCollateral_ + loanTwoCollateral_);

        // Deploy a cooler for walletB
        vm.startPrank(walletB);
        address coolerB_ = coolerFactory.generateCooler(gohm, dai);
        Cooler coolerB = Cooler(coolerB_);

        // Approve clearinghouse to spend gOHM
        gohm.approve(address(clearinghouse), loanOneCollateral_ + loanTwoCollateral_);

        // Take loans
        {
            // Loan 0 for coolerB
            (uint256 loanOnePrincipal, ) = clearinghouse.getLoanForCollateral(loanOneCollateral_);
            clearinghouse.lendToCooler(coolerB, loanOnePrincipal);

            // Loan 1 for coolerB
            (uint256 loanTwoPrincipal, ) = clearinghouse.getLoanForCollateral(loanTwoCollateral_);
            clearinghouse.lendToCooler(coolerB, loanTwoPrincipal);
            vm.stopPrank();
        }

        uint256[] memory loanIds = new uint256[](2);
        loanIds[0] = 0;
        loanIds[1] = 1;

        // Grant approvals
        (, uint256 gohmApproval, uint256 totalDebtWithFee, , ) = utils.requiredApprovals(
            address(clearinghouse),
            address(coolerB),
            loanIds
        );

        // Record the amount of DAI in the wallet
        uint256 initPrincipal = dai.balanceOf(walletB);
        uint256 interestDue = _getInterestDue(address(coolerB), loanIds);

        // Grant approvals
        vm.startPrank(walletB);
        dai.approve(address(utils), totalDebtWithFee);
        gohm.approve(address(utils), gohmApproval);
        vm.stopPrank();

        // Consolidate loans for coolers 0 and 1 into 2
        vm.startPrank(walletB);
        utils.consolidateWithFlashLoan(
            address(clearinghouse),
            address(clearinghouse),
            address(coolerB),
            address(coolerB),
            loanIds,
            0,
            false
        );
        vm.stopPrank();

        // Assert loan balances
        assertEq(coolerB.getLoan(0).collateral, 0, "loan 0: collateral");
        assertEq(coolerB.getLoan(1).collateral, 0, "loan 1: collateral");
        assertEq(
            coolerB.getLoan(2).collateral + gohm.balanceOf(walletB),
            loanOneCollateral_ + loanTwoCollateral_,
            "consolidated: collateral"
        );

        // Assert token balances
        assertEq(dai.balanceOf(walletB), initPrincipal - interestDue, "DAI balance");
        // Don't check gOHM balance of walletB, because it can be non-zero due to rounding
        // assertEq(gohm.balanceOf(walletB), 0, "gOHM balance");
        assertEq(dai.balanceOf(address(coolerB)), 0, "DAI balance: coolerB");
        assertEq(
            gohm.balanceOf(address(coolerB)) + gohm.balanceOf(walletB),
            loanOneCollateral_ + loanTwoCollateral_,
            "gOHM balance: coolerB"
        );
        assertEq(gohm.balanceOf(address(utils)), 0, "gOHM balance: utils");

        // Assert approvals
        assertEq(
            dai.allowance(address(utils), address(coolerB)),
            0,
            "DAI allowance: utils -> coolerB"
        );
        assertEq(
            gohm.allowance(address(utils), address(coolerB)),
            0,
            "gOHM allowance: utils -> coolerB"
        );
    }

    function test_consolidate_protocolFee()
        public
        givenAdminHasRole
        givenPolicyActive
        givenProtocolFee(1000) // 1%
    {
        uint256[] memory idsA = _idsA();

        // Grant approvals
        (, uint256 gohmApproval, uint256 totalDebtWithFee, , uint256 protocolFee) = utils
            .requiredApprovals(address(clearinghouse), address(coolerA), idsA);

        // Record the amount of DAI in the wallet
        uint256 initPrincipal = dai.balanceOf(walletA);
        uint256 interestDue = _getInterestDue(idsA);

        _grantCallerApprovals(gohmApproval, totalDebtWithFee);

        // Consolidate loans for coolers A, B, and C into coolerC
        _consolidate(idsA);

        _assertCoolerLoans(_GOHM_AMOUNT);
        _assertTokenBalances(
            initPrincipal - interestDue - protocolFee,
            0,
            protocolFee,
            _GOHM_AMOUNT
        );
        _assertApprovals();
    }

    function test_consolidate_whenUseFundsLessThanTotalDebt() public givenPolicyActive {
        uint256[] memory idsA = _idsA();

        // Grant approvals
        (, uint256 gohmApproval, uint256 totalDebtWithFee, , ) = utils.requiredApprovals(
            address(clearinghouse),
            address(coolerA),
            idsA
        );

        // Record the amount of DAI in the wallet
        uint256 initPrincipal = dai.balanceOf(walletA);
        uint256 interestDue = _getInterestDue(idsA);

        _grantCallerApprovals(gohmApproval, totalDebtWithFee);

        // Consolidate loans for coolers A, B, and C into coolerC
        _consolidate(idsA, interestDue - 1, false);

        _assertCoolerLoans(_GOHM_AMOUNT);
        _assertTokenBalances(initPrincipal - interestDue, 0, 0, _GOHM_AMOUNT);
        _assertApprovals();
    }

    function test_consolidate_whenUseFundsEqualToTotalDebt() public givenPolicyActive {
        uint256[] memory idsA = _idsA();

        // Grant approvals
        (, uint256 gohmApproval, uint256 totalDebtWithFee, , ) = utils.requiredApprovals(
            address(clearinghouse),
            address(coolerA),
            idsA
        );

        // Record the amount of DAI in the wallet
        uint256 interestDue = _getInterestDue(idsA);

        // Ensure the caller has enough DAI
        deal(address(dai), walletA, totalDebtWithFee);

        _grantCallerApprovals(gohmApproval, totalDebtWithFee);

        // Consolidate loans for coolers A, B, and C into coolerC
        _consolidate(idsA, totalDebtWithFee, false);

        _assertCoolerLoans(_GOHM_AMOUNT);
        _assertTokenBalances(totalDebtWithFee - interestDue, 0, 0, _GOHM_AMOUNT);
        _assertApprovals();
    }

    function test_consolidate_protocolFee_whenUseFundsGreaterThanProtocolFee()
        public
        givenAdminHasRole
        givenPolicyActive
        givenProtocolFee(1000) // 1%
    {
        uint256[] memory idsA = _idsA();

        // Grant approvals
        (, uint256 gohmApproval, uint256 totalDebtWithFee, , uint256 protocolFee) = utils
            .requiredApprovals(address(clearinghouse), address(coolerA), idsA);

        // Record the amount of DAI in the wallet
        uint256 initPrincipal = dai.balanceOf(walletA);
        uint256 interestDue = _getInterestDue(idsA);

        _grantCallerApprovals(gohmApproval, totalDebtWithFee);

        // Consolidate loans for coolers A, B, and C into coolerC
        uint256 useFunds = protocolFee + 1;
        _consolidate(idsA, useFunds, false);

        // Assertions
        uint256 protocolFeeActual = ((initPrincipal + interestDue - useFunds) *
            utils.feePercentage()) / _ONE_HUNDRED_PERCENT;

        _assertCoolerLoans(_GOHM_AMOUNT);
        _assertTokenBalances(
            initPrincipal - interestDue - protocolFeeActual,
            0,
            protocolFeeActual,
            _GOHM_AMOUNT
        );
        _assertApprovals();
    }

    function test_consolidate_whenUseFundsGreaterThanTotalDebt_reverts() public givenPolicyActive {
        uint256[] memory idsA = _idsA();

        // Grant approvals
        (, uint256 gohmApproval, uint256 totalDebtWithFee, , ) = utils.requiredApprovals(
            address(clearinghouse),
            address(coolerA),
            idsA
        );

        _grantCallerApprovals(gohmApproval, totalDebtWithFee + 1);

        // Ensure the caller has more DAI that the total debt
        deal(address(dai), walletA, totalDebtWithFee + 1);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            LoanConsolidator.Params_UseFundsOutOfBounds.selector
        );
        vm.expectRevert(err);

        // Consolidate loans for coolers A, B, and C into coolerC
        uint256 useFunds = totalDebtWithFee + 1;
        _consolidate(idsA, useFunds, false);
    }

    function test_consolidate_protocolFee_whenUseFundsLessThanProtocolFee()
        public
        givenAdminHasRole
        givenPolicyActive
        givenProtocolFee(1000) // 1%
    {
        uint256[] memory idsA = _idsA();

        // Grant approvals
        (, uint256 gohmApproval, uint256 totalDebtWithFee, , uint256 protocolFee) = utils
            .requiredApprovals(address(clearinghouse), address(coolerA), idsA);

        // Record the amount of DAI in the wallet
        uint256 initPrincipal = dai.balanceOf(walletA);
        uint256 interestDue = _getInterestDue(idsA);

        _grantCallerApprovals(gohmApproval, totalDebtWithFee);

        // Consolidate loans for coolers A, B, and C into coolerC
        uint256 useFunds = protocolFee - 1;
        _consolidate(idsA, useFunds, false);

        // Assertions
        uint256 protocolFeeActual = ((initPrincipal + interestDue - useFunds) *
            utils.feePercentage()) / _ONE_HUNDRED_PERCENT;

        _assertCoolerLoans(_GOHM_AMOUNT);
        _assertTokenBalances(
            initPrincipal - interestDue - protocolFeeActual,
            0,
            protocolFeeActual,
            _GOHM_AMOUNT
        );
        _assertApprovals();
    }

    function test_consolidate_protocolFee_whenUseFundsEqualToProtocolFee()
        public
        givenAdminHasRole
        givenPolicyActive
        givenProtocolFee(1000) // 1%
    {
        uint256[] memory idsA = _idsA();

        // Grant approvals
        (, uint256 gohmApproval, uint256 totalDebtWithFee, , uint256 protocolFee) = utils
            .requiredApprovals(address(clearinghouse), address(coolerA), idsA);

        // Record the amount of DAI in the wallet
        uint256 initPrincipal = dai.balanceOf(walletA);
        uint256 interestDue = _getInterestDue(idsA);

        _grantCallerApprovals(gohmApproval, totalDebtWithFee);

        // Consolidate loans for coolers A, B, and C into coolerC
        uint256 useFunds = protocolFee;
        _consolidate(idsA, useFunds, false);

        // Assertions
        uint256 protocolFeeActual = ((initPrincipal + interestDue - useFunds) *
            utils.feePercentage()) / _ONE_HUNDRED_PERCENT;

        _assertCoolerLoans(_GOHM_AMOUNT);
        _assertTokenBalances(
            initPrincipal - interestDue - protocolFeeActual,
            0,
            protocolFeeActual,
            _GOHM_AMOUNT
        );
        _assertApprovals();
    }

    function test_consolidate_protocolFee_whenUseFundsEqualToProtocolFee_usingSDai()
        public
        givenAdminHasRole
        givenPolicyActive
        givenProtocolFee(1000) // 1%
    {
        uint256[] memory idsA = _idsA();

        // Grant approvals
        (, uint256 gohmApproval, uint256 totalDebtWithFee, , uint256 protocolFee) = utils
            .requiredApprovals(address(clearinghouse), address(coolerA), idsA);

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
        uint256 protocolFeeActual = ((initPrincipal + interestDue - useFunds) *
            utils.feePercentage()) / _ONE_HUNDRED_PERCENT;

        _assertCoolerLoans(_GOHM_AMOUNT);
        _assertTokenBalances(
            initPrincipal - interestDue + useFunds - protocolFeeActual,
            0,
            protocolFeeActual,
            _GOHM_AMOUNT
        );
        _assertApprovals();
    }

    function test_consolidate_protocolFee_whenUseFundsGreaterThanProtocolFee_usingSDai()
        public
        givenAdminHasRole
        givenPolicyActive
        givenProtocolFee(1000) // 1%
    {
        uint256[] memory idsA = _idsA();

        // Grant approvals
        (, uint256 gohmApproval, uint256 totalDebtWithFee, , uint256 protocolFee) = utils
            .requiredApprovals(address(clearinghouse), address(coolerA), idsA);

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
        uint256 protocolFeeActual = ((initPrincipal + interestDue - useFunds) *
            utils.feePercentage()) / _ONE_HUNDRED_PERCENT;

        _assertCoolerLoans(_GOHM_AMOUNT);
        _assertTokenBalances(
            initPrincipal - interestDue + useFunds - protocolFeeActual,
            0,
            protocolFeeActual,
            _GOHM_AMOUNT
        );
        _assertApprovals();
    }

    function test_consolidate_protocolFee_whenUseFundsLessThanProtocolFee_usingSDai()
        public
        givenAdminHasRole
        givenPolicyActive
        givenProtocolFee(1000) // 1%
    {
        uint256[] memory idsA = _idsA();

        // Grant approvals
        (, uint256 gohmApproval, uint256 totalDebtWithFee, , uint256 protocolFee) = utils
            .requiredApprovals(address(clearinghouse), address(coolerA), idsA);

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
        uint256 protocolFeeActual = ((initPrincipal + interestDue - useFunds) *
            utils.feePercentage()) / _ONE_HUNDRED_PERCENT;

        _assertCoolerLoans(_GOHM_AMOUNT);
        _assertTokenBalances(
            initPrincipal - interestDue + useFunds - protocolFeeActual,
            0,
            protocolFeeActual,
            _GOHM_AMOUNT
        );
        _assertApprovals();
    }

    function test_consolidate_noProtocolFee_disabledClearinghouse_reverts()
        public
        givenPolicyActive
        givenEmergencyHasRole
    {
        // Disable the Clearinghouse
        vm.prank(emergency);
        clearinghouse.emergencyShutdown();

        uint256[] memory idsA = _idsA();

        // Grant approvals
        (, uint256 gohmApproval, uint256 totalDebtWithFee, , ) = utils.requiredApprovals(
            address(clearinghouse),
            address(coolerA),
            idsA
        );

        _grantCallerApprovals(gohmApproval, totalDebtWithFee);

        // Expect revert
        vm.expectRevert("SavingsDai/insufficient-balance");

        // Consolidate loans for coolers A, B, and C into coolerC
        _consolidate(
            address(clearinghouse),
            address(clearinghouse),
            address(coolerA),
            address(coolerA),
            idsA,
            0,
            false
        );
    }

    // setFeePercentage
    // when the policy is not active
    //  [X] it reverts
    // when the caller is not the admin
    //  [X] it reverts
    // when the fee is > 100%
    //  [X] it reverts
    // [X] it sets the fee percentage

    function test_setFeePercentage_whenPolicyNotActive_reverts() public givenAdminHasRole {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(LoanConsolidator.OnlyPolicyActive.selector));

        vm.prank(admin);
        utils.setFeePercentage(1000);
    }

    function test_setFeePercentage_notAdmin_reverts() public givenAdminHasRole givenPolicyActive {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ROLE_ADMIN));

        // Set the fee percentage as a non-admin
        utils.setFeePercentage(1000);
    }

    function test_setFeePercentage_aboveMax_reverts() public givenAdminHasRole givenPolicyActive {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(LoanConsolidator.Params_FeePercentageOutOfRange.selector)
        );

        vm.prank(admin);
        utils.setFeePercentage(_ONE_HUNDRED_PERCENT + 1);
    }

    function test_setFeePercentage(
        uint256 feePercentage_
    ) public givenAdminHasRole givenPolicyActive {
        uint256 feePercentage = bound(feePercentage_, 0, _ONE_HUNDRED_PERCENT);

        vm.prank(admin);
        utils.setFeePercentage(feePercentage);

        assertEq(utils.feePercentage(), feePercentage, "fee percentage");
    }

    // requiredApprovals
    // when the policy is not active
    //  [X] it reverts
    // when the caller has no loans
    //  [X] it reverts
    // when the caller has 1 loan
    //  [X] it reverts
    // when the protocol fee is zero
    //  [X] it returns the correct values
    // when the protocol fee is non-zero
    //  [X] it returns the correct values
    // [X] it returns the correct values for owner, gOHM amount, total DAI debt and sDAI amount

    function test_requiredApprovals_policyNotActive_reverts() public {
        uint256[] memory ids = _idsA();

        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(LoanConsolidator.OnlyPolicyActive.selector));

        utils.requiredApprovals(address(clearinghouse), address(coolerA), ids);
    }

    function test_requiredApprovals_noLoans() public givenPolicyActive {
        uint256[] memory ids = new uint256[](0);

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(LoanConsolidator.Params_InsufficientCoolerCount.selector)
        );

        utils.requiredApprovals(address(clearinghouse), address(coolerA), ids);
    }

    function test_requiredApprovals_oneLoan() public givenPolicyActive {
        uint256[] memory ids = new uint256[](1);
        ids[0] = 0;

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(LoanConsolidator.Params_InsufficientCoolerCount.selector)
        );

        utils.requiredApprovals(address(clearinghouse), address(coolerA), ids);
    }

    function test_requiredApprovals_noProtocolFee() public givenPolicyActive {
        uint256[] memory ids = _idsA();

        (
            address owner_,
            uint256 gohmApproval,
            uint256 totalDebtWithFee,
            uint256 sDaiApproval,
            uint256 protocolFee
        ) = utils.requiredApprovals(address(clearinghouse), address(coolerA), ids);

        uint256 expectedTotalDebtWithFee;
        for (uint256 i = 0; i < ids.length; i++) {
            Cooler.Loan memory loan = coolerA.getLoan(ids[i]);
            expectedTotalDebtWithFee += loan.principal + loan.interestDue;
        }

        assertEq(owner_, walletA, "owner");
        assertEq(gohmApproval, _GOHM_AMOUNT, "gOHM approval");
        assertEq(totalDebtWithFee, expectedTotalDebtWithFee, "total debt with fee");
        assertEq(sDaiApproval, sdai.previewWithdraw(expectedTotalDebtWithFee), "sDai approval");
        assertEq(protocolFee, 0, "protocol fee");
    }

    function test_requiredApprovals_ProtocolFee()
        public
        givenAdminHasRole
        givenPolicyActive
        givenProtocolFee(1000) // 1%
    {
        uint256[] memory ids = _idsA();

        (
            address owner_,
            uint256 gohmApproval,
            uint256 totalDebtWithFee,
            uint256 sDaiApproval,
            uint256 protocolFee
        ) = utils.requiredApprovals(address(clearinghouse), address(coolerA), ids);

        uint256 expectedTotalDebtWithFee;
        for (uint256 i = 0; i < ids.length; i++) {
            Cooler.Loan memory loan = coolerA.getLoan(ids[i]);
            expectedTotalDebtWithFee += loan.principal + loan.interestDue;
        }

        // Calculate protocol fee
        uint256 protocolFeeActual = (expectedTotalDebtWithFee * 1000) / _ONE_HUNDRED_PERCENT;

        assertEq(owner_, walletA, "owner");
        assertEq(gohmApproval, _GOHM_AMOUNT, "gOHM approval");
        assertEq(
            totalDebtWithFee,
            expectedTotalDebtWithFee + protocolFeeActual,
            "total debt with fee"
        );
        assertEq(
            sDaiApproval,
            sdai.previewWithdraw(expectedTotalDebtWithFee + protocolFeeActual),
            "sDai approval"
        );
        assertEq(protocolFee, protocolFeeActual, "protocol fee");
    }

    function test_requiredApprovals_fuzz(
        uint256 loanOneCollateral_,
        uint256 loanTwoCollateral_
    ) public givenPolicyActive {
        // Bound the collateral values
        loanOneCollateral_ = bound(loanOneCollateral_, 1, 1e18);
        loanTwoCollateral_ = bound(loanTwoCollateral_, 1, 1e18);

        // Set up a new wallet
        address walletB = vm.addr(0xB);

        // Fund the wallet with gOHM
        deal(address(gohm), walletB, loanOneCollateral_ + loanTwoCollateral_);

        // Deploy a cooler for walletB
        vm.startPrank(walletB);
        address coolerB_ = coolerFactory.generateCooler(gohm, dai);
        Cooler coolerB = Cooler(coolerB_);

        // Approve clearinghouse to spend gOHM
        gohm.approve(address(clearinghouse), loanOneCollateral_ + loanTwoCollateral_);

        // Take loans
        uint256 totalPrincipal;
        {
            // Loan 0 for coolerB
            (uint256 loanOnePrincipal, ) = clearinghouse.getLoanForCollateral(loanOneCollateral_);
            totalPrincipal += loanOnePrincipal;
            clearinghouse.lendToCooler(coolerB, loanOnePrincipal);

            // Loan 1 for coolerB
            (uint256 loanTwoPrincipal, ) = clearinghouse.getLoanForCollateral(loanTwoCollateral_);
            totalPrincipal += loanTwoPrincipal;
            clearinghouse.lendToCooler(coolerB, loanTwoPrincipal);
            vm.stopPrank();
        }

        uint256[] memory loanIds = new uint256[](2);
        loanIds[0] = 0;
        loanIds[1] = 1;

        // Grant approvals
        (, uint256 gohmApproval, , , ) = utils.requiredApprovals(
            address(clearinghouse),
            address(coolerB),
            loanIds
        );

        // Assertions
        // The gOHM approval should be the amount of collateral required for the total principal
        // At small values, this may be slightly different due to rounding
        assertEq(gohmApproval, clearinghouse.getCollateralForLoan(totalPrincipal), "gOHM approval");
    }

    function test_collateralRequired_fuzz(
        uint256 loanOneCollateral_,
        uint256 loanTwoCollateral_
    ) public givenPolicyActive {
        // Bound the collateral values
        loanOneCollateral_ = bound(loanOneCollateral_, 1, 1e18);
        loanTwoCollateral_ = bound(loanTwoCollateral_, 1, 1e18);

        // Set up a new wallet
        address walletB = vm.addr(0xB);

        // Fund the wallet with gOHM
        deal(address(gohm), walletB, loanOneCollateral_ + loanTwoCollateral_);

        // Deploy a cooler for walletB
        vm.startPrank(walletB);
        address coolerB_ = coolerFactory.generateCooler(gohm, dai);
        Cooler coolerB = Cooler(coolerB_);

        // Approve clearinghouse to spend gOHM
        gohm.approve(address(clearinghouse), loanOneCollateral_ + loanTwoCollateral_);

        // Take loans
        uint256 totalPrincipal;
        {
            // Loan 0 for coolerB
            (uint256 loanOnePrincipal, ) = clearinghouse.getLoanForCollateral(loanOneCollateral_);
            clearinghouse.lendToCooler(coolerB, loanOnePrincipal);

            // Loan 1 for coolerB
            (uint256 loanTwoPrincipal, ) = clearinghouse.getLoanForCollateral(loanTwoCollateral_);
            clearinghouse.lendToCooler(coolerB, loanTwoPrincipal);
            vm.stopPrank();

            totalPrincipal = loanOnePrincipal + loanTwoPrincipal;
        }

        // Get the amount of collateral for the loans
        uint256 existingLoanCollateralExpected = coolerB.getLoan(0).collateral +
            coolerB.getLoan(1).collateral;

        // Get the amount of collateral required for the consolidated loan
        uint256 consolidatedLoanCollateralExpected = Clearinghouse(clearinghouse)
            .getCollateralForLoan(totalPrincipal);

        // Get the amount of additional collateral required
        uint256 additionalCollateralExpected;
        if (consolidatedLoanCollateralExpected > existingLoanCollateralExpected) {
            additionalCollateralExpected =
                consolidatedLoanCollateralExpected -
                existingLoanCollateralExpected;
        }

        // Call collateralRequired
        uint256[] memory loanIds = new uint256[](2);
        loanIds[0] = 0;
        loanIds[1] = 1;

        (
            uint256 consolidatedLoanCollateral,
            uint256 existingLoanCollateral,
            uint256 additionalCollateral
        ) = utils.collateralRequired(address(clearinghouse), address(coolerB), loanIds);

        // Assertions
        assertEq(
            consolidatedLoanCollateral,
            consolidatedLoanCollateralExpected,
            "consolidated loan collateral"
        );
        assertEq(
            existingLoanCollateral,
            existingLoanCollateralExpected,
            "existing loan collateral"
        );
        assertEq(additionalCollateral, additionalCollateralExpected, "additional collateral");
    }

    // constructor
    // when the kernel address is the zero address
    //  [X] it reverts
    // when the fee percentage is > 100e2
    //  [X] it reverts
    // [X] it sets the values

    function test_constructor_zeroKernel_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LoanConsolidator.Params_InvalidAddress.selector);
        vm.expectRevert(err);

        new LoanConsolidator(address(0), 0);
    }

    function test_constructor_feePercentageAboveMax_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            LoanConsolidator.Params_FeePercentageOutOfRange.selector
        );
        vm.expectRevert(err);

        new LoanConsolidator(address(kernel), _ONE_HUNDRED_PERCENT + 1);
    }

    function test_constructor(uint256 feePercentage_) public {
        uint256 feePercentage = bound(feePercentage_, 0, _ONE_HUNDRED_PERCENT);

        utils = new LoanConsolidator(address(kernel), feePercentage);

        assertEq(address(utils.kernel()), address(kernel), "kernel");
        assertEq(utils.feePercentage(), feePercentage, "fee percentage");
        assertEq(utils.consolidatorActive(), true, "consolidator active");
    }

    // activate
    // when the policy is not active
    //  [X] it reverts
    // when the caller is not an admin or emergency shutdown
    //  [X] it reverts
    // when the caller is the admin role
    //  [X] it reverts
    // when the caller is the emergency shutdown role
    //  when the contract is already active
    //   [X] it does nothing
    //  [X] it sets the active flag to true

    function test_activate_policyNotActive_reverts()
        public
        givenAdminHasRole
        givenEmergencyHasRole
    {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(LoanConsolidator.OnlyPolicyActive.selector));

        vm.prank(emergency);
        utils.activate();
    }

    function test_activate_notAdminOrEmergency_reverts()
        public
        givenAdminHasRole
        givenEmergencyHasRole
        givenPolicyActive
        givenDeactivated
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            ROLE_EMERGENCY_SHUTDOWN
        );
        vm.expectRevert(err);

        utils.activate();
    }

    function test_activate_asAdmin_reverts()
        public
        givenAdminHasRole
        givenEmergencyHasRole
        givenPolicyActive
        givenDeactivated
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            ROLE_EMERGENCY_SHUTDOWN
        );
        vm.expectRevert(err);

        vm.prank(admin);
        utils.activate();
    }

    function test_activate_asEmergency()
        public
        givenAdminHasRole
        givenEmergencyHasRole
        givenPolicyActive
        givenDeactivated
    {
        vm.prank(emergency);
        utils.activate();

        assertTrue(utils.consolidatorActive(), "consolidator active");
    }

    function test_activate_asEmergency_alreadyActive()
        public
        givenAdminHasRole
        givenEmergencyHasRole
        givenPolicyActive
    {
        vm.prank(emergency);
        utils.activate();

        assertTrue(utils.consolidatorActive(), "consolidator active");
    }

    // deactivate
    // when the policy is not active
    //  [X] it reverts
    // when the caller is not an admin or emergency shutdown
    //  [X] it reverts
    // when the caller has the admin role
    //  [X] it reverts
    // when the caller has the emergency shutdown role
    //  when the contract is already deactivated
    //   [X] it does nothing
    //  [X] it sets the active flag to false

    function test_deactivate_policyNotActive_reverts()
        public
        givenAdminHasRole
        givenEmergencyHasRole
    {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(LoanConsolidator.OnlyPolicyActive.selector));

        vm.prank(emergency);
        utils.deactivate();
    }

    function test_deactivate_notAdminOrEmergency_reverts()
        public
        givenAdminHasRole
        givenEmergencyHasRole
        givenPolicyActive
    {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ROLE_EMERGENCY_SHUTDOWN)
        );

        utils.deactivate();
    }

    function test_deactivate_asAdmin_reverts()
        public
        givenAdminHasRole
        givenEmergencyHasRole
        givenPolicyActive
    {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ROLE_EMERGENCY_SHUTDOWN)
        );

        vm.prank(admin);
        utils.deactivate();
    }

    function test_deactivate_asEmergency()
        public
        givenAdminHasRole
        givenEmergencyHasRole
        givenPolicyActive
    {
        vm.prank(emergency);
        utils.deactivate();

        assertFalse(utils.consolidatorActive(), "consolidator active");
    }

    function test_deactivate_asEmergency_alreadyDeactivated()
        public
        givenAdminHasRole
        givenEmergencyHasRole
        givenPolicyActive
        givenDeactivated
    {
        vm.prank(emergency);
        utils.deactivate();

        assertFalse(utils.consolidatorActive(), "consolidator active");
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
