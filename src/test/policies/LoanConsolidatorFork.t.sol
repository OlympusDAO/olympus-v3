// SPDX-License-Identifier: GLP-3.0
// solhint-disable max-states-count
pragma solidity ^0.8.15;

import {Test, console2} from "forge-std/Test.sol";
import {MockFlashloanLender} from "src/test/mocks/MockFlashloanLender.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {IERC4626} from "forge-std/interfaces/IERC4626.sol";

import {IERC3156FlashLender} from "src/interfaces/maker-dao/IERC3156FlashLender.sol";
import {CoolerFactory} from "src/external/cooler/CoolerFactory.sol";
import {Clearinghouse} from "src/policies/Clearinghouse.sol";
import {Cooler} from "src/external/cooler/Cooler.sol";

import {OlympusContractRegistry} from "src/modules/RGSTY/OlympusContractRegistry.sol";
import {ContractRegistryAdmin} from "src/policies/ContractRegistryAdmin.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";
import {CHREGv1} from "src/modules/CHREG/CHREG.v1.sol";
import {OlympusClearinghouseRegistry} from "src/modules/CHREG/OlympusClearinghouseRegistry.sol";
import {Kernel, Actions, toKeycode, Module} from "src/Kernel.sol";
import {ClonesWithImmutableArgs} from "clones/ClonesWithImmutableArgs.sol";

import {LoanConsolidator} from "src/policies/LoanConsolidator.sol";

import {ClearinghouseLowerLTC} from "src/test/lib/ClearinghouseLowerLTC.sol";
import {ClearinghouseHigherLTC} from "src/test/lib/ClearinghouseHigherLTC.sol";

contract LoanConsolidatorForkTest is Test {
    using ClonesWithImmutableArgs for address;

    LoanConsolidator public utils;

    ERC20 public ohm;
    ERC20 public gohm;
    ERC20 public dai;
    ERC20 public usds;
    IERC4626 public sdai;
    IERC4626 public susds;

    CoolerFactory public coolerFactory;
    Clearinghouse public clearinghouse;
    Clearinghouse public clearinghouseUsds;

    OlympusContractRegistry public RGSTY;
    ContractRegistryAdmin public rgstyAdmin;
    RolesAdmin public rolesAdmin;
    TRSRYv1 public TRSRY;
    CHREGv1 public CHREG;
    Kernel public kernel;

    address public staking;
    address public lender;
    address public daiUsdsMigrator;
    address public admin;
    address public emergency;
    address public kernelExecutor;

    address public walletA;
    address public walletB;
    Cooler public coolerA;
    Cooler public coolerB;

    uint256 internal constant _GOHM_AMOUNT = 3_333 * 1e18;
    uint256 internal constant _ONE_HUNDRED_PERCENT = 100e2;

    uint256 internal trsryDaiBalance;
    uint256 internal trsryGOhmBalance;
    uint256 internal trsrySDaiBalance;
    uint256 internal trsryUsdsBalance;
    uint256 internal trsrySusdsBalance;

    // These are replicated here so that if they are updated, the tests will fail
    bytes32 public constant ROLE_ADMIN = "loan_consolidator_admin";
    bytes32 public constant ROLE_EMERGENCY_SHUTDOWN = "emergency_shutdown";

    function setUp() public {
        // Mainnet Fork at a fixed block
        // After sUSDS deployment
        vm.createSelectFork("mainnet", 20900000);

        // Required Contracts
        coolerFactory = CoolerFactory(0x30Ce56e80aA96EbbA1E1a74bC5c0FEB5B0dB4216);
        clearinghouse = Clearinghouse(0xE6343ad0675C9b8D3f32679ae6aDbA0766A2ab4c);

        ohm = ERC20(0x64aa3364F17a4D01c6f1751Fd97C2BD3D7e7f1D5);
        gohm = ERC20(0x0ab87046fBb341D058F17CBC4c1133F25a20a52f);
        dai = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        usds = ERC20(0xdC035D45d973E3EC169d2276DDab16f1e407384F);
        sdai = IERC4626(0x83F20F44975D03b1b09e64809B757c47f942BEeA);
        susds = IERC4626(0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD);
        lender = 0x60744434d6339a6B27d73d9Eda62b6F66a0a04FA;
        staking = 0xB63cac384247597756545b500253ff8E607a8020;
        daiUsdsMigrator = 0x3225737a9Bbb6473CB4a45b7244ACa2BeFdB276A;

        kernel = Kernel(0x2286d7f9639e8158FaD1169e76d1FbC38247f54b);
        rolesAdmin = RolesAdmin(0xb216d714d91eeC4F7120a732c11428857C659eC8);
        TRSRY = TRSRYv1(address(kernel.getModuleForKeycode(toKeycode("TRSRY"))));
        CHREG = CHREGv1(address(kernel.getModuleForKeycode(toKeycode("CHREG"))));

        // Deposit sUSDS in TRSRY
        deal(address(susds), address(TRSRY), 18_000_000 * 1e18);

        // Determine the kernel executor
        kernelExecutor = Kernel(kernel).executor();

        // CHREG v1 (0x24b96f2150BF1ed10D3e8B28Ed33E392fbB4Cad5) has a bug with the registryCount. If the version is 1.0, mimic upgrading the module
        if (address(CHREG) == 0x24b96f2150BF1ed10D3e8B28Ed33E392fbB4Cad5) {
            console2.log("CHREG v1.0 detected, upgrading to current version...");

            // Determine the active clearinghouse
            uint256 activeClearinghouseCount = CHREG.activeCount();
            address activeClearinghouse;
            if (activeClearinghouseCount >= 1) {
                activeClearinghouse = CHREG.active(0);
                console2.log("Setting active clearinghouse to:", activeClearinghouse);

                // CHREG only accepts one active clearinghouse
                activeClearinghouseCount = 1;
            }

            // Determine the inactive clearinghouses
            uint256 inactiveClearinghouseCount = CHREG.registryCount();
            address[] memory inactiveClearinghouses = new address[](
                inactiveClearinghouseCount - activeClearinghouseCount
            );
            for (uint256 i = 0; i < inactiveClearinghouseCount; i++) {
                // Skip if active, as the constructor will check for duplicates
                if (CHREG.registry(i) == activeClearinghouse) continue;

                inactiveClearinghouses[i] = CHREG.registry(i);
            }

            // Deploy the current version of CHREG
            CHREG = new OlympusClearinghouseRegistry(
                kernel,
                activeClearinghouse,
                inactiveClearinghouses
            );

            // Upgrade the module
            vm.prank(kernelExecutor);
            kernel.executeAction(Actions.UpgradeModule, address(CHREG));
        }

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

        // Grant the cooler overseer role to this contract
        vm.prank(kernelExecutor);
        rolesAdmin.grantRole("cooler_overseer", address(this));

        // Register the tokens with RGSTY
        vm.startPrank(address(this));
        rgstyAdmin.registerImmutableContract("dai", address(dai));
        rgstyAdmin.registerImmutableContract("gohm", address(gohm));
        rgstyAdmin.registerImmutableContract("usds", address(usds));
        rgstyAdmin.registerContract("flash", address(lender));
        rgstyAdmin.registerContract("dmgtr", address(daiUsdsMigrator));
        vm.stopPrank();

        // Add a new Clearinghouse with USDS
        clearinghouseUsds = new Clearinghouse(
            address(ohm),
            address(gohm),
            staking,
            address(susds),
            address(coolerFactory),
            address(kernel)
        );
        vm.startPrank(kernelExecutor);
        kernel.executeAction(Actions.ActivatePolicy, address(clearinghouseUsds));
        vm.stopPrank();
        // Activate the USDS Clearinghouse
        clearinghouseUsds.activate();
        // Rebalance the USDS Clearinghouse
        clearinghouseUsds.rebalance();

        // Cache the TRSRY balances
        // This is after the Clearinghouse, since activation may result in funds movement
        trsryDaiBalance = dai.balanceOf(address(TRSRY));
        trsryGOhmBalance = gohm.balanceOf(address(TRSRY));
        trsrySDaiBalance = sdai.balanceOf(address(TRSRY));
        trsryUsdsBalance = usds.balanceOf(address(TRSRY));
        trsrySusdsBalance = susds.balanceOf(address(TRSRY));

        admin = vm.addr(0x2);

        // Deploy LoanConsolidator
        utils = new LoanConsolidator(address(kernel), 0);

        walletA = vm.addr(0xA);
        walletB = vm.addr(0xB);

        // Fund wallets with gOHM
        deal(address(gohm), walletA, _GOHM_AMOUNT);

        // Ensure the Clearinghouse has enough DAI and sDAI
        deal(address(dai), address(clearinghouse), 18_000_000 * 1e18);
        deal(address(sdai), address(clearinghouse), 18_000_000 * 1e18);
        // Ensure the Clearinghouse has enough USDS and sUSDS
        deal(address(usds), address(clearinghouseUsds), 18_000_000 * 1e18);
        deal(address(susds), address(clearinghouseUsds), 18_000_000 * 1e18);

        _createCoolerAndLoans(clearinghouse, coolerFactory, walletA, dai);

        // LoanConsolidator is deactivated by default
        // Assign the emergency role so that the contract can be activated
        _assignEmergencyRole();
    }

    // ===== MODIFIERS ===== //

    modifier givenAdminHasRole() {
        vm.prank(kernelExecutor);
        rolesAdmin.grantRole(ROLE_ADMIN, admin);
        _;
    }

    function _assignEmergencyRole() internal {
        vm.prank(kernelExecutor);
        rolesAdmin.grantRole(ROLE_EMERGENCY_SHUTDOWN, emergency);
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

    function _grantCallerApprovals(
        address caller_,
        address clearinghouseTo_,
        address coolerFrom_,
        address coolerTo_,
        uint256[] memory ids_
    ) internal {
        (
            ,
            uint256 gohmApproval,
            address reserveTo,
            uint256 ownerReserveTo,
            uint256 callerReserveTwo
        ) = utils.requiredApprovals(clearinghouseTo_, coolerFrom_, ids_);

        // Determine the owner of coolerTo_
        address coolerToOwner = Cooler(coolerTo_).owner();
        bool coolerToOwnerIsCaller = coolerToOwner == caller_;

        // If the owner of the coolers is the same, then the caller can approve the entire amount
        if (coolerToOwnerIsCaller) {
            vm.startPrank(caller_);
            ERC20(reserveTo).approve(address(utils), ownerReserveTo + callerReserveTwo);
            gohm.approve(address(utils), gohmApproval);
            vm.stopPrank();
        }
        // Otherwise two different approvals are needed
        else {
            vm.startPrank(caller_);
            ERC20(reserveTo).approve(address(utils), callerReserveTwo);
            gohm.approve(address(utils), gohmApproval);
            vm.stopPrank();

            vm.startPrank(coolerToOwner);
            ERC20(reserveTo).approve(address(utils), ownerReserveTo);
            vm.stopPrank();
        }
    }

    function _grantCallerApprovals(uint256[] memory ids_) internal {
        _grantCallerApprovals(
            walletA,
            address(clearinghouse),
            address(coolerA),
            address(coolerA),
            ids_
        );
    }

    function _grantCallerApprovals(
        uint256 gOhmAmount_,
        uint256 daiAmount_,
        uint256 usdsAmount_
    ) internal {
        vm.startPrank(walletA);
        dai.approve(address(utils), daiAmount_);
        usds.approve(address(utils), usdsAmount_);
        gohm.approve(address(utils), gOhmAmount_);
        vm.stopPrank();
    }

    function _consolidate(
        address caller_,
        address clearinghouseFrom_,
        address clearinghouseTo_,
        address coolerFrom_,
        address coolerTo_,
        uint256[] memory ids_
    ) internal {
        vm.prank(caller_);
        utils.consolidate(clearinghouseFrom_, clearinghouseTo_, coolerFrom_, coolerTo_, ids_);
    }

    function _consolidate(uint256[] memory ids_) internal {
        _consolidate(
            walletA,
            address(clearinghouse),
            address(clearinghouse),
            address(coolerA),
            address(coolerA),
            ids_
        );
    }

    function _consolidateWithNewOwner(
        address caller_,
        address clearinghouseFrom_,
        address clearinghouseTo_,
        address coolerFrom_,
        address coolerTo_,
        uint256[] memory ids_
    ) internal {
        vm.prank(caller_);
        utils.consolidateWithNewOwner(
            clearinghouseFrom_,
            clearinghouseTo_,
            coolerFrom_,
            coolerTo_,
            ids_
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

    modifier givenMockFlashloanLender() {
        lender = address(new MockFlashloanLender(0, address(dai)));

        // Swap the maker flashloan lender for our mock
        vm.startPrank(address(this));
        rgstyAdmin.updateContract("flash", lender);
        vm.stopPrank();
        _;
    }

    modifier givenMockFlashloanLenderFee(uint16 feePercent_) {
        MockFlashloanLender(lender).setFeePercent(feePercent_);
        _;
    }

    modifier givenMockFlashloanLenderHasBalance(uint256 balance_) {
        deal(address(dai), lender, balance_);
        _;
    }

    function _createCooler(
        CoolerFactory coolerFactory_,
        address wallet_,
        ERC20 token_
    ) internal returns (address) {
        console2.log("Creating cooler...");

        if (address(token_) == address(dai)) {
            console2.log("token: DAI");
        } else if (address(token_) == address(usds)) {
            console2.log("token: USDS");
        } else {
            console2.log("token: ", address(token_));
        }

        if (wallet_ == walletA) {
            console2.log("wallet: A");
        } else if (wallet_ == walletB) {
            console2.log("wallet: B");
        } else {
            console2.log("wallet: ", wallet_);
        }

        vm.startPrank(wallet_);
        address cooler_ = coolerFactory_.generateCooler(gohm, token_);
        vm.stopPrank();

        console2.log("Cooler created:", cooler_);

        return cooler_;
    }

    function _createLoans(Clearinghouse clearinghouse_, Cooler cooler_, address wallet_) internal {
        vm.startPrank(wallet_);
        // Approve clearinghouse to spend gOHM
        gohm.approve(address(clearinghouse_), _GOHM_AMOUNT);
        // Loan 0 for cooler_ (collateral: 2,000 gOHM)
        (uint256 loan, ) = clearinghouse_.getLoanForCollateral(2_000 * 1e18);
        clearinghouse_.lendToCooler(cooler_, loan);
        // Loan 1 for cooler_ (collateral: 1,000 gOHM)
        (loan, ) = clearinghouse_.getLoanForCollateral(1_000 * 1e18);
        clearinghouse_.lendToCooler(cooler_, loan);
        // Loan 2 for cooler_ (collateral: 333 gOHM)
        (loan, ) = clearinghouse_.getLoanForCollateral(333 * 1e18);
        clearinghouse_.lendToCooler(cooler_, loan);
        vm.stopPrank();
        console2.log("Loans 0, 1, 2 created for cooler:", address(cooler_));
    }

    function _createCoolerAndLoans(
        Clearinghouse clearinghouse_,
        CoolerFactory coolerFactory_,
        address wallet_,
        ERC20 token_
    ) internal {
        address cooler_ = _createCooler(coolerFactory_, wallet_, token_);
        coolerA = Cooler(cooler_);

        _createLoans(clearinghouse_, coolerA, wallet_);
    }

    /// @notice Creates a new Cooler clone
    /// @dev    Not that this will be regarded as a third-party Cooler, and rejected by LoanConsolidator, as CoolerFactory has no record of it.
    function _cloneCooler(
        address owner_,
        address collateral_,
        address debt_,
        address factory_
    ) internal returns (Cooler) {
        bytes memory coolerData = abi.encodePacked(owner_, collateral_, debt_, factory_);
        return Cooler(address(coolerFactory.coolerImplementation()).clone(coolerData));
    }

    modifier givenCoolerB(ERC20 token_) {
        coolerB = Cooler(_createCooler(coolerFactory, walletB, token_));
        _;
    }

    function _createClearinghouseWithLowerLTC() internal returns (Clearinghouse) {
        ClearinghouseLowerLTC newClearinghouse = new ClearinghouseLowerLTC(
            address(ohm),
            address(gohm),
            address(staking),
            address(sdai),
            address(coolerFactory),
            address(kernel)
        );

        // Activate as a policy
        vm.prank(kernelExecutor);
        kernel.executeAction(Actions.ActivatePolicy, address(newClearinghouse));

        // Activate the new clearinghouse
        newClearinghouse.activate();
        // Rebalance the new clearinghouse
        newClearinghouse.rebalance();

        return Clearinghouse(address(newClearinghouse));
    }

    function _createClearinghouseWithHigherLTC() internal returns (Clearinghouse) {
        ClearinghouseHigherLTC newClearinghouse = new ClearinghouseHigherLTC(
            address(ohm),
            address(gohm),
            address(staking),
            address(sdai),
            address(coolerFactory),
            address(kernel)
        );

        // Activate as a policy
        vm.prank(kernelExecutor);
        kernel.executeAction(Actions.ActivatePolicy, address(newClearinghouse));

        // Activate the new clearinghouse
        newClearinghouse.activate();
        // Rebalance the new clearinghouse
        newClearinghouse.rebalance();

        return Clearinghouse(address(newClearinghouse));
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

    function _assertCoolerLoansCrossClearinghouse(
        address coolerFrom_,
        address coolerTo_,
        uint256 collateral_
    ) internal {
        // Check that coolerFrom has no open loans
        Cooler.Loan memory loan = Cooler(coolerFrom_).getLoan(0);
        assertEq(loan.collateral, 0, "coolerFrom, loan 0: collateral");
        loan = Cooler(coolerFrom_).getLoan(1);
        assertEq(loan.collateral, 0, "coolerFrom, loan 1: collateral");
        loan = Cooler(coolerFrom_).getLoan(2);
        assertEq(loan.collateral, 0, "coolerFrom, loan 2: collateral");
        vm.expectRevert();
        loan = Cooler(coolerFrom_).getLoan(3);

        // Check that coolerTo has a single open loan
        loan = Cooler(coolerTo_).getLoan(0);
        assertEq(loan.collateral, collateral_, "coolerTo, loan 0: collateral");
        vm.expectRevert();
        loan = Cooler(coolerTo_).getLoan(1);
    }

    function _assertTokenBalances(
        uint256 walletABalance,
        uint256 lenderBalance,
        uint256 collectorBalance,
        uint256 collateralBalance
    ) internal view {
        assertEq(dai.balanceOf(address(utils)), 0, "dai: utils");
        assertEq(dai.balanceOf(walletA), walletABalance, "dai: walletA");
        assertEq(dai.balanceOf(address(coolerA)), 0, "dai: coolerA");
        assertEq(dai.balanceOf(lender), lenderBalance, "dai: lender");
        assertEq(
            dai.balanceOf(address(TRSRY)),
            trsryDaiBalance + collectorBalance,
            "dai: collector"
        );
        assertEq(usds.balanceOf(address(utils)), 0, "usds: utils");
        assertEq(usds.balanceOf(walletA), 0, "usds: walletA");
        assertEq(usds.balanceOf(address(coolerA)), 0, "usds: coolerA");
        assertEq(usds.balanceOf(lender), 0, "usds: lender");
        assertEq(usds.balanceOf(address(TRSRY)), trsryUsdsBalance, "usds: collector");
        assertEq(sdai.balanceOf(address(utils)), 0, "sdai: utils");
        assertEq(sdai.balanceOf(walletA), 0, "sdai: walletA");
        assertEq(sdai.balanceOf(address(coolerA)), 0, "sdai: coolerA");
        assertEq(sdai.balanceOf(lender), 0, "sdai: lender");
        assertEq(sdai.balanceOf(address(TRSRY)), trsrySDaiBalance, "sdai: collector");
        assertEq(susds.balanceOf(address(utils)), 0, "susds: utils");
        assertEq(susds.balanceOf(walletA), 0, "susds: walletA");
        assertEq(susds.balanceOf(address(coolerA)), 0, "susds: coolerA");
        assertEq(susds.balanceOf(lender), 0, "susds: lender");
        assertEq(susds.balanceOf(address(TRSRY)), trsrySusdsBalance, "susds: collector");
        assertEq(gohm.balanceOf(address(utils)), 0, "gohm: utils");
        assertEq(gohm.balanceOf(walletA), 0, "gohm: walletA");
        assertEq(gohm.balanceOf(address(coolerA)), collateralBalance, "gohm: coolerA");
        assertEq(gohm.balanceOf(lender), 0, "gohm: lender");
        assertEq(gohm.balanceOf(address(TRSRY)), trsryGOhmBalance, "gohm: collector");
    }

    function _assertTokenBalances(
        address reserveTo_,
        address coolerFrom_,
        address coolerTo_,
        uint256 walletABalance,
        uint256 lenderBalance,
        uint256 collectorBalance,
        uint256 collateralBalance
    ) internal view {
        assertEq(dai.balanceOf(address(utils)), 0, "dai: utils");
        assertEq(
            dai.balanceOf(walletA),
            reserveTo_ == address(dai) ? walletABalance : 0,
            "dai: walletA"
        );
        assertEq(dai.balanceOf(address(coolerFrom_)), 0, "dai: coolerFrom_");
        assertEq(dai.balanceOf(address(coolerTo_)), 0, "dai: coolerTo_");
        assertEq(dai.balanceOf(lender), lenderBalance, "dai: lender");
        assertEq(
            dai.balanceOf(address(TRSRY)),
            trsryDaiBalance + (reserveTo_ == address(dai) ? collectorBalance : 0),
            "dai: collector"
        );

        assertEq(usds.balanceOf(address(utils)), 0, "usds: utils");
        assertEq(
            usds.balanceOf(walletA),
            reserveTo_ == address(usds) ? walletABalance : 0,
            "usds: walletA"
        );
        assertEq(usds.balanceOf(address(coolerFrom_)), 0, "usds: coolerFrom_");
        assertEq(usds.balanceOf(address(coolerTo_)), 0, "usds: coolerTo_");
        assertEq(usds.balanceOf(lender), 0, "usds: lender");
        assertEq(
            usds.balanceOf(address(TRSRY)),
            trsryUsdsBalance + (reserveTo_ == address(usds) ? collectorBalance : 0),
            "usds: collector"
        );

        assertEq(sdai.balanceOf(address(utils)), 0, "sdai: utils");
        assertEq(sdai.balanceOf(walletA), 0, "sdai: walletA");
        assertEq(sdai.balanceOf(address(coolerFrom_)), 0, "sdai: coolerFrom_");
        assertEq(sdai.balanceOf(address(coolerTo_)), 0, "sdai: coolerTo_");
        assertEq(sdai.balanceOf(lender), 0, "sdai: lender");
        assertEq(sdai.balanceOf(address(TRSRY)), trsrySDaiBalance, "sdai: collector");

        assertEq(susds.balanceOf(address(utils)), 0, "susds: utils");
        assertEq(susds.balanceOf(walletA), 0, "susds: walletA");
        assertEq(susds.balanceOf(address(coolerFrom_)), 0, "susds: coolerFrom_");
        assertEq(susds.balanceOf(address(coolerTo_)), 0, "susds: coolerTo_");
        assertEq(susds.balanceOf(lender), 0, "susds: lender");
        assertEq(susds.balanceOf(address(TRSRY)), trsrySusdsBalance, "susds: collector");

        assertEq(gohm.balanceOf(address(utils)), 0, "gohm: utils");
        assertEq(gohm.balanceOf(walletA), 0, "gohm: walletA");
        assertEq(
            gohm.balanceOf(address(coolerFrom_)),
            address(coolerFrom_) == address(coolerTo_) ? collateralBalance : 0,
            "gohm: coolerFrom_"
        );
        assertEq(gohm.balanceOf(address(coolerTo_)), collateralBalance, "gohm: coolerTo_");
        assertEq(gohm.balanceOf(lender), 0, "gohm: lender");
        assertEq(gohm.balanceOf(address(TRSRY)), trsryGOhmBalance, "gohm: collector");
    }

    function _assertApprovals() internal view {
        _assertApprovals(address(coolerA), address(coolerA));
    }

    function _assertApprovals(address coolerFrom_, address coolerTo_) internal view {
        assertEq(
            dai.allowance(address(utils), address(coolerFrom_)),
            0,
            "dai allowance: utils -> coolerFrom_"
        );
        assertEq(
            dai.allowance(address(utils), address(coolerTo_)),
            0,
            "dai allowance: utils -> coolerTo_"
        );
        assertEq(
            dai.allowance(address(utils), address(clearinghouse)),
            0,
            "dai allowance: utils -> clearinghouse"
        );
        assertEq(
            dai.allowance(address(utils), address(clearinghouseUsds)),
            0,
            "dai allowance: utils -> clearinghouseUsds"
        );
        assertEq(
            dai.allowance(address(utils), address(lender)),
            0,
            "dai allowance: utils -> lender"
        );

        assertEq(
            usds.allowance(address(utils), address(coolerFrom_)),
            0,
            "usds allowance: utils -> coolerFrom_"
        );
        assertEq(
            usds.allowance(address(utils), address(coolerTo_)),
            0,
            "usds allowance: utils -> coolerTo_"
        );
        assertEq(
            usds.allowance(address(utils), address(clearinghouse)),
            0,
            "usds allowance: utils -> clearinghouse"
        );
        assertEq(
            usds.allowance(address(utils), address(clearinghouseUsds)),
            0,
            "usds allowance: utils -> clearinghouseUsds"
        );
        assertEq(
            usds.allowance(address(utils), address(lender)),
            0,
            "usds allowance: utils -> lender"
        );

        assertEq(gohm.allowance(walletA, address(utils)), 0, "gohm allowance: walletA -> utils");
        assertEq(
            gohm.allowance(address(utils), address(coolerFrom_)),
            0,
            "gohm allowance: utils -> coolerFrom_"
        );
        assertEq(
            gohm.allowance(address(utils), address(coolerTo_)),
            0,
            "gohm allowance: utils -> coolerTo_"
        );
        assertEq(
            gohm.allowance(address(utils), address(clearinghouse)),
            0,
            "gohm allowance: utils -> clearinghouse"
        );
        assertEq(
            gohm.allowance(address(utils), address(clearinghouseUsds)),
            0,
            "gohm allowance: utils -> clearinghouseUsds"
        );
        assertEq(
            gohm.allowance(address(utils), address(lender)),
            0,
            "gohm allowance: utils -> lender"
        );
    }

    // ===== TESTS ===== //

    // consolidate
    // given the contract has not been activated as a policy
    //  [X] it reverts
    // given the contract has been disabled
    //  [X] it reverts
    // given clearinghouseFrom is not registered with CHREG
    //  [X] it reverts
    // given clearinghouseTo is not registered with CHREG
    //  [X] it reverts
    // given coolerFrom was not created by clearinghouseFrom's CoolerFactory
    //  [X] it reverts
    // given coolerTo was not created by clearinghouseTo's CoolerFactory
    //  [X] it reverts
    // given the caller is not the owner of coolerFrom
    //  [X] it reverts
    // given the caller is not the owner of coolerTo
    //  [X] it reverts
    // given clearinghouseFrom is not an active policy
    //  given clearinghouseFrom is disabled
    //   [X] it succeeds
    //  [X] it succeeds
    // given clearinghouseFrom is disabled
    //  [X] it succeeds
    // given clearinghouseTo is disabled
    //  [X] it reverts
    // given coolerFrom is equal to coolerTo
    //  given coolerFrom has no loans specified
    //   [X] it reverts
    //  given coolerFrom has 1 loan specified
    //   [X] it reverts
    // given coolerFrom is not equal to coolerTo
    //  given coolerFrom has no loans specified
    //   [X] it reverts
    //  given coolerFrom has 1 loan specified
    //   [X] it migrates the loan to coolerTo
    // given reserveTo is DAI
    //  given DAI spending approval has not been given to LoanConsolidator
    //   [X] it reverts
    // given reserveTo is USDS
    //  given USDS spending approval has not been given to LoanConsolidator
    //   [X] it reverts
    // given gOHM spending approval has not been given to LoanConsolidator
    //  [X] it reverts
    // given the protocol fee is non-zero
    //  [X] it transfers the protocol fee to the collector
    // given the lender fee is non-zero
    //  [X] it transfers the lender fee to the lender
    // given the protocol fee is zero
    //  [X] it succeeds, but does not transfer additional reserveTo for the protocol fee
    // given the lender fee is zero
    //  [X] it succeeds, but does not transfer additional reserveTo for the lender fee
    // when clearinghouseFrom is DAI and clearinghouseTo is USDS
    //  [X] the loans on coolerFrom are migrated to coolerTo
    //  [X] the Cooler owner receives USDS from the new loan
    // when clearinghouseFrom is USDS and clearinghouseTo is DAI
    //  [X] the loans on coolerFrom are migrated to coolerTo
    //  [X] the Cooler owner receives DAI from the new loan
    // when clearinghouseFrom is USDS and clearinghouseTo is USDS
    //  [X] the loans on coolerFrom are migrated to coolerTo
    //  [X] the Cooler owner receives USDS from the new loan
    // when clearinghouseFrom is DAI and clearinghouseTo is DAI
    //  [X] the loans on coolerFrom are migrated to coolerTo
    //  [X] the Cooler owner receives DAI from the new loan
    // given clearinghouseFrom has a lower LTC than clearinghouseTo
    //  [X] the cooler owner receives a new loan for the old principal amount based on a higher LTC/higher collateral amount
    // given clearinghouseFrom has a higher LTC than clearinghouseTo
    //  given the cooler owner does not have enough collateral for the new loan
    //   [X] it reverts
    //  [X] the Cooler owner receives a new loan for the old principal amount based on a lower LTC/lower collateral amount

    // --- consolidate --------------------------------------------

    function test_consolidate_policyNotActive_reverts() public {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(LoanConsolidator.OnlyPolicyActive.selector));

        // Consolidate loans for coolerA
        uint256[] memory idsA = _idsA();
        _consolidate(idsA);
    }

    function test_consolidate_defaultDeactivated_reverts() public givenPolicyActive {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(LoanConsolidator.OnlyConsolidatorActive.selector));

        // Consolidate loans for coolerA
        uint256[] memory idsA = _idsA();
        _consolidate(idsA);
    }

    function test_consolidate_deactivated_reverts()
        public
        givenPolicyActive
        givenActivated
        givenDeactivated
    {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(LoanConsolidator.OnlyConsolidatorActive.selector));

        // Consolidate loans for coolerA
        uint256[] memory idsA = _idsA();
        _consolidate(idsA);
    }

    function test_consolidate_thirdPartyClearinghouseFrom_reverts()
        public
        givenPolicyActive
        givenActivated
    {
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

        // Consolidate loans
        uint256[] memory idsA = _idsA();
        _consolidate(
            walletA,
            address(newClearinghouse),
            address(clearinghouse),
            address(coolerA),
            address(coolerA),
            idsA
        );
    }

    function test_consolidate_thirdPartyClearinghouseTo_reverts()
        public
        givenPolicyActive
        givenActivated
    {
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

        // Consolidate loans
        uint256[] memory idsA = _idsA();
        _consolidate(
            walletA,
            address(clearinghouse),
            address(newClearinghouse),
            address(coolerA),
            address(coolerA),
            idsA
        );
    }

    function test_consolidate_thirdPartyCoolerFrom_reverts()
        public
        givenPolicyActive
        givenActivated
    {
        // Create a new Cooler
        // It was not created by the Clearinghouse's CoolerFactory, so should be rejected
        Cooler newCooler = _cloneCooler(
            walletA,
            address(gohm),
            address(dai),
            address(coolerFactory)
        );

        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(LoanConsolidator.Params_InvalidCooler.selector));

        // Consolidate loans for coolerA into newCooler
        uint256[] memory idsA = _idsA();
        _consolidate(
            walletA,
            address(clearinghouse),
            address(clearinghouse),
            address(newCooler),
            address(coolerA),
            idsA
        );
    }

    function test_consolidate_thirdPartyCoolerTo_reverts() public givenPolicyActive givenActivated {
        // Create a new Cooler
        // It was not created by the Clearinghouse's CoolerFactory, so should be rejected
        Cooler newCooler = _cloneCooler(
            walletA,
            address(gohm),
            address(dai),
            address(coolerFactory)
        );

        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(LoanConsolidator.Params_InvalidCooler.selector));

        // Consolidate loans for coolerA into newCooler
        uint256[] memory idsA = _idsA();
        _consolidate(
            walletA,
            address(clearinghouse),
            address(clearinghouse),
            address(coolerA),
            address(newCooler),
            idsA
        );
    }

    function test_consolidate_clearinghouseFromNotActive() public givenPolicyActive givenActivated {
        uint256[] memory idsA = _idsA();

        // Create a Cooler on the USDS Clearinghouse
        address coolerUsds = _createCooler(coolerFactory, walletA, usds);
        address coolerDai = address(coolerA);

        (, uint256 interest, , uint256 protocolFee) = utils.fundsRequired(
            address(clearinghouseUsds),
            coolerDai,
            idsA
        );

        // Grant approvals
        _grantCallerApprovals(walletA, address(clearinghouseUsds), coolerDai, coolerUsds, idsA);

        // Deal fees in USDS to the wallet
        deal(address(usds), walletA, interest + protocolFee);
        // Make sure the wallet has no DAI
        deal(address(dai), walletA, 0);

        // Disable the previous clearinghouse
        vm.prank(emergency);
        clearinghouse.emergencyShutdown();

        // Consolidate loans
        _consolidate(
            walletA,
            address(clearinghouse),
            address(clearinghouseUsds),
            coolerDai,
            coolerUsds,
            idsA
        );

        _assertCoolerLoansCrossClearinghouse(coolerDai, coolerUsds, _GOHM_AMOUNT);
    }

    function test_consolidate_clearinghouseFromPolicyNotActive()
        public
        givenPolicyActive
        givenActivated
    {
        uint256[] memory idsA = _idsA();

        // Create a Cooler on the USDS Clearinghouse
        address coolerUsds = _createCooler(coolerFactory, walletA, usds);
        address coolerDai = address(coolerA);

        (, uint256 interest, , uint256 protocolFee) = utils.fundsRequired(
            address(clearinghouseUsds),
            coolerDai,
            idsA
        );

        // Grant approvals
        _grantCallerApprovals(walletA, address(clearinghouseUsds), coolerDai, coolerUsds, idsA);

        // Deal fees in USDS to the wallet
        deal(address(usds), walletA, interest + protocolFee);
        // Make sure the wallet has no DAI
        deal(address(dai), walletA, 0);

        // Uninstall the previous Clearinghouse as a policy
        vm.prank(kernelExecutor);
        kernel.executeAction(Actions.DeactivatePolicy, address(clearinghouse));

        // Consolidate loans
        _consolidate(
            walletA,
            address(clearinghouse),
            address(clearinghouseUsds),
            coolerDai,
            coolerUsds,
            idsA
        );

        _assertCoolerLoansCrossClearinghouse(coolerDai, coolerUsds, _GOHM_AMOUNT);
    }

    function test_consolidate_clearinghouseFromNotActive_clearinghouseFromPolicyNotActive_reverts()
        public
        givenPolicyActive
        givenActivated
    {
        uint256[] memory idsA = _idsA();

        // Create a Cooler on the USDS Clearinghouse
        address coolerUsds = _createCooler(coolerFactory, walletA, usds);
        address coolerDai = address(coolerA);

        (, uint256 interest, , uint256 protocolFee) = utils.fundsRequired(
            address(clearinghouseUsds),
            coolerDai,
            idsA
        );

        // Grant approvals
        _grantCallerApprovals(walletA, address(clearinghouseUsds), coolerDai, coolerUsds, idsA);

        // Deal fees in USDS to the wallet
        deal(address(usds), walletA, interest + protocolFee);
        // Make sure the wallet has no DAI
        deal(address(dai), walletA, 0);

        // Disable the previous Clearinghouse
        vm.prank(emergency);
        clearinghouse.emergencyShutdown();

        // Uninstall the previous Clearinghouse as a policy
        vm.prank(kernelExecutor);
        kernel.executeAction(Actions.DeactivatePolicy, address(clearinghouse));

        // Expect revert
        // The Clearinghouse will attempt to be defunded, which will fail
        vm.expectRevert(
            abi.encodeWithSelector(
                Module.Module_PolicyNotPermitted.selector,
                address(clearinghouse)
            )
        );

        // Consolidate loans
        _consolidate(
            walletA,
            address(clearinghouse),
            address(clearinghouseUsds),
            coolerDai,
            coolerUsds,
            idsA
        );
    }

    function test_consolidate_sameCooler_noLoans_reverts() public givenPolicyActive givenActivated {
        // Grant approvals
        _grantCallerApprovals(type(uint256).max, type(uint256).max, type(uint256).max);

        // Expect revert since no loan ids are given
        vm.expectRevert(
            abi.encodeWithSelector(LoanConsolidator.Params_InsufficientCoolerCount.selector)
        );

        // Consolidate loans, but give no ids
        uint256[] memory ids = new uint256[](0);
        _consolidate(ids);
    }

    function test_consolidate_sameCooler_oneLoan_reverts() public givenPolicyActive givenActivated {
        // Grant approvals
        _grantCallerApprovals(type(uint256).max, type(uint256).max, type(uint256).max);

        // Expect revert since no loan ids are given
        vm.expectRevert(
            abi.encodeWithSelector(LoanConsolidator.Params_InsufficientCoolerCount.selector)
        );

        // Consolidate loans, but give one id
        uint256[] memory ids = new uint256[](1);
        ids[0] = 0;
        _consolidate(ids);
    }

    function test_consolidate_differentCooler_noLoans_reverts()
        public
        givenPolicyActive
        givenActivated
    {
        uint256[] memory idsA = _idsA();

        // Deploy a Cooler on the USDS Clearinghouse
        vm.startPrank(walletA);
        address coolerUsds_ = coolerFactory.generateCooler(gohm, usds);
        Cooler coolerUsds = Cooler(coolerUsds_);
        vm.stopPrank();

        (, uint256 interest, , uint256 protocolFee) = utils.fundsRequired(
            address(clearinghouse),
            address(coolerA),
            idsA
        );

        // Grant approvals
        _grantCallerApprovals(type(uint256).max, type(uint256).max, type(uint256).max);

        // Deal fees in USDS to the wallet
        deal(address(usds), walletA, interest + protocolFee);
        // Make sure the wallet has no DAI
        deal(address(dai), walletA, 0);

        // Expect revert since no loan ids are given
        vm.expectRevert(
            abi.encodeWithSelector(LoanConsolidator.Params_InsufficientCoolerCount.selector)
        );

        // Consolidate loans, but give no ids
        idsA = new uint256[](0);
        _consolidate(
            walletA,
            address(clearinghouse),
            address(clearinghouseUsds),
            address(coolerA),
            address(coolerUsds),
            idsA
        );
    }

    function test_consolidate_differentCooler_oneLoan() public givenPolicyActive givenActivated {
        uint256[] memory idsA = _idsA();

        // Deploy a Cooler on the USDS Clearinghouse
        vm.startPrank(walletA);
        address coolerUsds_ = coolerFactory.generateCooler(gohm, usds);
        Cooler coolerUsds = Cooler(coolerUsds_);
        vm.stopPrank();

        (, uint256 interest, , uint256 protocolFee) = utils.fundsRequired(
            address(clearinghouse),
            address(coolerA),
            idsA
        );

        // Grant approvals
        _grantCallerApprovals(type(uint256).max, type(uint256).max, type(uint256).max);

        // Deal fees in USDS to the wallet
        deal(address(usds), walletA, interest + protocolFee);
        // Make sure the wallet has no DAI
        deal(address(dai), walletA, 0);

        // Get the loan principal before consolidation
        Cooler.Loan memory loanZero = coolerA.getLoan(0);
        Cooler.Loan memory loanOne = coolerA.getLoan(1);
        Cooler.Loan memory loanTwo = coolerA.getLoan(2);

        // Consolidate loans, but give only one id
        idsA = new uint256[](1);
        idsA[0] = 0;
        _consolidate(
            walletA,
            address(clearinghouse),
            address(clearinghouseUsds),
            address(coolerA),
            address(coolerUsds),
            idsA
        );

        // Assert that only loan 0 has been repaid
        assertEq(coolerA.getLoan(0).principal, 0, "cooler DAI, loan 0: principal");
        assertEq(coolerA.getLoan(1).principal, loanOne.principal, "cooler DAI, loan 1: principal");
        assertEq(coolerA.getLoan(2).principal, loanTwo.principal, "cooler DAI, loan 2: principal");
        // Assert that loan 0 has been migrated to coolerUsds
        assertEq(
            coolerUsds.getLoan(0).principal,
            loanZero.principal,
            "cooler USDS, loan 0: principal"
        );
        // Assert that coolerUsds has no other loans
        vm.expectRevert();
        coolerUsds.getLoan(1);
    }

    function test_consolidate_callerNotOwner_coolerFrom_reverts()
        public
        givenPolicyActive
        givenActivated
        givenCoolerB(dai)
    {
        uint256[] memory idsA = _idsA();

        // Grant approvals
        _grantCallerApprovals(idsA);

        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(LoanConsolidator.OnlyCoolerOwner.selector));

        // Consolidate loans
        // Do not perform as the cooler owner
        _consolidate(
            walletA,
            address(clearinghouse),
            address(clearinghouse),
            address(coolerB),
            address(coolerA),
            idsA
        );
    }

    function test_consolidate_callerNotOwner_coolerTo_reverts()
        public
        givenPolicyActive
        givenActivated
        givenCoolerB(dai)
    {
        uint256[] memory idsA = _idsA();

        // Grant approvals
        _grantCallerApprovals(idsA);

        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(LoanConsolidator.OnlyCoolerOwner.selector));

        // Consolidate loans
        // Do not perform as the cooler owner
        _consolidate(
            walletA,
            address(clearinghouse),
            address(clearinghouse),
            address(coolerA),
            address(coolerB),
            idsA
        );
    }

    function test_consolidate_insufficientGOhmApproval_reverts()
        public
        givenPolicyActive
        givenActivated
    {
        uint256[] memory idsA = _idsA();

        // Grant approvals
        (, uint256 gohmApproval, , uint256 ownerReserveTo, uint256 callerReserveTwo) = utils
            .requiredApprovals(address(clearinghouse), address(coolerA), idsA);

        _grantCallerApprovals(gohmApproval - 1, ownerReserveTo + callerReserveTwo, 0);

        // Expect revert
        vm.expectRevert("ERC20: transfer amount exceeds allowance");

        _consolidate(idsA);
    }

    function test_consolidate_insufficientDaiApproval_reverts()
        public
        givenPolicyActive
        givenActivated
    {
        uint256[] memory idsA = _idsA();

        // Grant approvals
        (, uint256 gohmApproval, , , ) = utils.requiredApprovals(
            address(clearinghouse),
            address(coolerA),
            idsA
        );

        _grantCallerApprovals(gohmApproval, 1, 0);

        // Expect revert
        vm.expectRevert("Dai/insufficient-allowance");

        _consolidate(idsA);
    }

    function test_consolidate_insufficientUsdsApproval_reverts()
        public
        givenPolicyActive
        givenActivated
    {
        uint256[] memory idsA = _idsA();

        // Create a Cooler on the USDS Clearinghouse
        address coolerUsds = _createCooler(coolerFactory, walletA, usds);

        // Grant approvals
        (, uint256 gohmApproval, , uint256 ownerReserveTo, uint256 callerReserveTo) = utils
            .requiredApprovals(address(clearinghouseUsds), address(coolerA), idsA);

        _grantCallerApprovals(gohmApproval, 0, 1);

        // Deal fees in USDS to the wallet
        deal(address(usds), walletA, ownerReserveTo + callerReserveTo);

        // Expect revert
        vm.expectRevert("Usds/insufficient-allowance");

        _consolidate(
            walletA,
            address(clearinghouse),
            address(clearinghouseUsds),
            address(coolerA),
            address(coolerUsds),
            idsA
        );
    }

    function test_consolidate_noProtocolFee() public givenPolicyActive givenActivated {
        uint256[] memory idsA = _idsA();

        // Record the amount of DAI in the wallet
        uint256 initPrincipal = dai.balanceOf(walletA);
        uint256 interestDue = _getInterestDue(idsA);

        // Grant approvals
        _grantCallerApprovals(idsA);

        // Consolidate loans
        _consolidate(idsA);

        _assertCoolerLoans(_GOHM_AMOUNT);
        _assertTokenBalances(initPrincipal - interestDue, 0, 0, _GOHM_AMOUNT);
        _assertApprovals();
    }

    function test_consolidate_noProtocolFee_fuzz(
        uint256 loanOneCollateral_,
        uint256 loanTwoCollateral_
    ) public givenPolicyActive givenActivated givenCoolerB(dai) {
        // Bound the collateral values
        loanOneCollateral_ = bound(loanOneCollateral_, 1, 1e18);
        loanTwoCollateral_ = bound(loanTwoCollateral_, 1, 1e18);

        // Fund the wallet with gOHM
        deal(address(gohm), walletB, loanOneCollateral_ + loanTwoCollateral_);

        // Approve clearinghouse to spend gOHM
        vm.prank(walletB);
        gohm.approve(address(clearinghouse), loanOneCollateral_ + loanTwoCollateral_);

        // Take loans
        {
            vm.startPrank(walletB);
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

        // Record the amount of DAI in the wallet
        uint256 initPrincipal = dai.balanceOf(walletB);
        uint256 interestDue = _getInterestDue(address(coolerB), loanIds);

        // Grant approvals
        _grantCallerApprovals(
            walletB,
            address(clearinghouse),
            address(coolerB),
            address(coolerB),
            loanIds
        );

        // Consolidate loans
        _consolidate(
            walletB,
            address(clearinghouse),
            address(clearinghouse),
            address(coolerB),
            address(coolerB),
            loanIds
        );

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

    function test_consolidate_lenderFee()
        public
        givenPolicyActive
        givenActivated
        givenAdminHasRole
        givenMockFlashloanLender
        givenMockFlashloanLenderFee(1000) // 10%
        givenMockFlashloanLenderHasBalance(20_000_000e18)
    {
        uint256[] memory idsA = _idsA();

        // Record the initial debt balance
        (uint256 totalPrincipal, ) = clearinghouse.getLoanForCollateral(_GOHM_AMOUNT);

        // Record the amount of DAI in the wallet
        uint256 initPrincipal = dai.balanceOf(walletA);
        (, uint256 interest, , uint256 protocolFee) = utils.fundsRequired(
            address(clearinghouse),
            address(coolerA),
            idsA
        );

        // Grant approvals
        _grantCallerApprovals(
            walletA,
            address(clearinghouse),
            address(coolerA),
            address(coolerA),
            idsA
        );

        // Calculate the expected lender fee
        uint256 lenderFee = MockFlashloanLender(lender).flashFee(address(dai), totalPrincipal);
        uint256 expectedLenderBalance = 20_000_000e18 + lenderFee;

        // Consolidate loans
        _consolidate(idsA);

        _assertCoolerLoans(_GOHM_AMOUNT);
        _assertTokenBalances(
            initPrincipal - interest - protocolFee - lenderFee,
            expectedLenderBalance,
            protocolFee,
            _GOHM_AMOUNT
        );
        _assertApprovals();
    }

    function test_consolidate_protocolFee()
        public
        givenPolicyActive
        givenActivated
        givenAdminHasRole
        givenProtocolFee(1000) // 1%
    {
        uint256[] memory idsA = _idsA();

        // Record the amount of DAI in the wallet
        uint256 initPrincipal = dai.balanceOf(walletA);
        (, uint256 interest, , uint256 protocolFee) = utils.fundsRequired(
            address(clearinghouse),
            address(coolerA),
            idsA
        );

        // Grant approvals
        _grantCallerApprovals(
            walletA,
            address(clearinghouse),
            address(coolerA),
            address(coolerA),
            idsA
        );

        // Consolidate loans
        _consolidate(idsA);

        _assertCoolerLoans(_GOHM_AMOUNT);
        _assertTokenBalances(initPrincipal - interest - protocolFee, 0, protocolFee, _GOHM_AMOUNT);
        _assertApprovals();
    }

    function test_consolidate_noProtocolFee_disabledClearinghouse_reverts()
        public
        givenPolicyActive
        givenActivated
    {
        // Disable the Clearinghouse
        vm.prank(emergency);
        clearinghouse.emergencyShutdown();

        uint256[] memory idsA = _idsA();

        // Grant approvals
        _grantCallerApprovals(idsA);

        // Expect revert
        vm.expectRevert("SavingsDai/insufficient-balance");

        // Consolidate loans
        _consolidate(
            walletA,
            address(clearinghouse),
            address(clearinghouse),
            address(coolerA),
            address(coolerA),
            idsA
        );
    }

    function test_consolidate_protocolFee_daiToUsds()
        public
        givenPolicyActive
        givenActivated
        givenAdminHasRole
        givenProtocolFee(1000) // 1%
    {
        uint256[] memory idsA = _idsA();

        // Create a Cooler on the USDS Clearinghouse
        address coolerUsds = _createCooler(coolerFactory, walletA, usds);
        address coolerDai = address(coolerA);

        (, uint256 interest, , uint256 protocolFee) = utils.fundsRequired(
            address(clearinghouseUsds),
            coolerDai,
            idsA
        );

        // Grant approvals
        _grantCallerApprovals(walletA, address(clearinghouseUsds), coolerDai, coolerUsds, idsA);

        // Deal fees in USDS to the wallet
        deal(address(usds), walletA, interest + protocolFee);
        // Make sure the wallet has no DAI
        deal(address(dai), walletA, 0);

        // Record the amount of USDS in the wallet
        uint256 initPrincipal = usds.balanceOf(walletA);

        // Consolidate loans
        _consolidate(
            walletA,
            address(clearinghouse),
            address(clearinghouseUsds),
            coolerDai,
            coolerUsds,
            idsA
        );

        _assertCoolerLoansCrossClearinghouse(coolerDai, coolerUsds, _GOHM_AMOUNT);
        _assertTokenBalances(
            address(usds),
            coolerDai,
            coolerUsds,
            initPrincipal - interest - protocolFee,
            0,
            protocolFee,
            _GOHM_AMOUNT
        );
        _assertApprovals(coolerDai, coolerUsds);
    }

    function test_consolidate_protocolFee_usdsToDai()
        public
        givenPolicyActive
        givenActivated
        givenAdminHasRole
        givenProtocolFee(1000) // 1%
    {
        uint256[] memory idsA = _idsA();

        // Cache before it gets overwritten
        address coolerDai = address(coolerA);

        // Create cooler loans on the USDS Clearinghouse
        deal(address(gohm), walletA, _GOHM_AMOUNT);
        _createCoolerAndLoans(clearinghouseUsds, coolerFactory, walletA, usds);
        address coolerUsds = address(coolerA);
        (, uint256 interest, , uint256 protocolFee) = utils.fundsRequired(
            address(clearinghouse),
            coolerUsds,
            idsA
        );

        // Grant approvals
        _grantCallerApprovals(walletA, address(clearinghouse), coolerUsds, coolerDai, idsA);

        // Deal fees in DAI to the wallet
        deal(address(dai), walletA, interest + protocolFee);
        // Make sure the wallet has no USDS
        deal(address(usds), walletA, 0);

        // Record the amount of DAI in the wallet
        uint256 initPrincipal = dai.balanceOf(walletA);

        // Consolidate loans
        _consolidate(
            walletA,
            address(clearinghouseUsds),
            address(clearinghouse),
            coolerUsds,
            coolerDai,
            idsA
        );

        // Check that coolerUsds has no loans
        assertEq(Cooler(coolerUsds).getLoan(0).collateral, 0, "coolerUsds: loan 0: collateral");
        assertEq(Cooler(coolerUsds).getLoan(1).collateral, 0, "coolerUsds: loan 1: collateral");
        assertEq(Cooler(coolerUsds).getLoan(2).collateral, 0, "coolerUsds: loan 2: collateral");
        vm.expectRevert();
        Cooler(coolerUsds).getLoan(3);

        // Check that coolerDai has the previous 3 loans
        assertEq(
            Cooler(coolerDai).getLoan(0).collateral,
            2_000 * 1e18,
            "coolerDai: loan 0: collateral"
        );
        assertEq(
            Cooler(coolerDai).getLoan(1).collateral,
            1_000 * 1e18,
            "coolerDai: loan 1: collateral"
        );
        assertEq(
            Cooler(coolerDai).getLoan(2).collateral,
            333 * 1e18,
            "coolerDai: loan 2: collateral"
        );
        // Check that it has the consolidated loan
        assertEq(
            Cooler(coolerDai).getLoan(3).collateral,
            _GOHM_AMOUNT,
            "coolerDai: loan 3: collateral"
        );
        // No more loans
        vm.expectRevert();
        Cooler(coolerDai).getLoan(4);

        _assertTokenBalances(
            address(dai),
            coolerUsds,
            coolerDai,
            initPrincipal - interest - protocolFee,
            0,
            protocolFee,
            _GOHM_AMOUNT + _GOHM_AMOUNT // 2x loans
        );
        _assertApprovals(coolerUsds, coolerDai);
    }

    function test_consolidate_protocolFee_usdsToUsds()
        public
        givenPolicyActive
        givenActivated
        givenAdminHasRole
        givenProtocolFee(1000) // 1%
    {
        uint256[] memory idsA = _idsA();

        // Create coolers
        deal(address(gohm), walletA, _GOHM_AMOUNT);
        _createCoolerAndLoans(clearinghouseUsds, coolerFactory, walletA, usds);
        address coolerUsds = address(coolerA);

        (, uint256 interest, , uint256 protocolFee) = utils.fundsRequired(
            address(clearinghouseUsds),
            coolerUsds,
            idsA
        );

        // Grant approvals
        _grantCallerApprovals(walletA, address(clearinghouseUsds), coolerUsds, coolerUsds, idsA);

        // Deal fees in USDS to the wallet
        deal(address(usds), walletA, interest + protocolFee);
        // Make sure the wallet has no DAI
        deal(address(dai), walletA, 0);

        // Record the amount of USDS in the wallet
        uint256 initPrincipal = usds.balanceOf(walletA);

        // Consolidate loans
        _consolidate(
            walletA,
            address(clearinghouseUsds),
            address(clearinghouseUsds),
            coolerUsds,
            coolerUsds,
            idsA
        );

        _assertCoolerLoans(_GOHM_AMOUNT);
        _assertTokenBalances(
            address(usds),
            coolerUsds,
            coolerUsds,
            initPrincipal - interest - protocolFee,
            0,
            protocolFee,
            _GOHM_AMOUNT
        );
        _assertApprovals(coolerUsds, coolerUsds);
    }

    function test_consolidate_clearinghouseFromLowerLTC() public givenPolicyActive givenActivated {
        // Create a new Clearinghouse with a higher LTC
        Clearinghouse newClearinghouse = _createClearinghouseWithHigherLTC();

        // Calculate the collateral required for the existing loans
        (uint256 existingPrincipal, ) = clearinghouse.getLoanForCollateral(_GOHM_AMOUNT);
        uint256 newCollateralRequired = newClearinghouse.getCollateralForLoan(existingPrincipal);

        uint256[] memory idsA = _idsA();

        // Record the amount of DAI in the wallet
        uint256 initPrincipal = dai.balanceOf(walletA);
        uint256 interestDue = _getInterestDue(idsA);

        // Grant approvals
        _grantCallerApprovals(
            walletA,
            address(newClearinghouse),
            address(coolerA),
            address(coolerA),
            idsA
        );

        // Consolidate loans
        _consolidate(
            walletA,
            address(clearinghouse),
            address(newClearinghouse),
            address(coolerA),
            address(coolerA),
            idsA
        );

        _assertCoolerLoans(newCollateralRequired);
        _assertApprovals();

        // WalletA should have received the principal amount
        assertEq(dai.balanceOf(walletA), initPrincipal - interestDue, "walletA: dai balance");
        // Balance of gOHM should be the old collateral amount - new collateral required
        assertEq(
            gohm.balanceOf(walletA),
            _GOHM_AMOUNT - newCollateralRequired,
            "walletA: gOHM balance"
        );
        // Balance of gOHM in the cooler should be the new collateral required
        assertEq(gohm.balanceOf(address(coolerA)), newCollateralRequired, "coolerA: gOHM balance");
        // Balance of gOHM on the LoanConsolidator should be 0
        assertEq(gohm.balanceOf(address(utils)), 0, "policy: gOHM balance");
    }

    function test_consolidate_clearinghouseFromHigherLTC_insufficientCollateral_reverts()
        public
        givenPolicyActive
        givenActivated
    {
        // Create a new Clearinghouse with a lower LTC
        Clearinghouse newClearinghouse = _createClearinghouseWithLowerLTC();

        // Do NOT deal more collateral to the wallet

        uint256[] memory idsA = _idsA();

        // Grant approvals
        _grantCallerApprovals(
            walletA,
            address(newClearinghouse),
            address(coolerA),
            address(coolerA),
            idsA
        );

        // Expect revert
        vm.expectRevert("ERC20: transfer amount exceeds balance");

        // Consolidate loans
        _consolidate(
            walletA,
            address(clearinghouse),
            address(newClearinghouse),
            address(coolerA),
            address(coolerA),
            idsA
        );
    }

    function test_consolidate_clearinghouseFromHigherLTC() public givenPolicyActive givenActivated {
        // Create a new Clearinghouse with a lower LTC
        Clearinghouse newClearinghouse = _createClearinghouseWithLowerLTC();

        // Calculate the collateral required for the existing loans
        (uint256 existingPrincipal, ) = clearinghouse.getLoanForCollateral(_GOHM_AMOUNT);
        uint256 newCollateralRequired = newClearinghouse.getCollateralForLoan(existingPrincipal);

        // Deal the difference in collateral to the wallet
        deal(address(gohm), walletA, newCollateralRequired - _GOHM_AMOUNT);

        uint256[] memory idsA = _idsA();

        // Record the amount of DAI in the wallet
        uint256 initPrincipal = dai.balanceOf(walletA);
        uint256 interestDue = _getInterestDue(idsA);

        // Grant approvals
        _grantCallerApprovals(
            walletA,
            address(newClearinghouse),
            address(coolerA),
            address(coolerA),
            idsA
        );

        // Consolidate loans
        _consolidate(
            walletA,
            address(clearinghouse),
            address(newClearinghouse),
            address(coolerA),
            address(coolerA),
            idsA
        );

        _assertCoolerLoans(newCollateralRequired);
        _assertApprovals();

        // WalletA should have received the principal amount
        assertEq(dai.balanceOf(walletA), initPrincipal - interestDue, "walletA: dai balance");
        // Balance of gOHM should be 0, as the new collateral amount was used
        assertEq(gohm.balanceOf(walletA), 0, "walletA: gOHM balance");
        // Balance of gOHM in the cooler should be the new collateral required
        assertEq(gohm.balanceOf(address(coolerA)), newCollateralRequired, "coolerA: gOHM balance");
        // Balance of gOHM on the LoanConsolidator should be 0
        assertEq(gohm.balanceOf(address(utils)), 0, "policy: gOHM balance");
    }

    // consolidateWithNewOwner
    // given the contract has not been activated as a policy
    //  [X] it reverts
    // given the contract has been disabled
    //  [X] it reverts
    // given clearinghouseFrom is not registered with CHREG
    //  [X] it reverts
    // given clearinghouseTo is not registered with CHREG
    //  [X] it reverts
    // given coolerFrom was not created by clearinghouseFrom's CoolerFactory
    //  [X] it reverts
    // given coolerTo was not created by clearinghouseTo's CoolerFactory
    //  [X] it reverts
    // given the caller is not the owner of coolerFrom
    //  [X] it reverts
    // given the owner of coolerFrom is the same as the owner of coolerTo
    //  [X] it reverts
    // given clearinghouseTo is disabled
    //  [X] it reverts
    // given coolerFrom is equal to coolerTo
    //  [X] it reverts
    // given coolerFrom is not equal to coolerTo
    //  given coolerFrom has no loans specified
    //   [X] it reverts
    //  given coolerFrom has 1 loan specified
    //   [X] it migrates the loan to coolerTo
    // given reserveTo is DAI
    //  given DAI spending approval has not been given to LoanConsolidator
    //   [X] it reverts
    // given reserveTo is USDS
    //  given USDS spending approval has not been given to LoanConsolidator
    //   [X] it reverts
    // given gOHM spending approval has not been given to LoanConsolidator
    //  [X] it reverts
    // given the protocol fee is non-zero
    //  [X] it transfers the protocol fee to the collector
    // given the lender fee is non-zero
    //  [X] it transfers the lender fee to the lender
    // given the protocol fee is zero
    //  [X] it succeeds, but does not transfer additional reserveTo for the protocol fee
    // given the lender fee is zero
    //  [X] it succeeds, but does not transfer additional reserveTo for the lender fee
    // when clearinghouseFrom is DAI and clearinghouseTo is USDS
    //  [X] the loans on coolerFrom are migrated to coolerTo
    //  [X] the Cooler owner receives USDS from the new loan
    // when clearinghouseFrom is USDS and clearinghouseTo is DAI
    //  [X] the loans on coolerFrom are migrated to coolerTo
    //  [X] the Cooler owner receives DAI from the new loan
    // when clearinghouseFrom is USDS and clearinghouseTo is USDS
    //  [X] the loans on coolerFrom are migrated to coolerTo
    //  [X] the Cooler owner receives USDS from the new loan
    // when clearinghouseFrom is DAI and clearinghouseTo is DAI
    //  [X] the loans on coolerFrom are migrated to coolerTo
    //  [X] the Cooler owner receives DAI from the new loan

    // --- consolidateWithNewOwner --------------------------------------------

    function test_consolidateWithNewOwner_policyNotActive_reverts() public givenCoolerB(dai) {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(LoanConsolidator.OnlyPolicyActive.selector));

        // Consolidate loans for coolerA
        uint256[] memory idsA = _idsA();
        _consolidateWithNewOwner(
            walletA,
            address(clearinghouse),
            address(clearinghouse),
            address(coolerA),
            address(coolerB),
            idsA
        );
    }

    function test_consolidateWithNewOwner_deactivated_reverts()
        public
        givenPolicyActive
        givenActivated
        givenDeactivated
        givenAdminHasRole
        givenCoolerB(dai)
    {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(LoanConsolidator.OnlyConsolidatorActive.selector));

        // Consolidate loans for coolerA
        uint256[] memory idsA = _idsA();
        _consolidateWithNewOwner(
            walletA,
            address(clearinghouse),
            address(clearinghouse),
            address(coolerA),
            address(coolerB),
            idsA
        );
    }

    function test_consolidateWithNewOwner_thirdPartyClearinghouseFrom_reverts()
        public
        givenPolicyActive
        givenActivated
        givenCoolerB(dai)
    {
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

        // Consolidate loans
        uint256[] memory idsA = _idsA();
        _consolidateWithNewOwner(
            walletA,
            address(newClearinghouse),
            address(clearinghouse),
            address(coolerA),
            address(coolerB),
            idsA
        );
    }

    function test_consolidateWithNewOwner_thirdPartyClearinghouseTo_reverts()
        public
        givenPolicyActive
        givenActivated
        givenCoolerB(dai)
    {
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

        // Consolidate loans
        uint256[] memory idsA = _idsA();
        _consolidateWithNewOwner(
            walletA,
            address(clearinghouse),
            address(newClearinghouse),
            address(coolerA),
            address(coolerB),
            idsA
        );
    }

    function test_consolidateWithNewOwner_thirdPartyCoolerFrom_reverts()
        public
        givenPolicyActive
        givenActivated
        givenCoolerB(dai)
    {
        // Create a new Cooler
        // It was not created by the Clearinghouse's CoolerFactory, so should be rejected
        Cooler newCooler = _cloneCooler(
            walletA,
            address(gohm),
            address(dai),
            address(coolerFactory)
        );

        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(LoanConsolidator.Params_InvalidCooler.selector));

        // Consolidate loans for coolerA into newCooler
        uint256[] memory idsA = _idsA();
        _consolidateWithNewOwner(
            walletA,
            address(clearinghouse),
            address(clearinghouse),
            address(newCooler),
            address(coolerB),
            idsA
        );
    }

    function test_consolidateWithNewOwner_thirdPartyCoolerTo_reverts()
        public
        givenPolicyActive
        givenActivated
    {
        // Create a new Cooler
        // It was not created by the Clearinghouse's CoolerFactory, so should be rejected
        Cooler newCooler = _cloneCooler(
            walletA,
            address(gohm),
            address(dai),
            address(coolerFactory)
        );

        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(LoanConsolidator.Params_InvalidCooler.selector));

        // Consolidate loans for coolerA into newCooler
        uint256[] memory idsA = _idsA();
        _consolidateWithNewOwner(
            walletA,
            address(clearinghouse),
            address(clearinghouse),
            address(coolerA),
            address(newCooler),
            idsA
        );
    }

    function test_consolidateWithNewOwner_sameCooler_reverts()
        public
        givenPolicyActive
        givenActivated
    {
        uint256[] memory idsA = _idsA();

        // Grant approvals
        _grantCallerApprovals(
            walletA,
            address(clearinghouse),
            address(coolerA),
            address(coolerA),
            idsA
        );

        // Expect revert since the cooler is the same
        vm.expectRevert(abi.encodeWithSelector(LoanConsolidator.Params_InvalidCooler.selector));

        // Consolidate loans
        _consolidateWithNewOwner(
            walletA,
            address(clearinghouse),
            address(clearinghouse),
            address(coolerA),
            address(coolerA),
            idsA
        );
    }

    function test_consolidateWithNewOwner_sameOwner_reverts()
        public
        givenPolicyActive
        givenActivated
    {
        uint256[] memory idsA = _idsA();

        // Create a new Cooler on the USDS Clearinghouse
        vm.startPrank(walletA);
        address coolerUsds_ = coolerFactory.generateCooler(gohm, usds);
        Cooler coolerUsds = Cooler(coolerUsds_);
        vm.stopPrank();

        // Grant approvals
        _grantCallerApprovals(
            walletA,
            address(clearinghouse),
            address(coolerA),
            address(coolerA),
            idsA
        );

        // Expect revert since the owner is the same
        vm.expectRevert(abi.encodeWithSelector(LoanConsolidator.Params_InvalidCooler.selector));

        // Consolidate loans
        _consolidateWithNewOwner(
            walletA,
            address(clearinghouse),
            address(clearinghouseUsds),
            address(coolerA),
            address(coolerUsds),
            idsA
        );
    }

    function test_consolidateWithNewOwner_noLoans_reverts()
        public
        givenPolicyActive
        givenActivated
        givenCoolerB(dai)
    {
        uint256[] memory idsA = new uint256[](0);

        (, uint256 interest, , uint256 protocolFee) = utils.fundsRequired(
            address(clearinghouse),
            address(coolerA),
            idsA
        );

        // Grant approvals
        _grantCallerApprovals(
            walletA,
            address(clearinghouse),
            address(coolerA),
            address(coolerB),
            idsA
        );

        // Deal fees in DAI to the wallet
        deal(address(dai), walletA, interest + protocolFee);

        // Expect revert since no loan ids are given
        vm.expectRevert(
            abi.encodeWithSelector(LoanConsolidator.Params_InsufficientCoolerCount.selector)
        );

        // Consolidate loans for coolerA
        _consolidateWithNewOwner(
            walletA,
            address(clearinghouse),
            address(clearinghouse),
            address(coolerA),
            address(coolerB),
            idsA
        );
    }

    function test_consolidateWithNewOwner_oneLoan()
        public
        givenPolicyActive
        givenActivated
        givenCoolerB(dai)
    {
        uint256[] memory idsA = new uint256[](1);
        idsA[0] = 0;

        (, uint256 interest, , uint256 protocolFee) = utils.fundsRequired(
            address(clearinghouse),
            address(coolerA),
            idsA
        );

        // Grant approvals
        _grantCallerApprovals(
            walletA,
            address(clearinghouse),
            address(coolerA),
            address(coolerB),
            idsA
        );

        // Deal fees in DAI to the wallet
        deal(address(dai), walletA, interest + protocolFee);

        // Get the loan principal before consolidation
        Cooler.Loan memory loanZero = coolerA.getLoan(0);
        Cooler.Loan memory loanOne = coolerA.getLoan(1);
        Cooler.Loan memory loanTwo = coolerA.getLoan(2);

        // Consolidate loans for coolerA
        _consolidateWithNewOwner(
            walletA,
            address(clearinghouse),
            address(clearinghouse),
            address(coolerA),
            address(coolerB),
            idsA
        );

        // Assert that only loan 0 has been repaid
        assertEq(coolerA.getLoan(0).principal, 0, "cooler A, loan 0: principal");
        assertEq(coolerA.getLoan(1).principal, loanOne.principal, "cooler A, loan 1: principal");
        assertEq(coolerA.getLoan(2).principal, loanTwo.principal, "cooler A, loan 2: principal");
        // Assert that loan 0 has been migrated to coolerB
        assertEq(coolerB.getLoan(0).principal, loanZero.principal, "cooler B, loan 0: principal");
        // Assert that coolerB has no other loans
        vm.expectRevert();
        coolerB.getLoan(1);
    }

    function test_consolidateWithNewOwner_callerNotOwner_coolerFrom_reverts()
        public
        givenPolicyActive
        givenActivated
        givenCoolerB(dai)
    {
        uint256[] memory idsA = _idsA();

        // Grant approvals
        _grantCallerApprovals(
            walletB,
            address(clearinghouse),
            address(coolerA),
            address(coolerB),
            idsA
        );

        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(LoanConsolidator.OnlyCoolerOwner.selector));

        // Consolidate loans for coolerA
        // Do not perform as the cooler owner
        _consolidateWithNewOwner(
            walletB,
            address(clearinghouse),
            address(clearinghouse),
            address(coolerA),
            address(coolerB),
            idsA
        );
    }

    function test_consolidateWithNewOwner_insufficientGOhmApproval_reverts()
        public
        givenPolicyActive
        givenActivated
        givenCoolerB(dai)
    {
        uint256[] memory idsA = _idsA();

        // Grant approvals
        (, uint256 gohmApproval, , uint256 ownerReserveTo, uint256 callerReserveTwo) = utils
            .requiredApprovals(address(clearinghouse), address(coolerA), idsA);

        _grantCallerApprovals(gohmApproval - 1, ownerReserveTo + callerReserveTwo, 0);

        // Expect revert
        vm.expectRevert("ERC20: transfer amount exceeds allowance");

        // Consolidate loans for coolerA
        _consolidateWithNewOwner(
            walletA,
            address(clearinghouse),
            address(clearinghouse),
            address(coolerA),
            address(coolerB),
            idsA
        );
    }

    function test_consolidateWithNewOwner_insufficientDaiApproval_reverts()
        public
        givenPolicyActive
        givenActivated
        givenCoolerB(dai)
    {
        uint256[] memory idsA = _idsA();

        // Grant approvals
        (, uint256 gohmApproval, , , ) = utils.requiredApprovals(
            address(clearinghouse),
            address(coolerA),
            idsA
        );

        _grantCallerApprovals(gohmApproval, 1, 0);

        // Expect revert
        vm.expectRevert("Dai/insufficient-allowance");

        // Consolidate loans for coolerA
        _consolidateWithNewOwner(
            walletA,
            address(clearinghouse),
            address(clearinghouse),
            address(coolerA),
            address(coolerB),
            idsA
        );
    }

    function test_consolidateWithNewOwner_insufficientUsdsApproval_reverts()
        public
        givenPolicyActive
        givenActivated
        givenCoolerB(usds)
    {
        uint256[] memory idsA = _idsA();

        // Grant approvals
        (, uint256 gohmApproval, , uint256 ownerReserveTo, uint256 callerReserveTo) = utils
            .requiredApprovals(address(clearinghouseUsds), address(coolerA), idsA);

        _grantCallerApprovals(gohmApproval, 0, 1);

        // Deal fees in USDS to the wallet
        deal(address(usds), walletA, ownerReserveTo + callerReserveTo);

        // Expect revert
        vm.expectRevert("Usds/insufficient-allowance");

        // Consolidate loans for coolerA
        _consolidateWithNewOwner(
            walletA,
            address(clearinghouse),
            address(clearinghouseUsds),
            address(coolerA),
            address(coolerB),
            idsA
        );
    }

    function test_consolidateWithNewOwner_noProtocolFee()
        public
        givenPolicyActive
        givenActivated
        givenCoolerB(dai)
    {
        uint256[] memory idsA = _idsA();

        // Record the amount of DAI in the wallet
        uint256 initPrincipal = dai.balanceOf(walletA);
        uint256 interestDue = _getInterestDue(idsA);

        // Grant approvals
        _grantCallerApprovals(
            walletA,
            address(clearinghouse),
            address(coolerA),
            address(coolerB),
            idsA
        );

        // Consolidate loans for coolerA
        _consolidateWithNewOwner(
            walletA,
            address(clearinghouse),
            address(clearinghouse),
            address(coolerA),
            address(coolerB),
            idsA
        );

        _assertCoolerLoansCrossClearinghouse(address(coolerA), address(coolerB), _GOHM_AMOUNT);
        _assertTokenBalances(
            address(dai),
            address(coolerA),
            address(coolerB),
            initPrincipal - interestDue,
            0,
            0,
            _GOHM_AMOUNT
        );
        _assertApprovals(address(coolerA), address(coolerB));
    }

    function test_consolidateWithNewOwner_lenderFee()
        public
        givenPolicyActive
        givenActivated
        givenCoolerB(dai)
        givenAdminHasRole
        givenMockFlashloanLender
        givenMockFlashloanLenderFee(100) // 1%
        givenMockFlashloanLenderHasBalance(20_000_000e18)
    {
        uint256[] memory idsA = _idsA();

        // Record the initial debt balance
        (uint256 totalPrincipal, ) = clearinghouse.getLoanForCollateral(_GOHM_AMOUNT);

        // Record the amount of DAI in the wallet
        uint256 initPrincipal = dai.balanceOf(walletA);
        (, uint256 interest, , uint256 protocolFee) = utils.fundsRequired(
            address(clearinghouse),
            address(coolerA),
            idsA
        );

        // Grant approvals
        _grantCallerApprovals(
            walletA,
            address(clearinghouse),
            address(coolerA),
            address(coolerB),
            idsA
        );

        // Calculate the expected lender fee
        uint256 lenderFee = MockFlashloanLender(lender).flashFee(address(dai), totalPrincipal);
        uint256 expectedLenderBalance = 20_000_000e18 + lenderFee;

        // Consolidate loans
        _consolidateWithNewOwner(
            walletA,
            address(clearinghouse),
            address(clearinghouse),
            address(coolerA),
            address(coolerB),
            idsA
        );

        _assertCoolerLoansCrossClearinghouse(address(coolerA), address(coolerB), _GOHM_AMOUNT);
        _assertTokenBalances(
            address(dai),
            address(coolerA),
            address(coolerB),
            initPrincipal - interest - protocolFee - lenderFee,
            expectedLenderBalance,
            protocolFee,
            _GOHM_AMOUNT
        );
        _assertApprovals(address(coolerA), address(coolerB));
    }

    function test_consolidateWithNewOwner_protocolFee()
        public
        givenPolicyActive
        givenActivated
        givenCoolerB(dai)
        givenAdminHasRole
        givenProtocolFee(1000) // 1%
    {
        uint256[] memory idsA = _idsA();

        // Record the amount of DAI in the wallet
        uint256 initPrincipal = dai.balanceOf(walletA);
        (, uint256 interest, , uint256 protocolFee) = utils.fundsRequired(
            address(clearinghouse),
            address(coolerA),
            idsA
        );

        // Grant approvals
        _grantCallerApprovals(
            walletA,
            address(clearinghouse),
            address(coolerA),
            address(coolerB),
            idsA
        );

        // Consolidate loans
        _consolidateWithNewOwner(
            walletA,
            address(clearinghouse),
            address(clearinghouse),
            address(coolerA),
            address(coolerB),
            idsA
        );

        _assertCoolerLoansCrossClearinghouse(address(coolerA), address(coolerB), _GOHM_AMOUNT);
        _assertTokenBalances(
            address(dai),
            address(coolerA),
            address(coolerB),
            initPrincipal - interest - protocolFee,
            0,
            protocolFee,
            _GOHM_AMOUNT
        );
        _assertApprovals(address(coolerA), address(coolerB));
    }

    function test_consolidateWithNewOwner_disabledClearinghouse_reverts()
        public
        givenPolicyActive
        givenActivated
        givenCoolerB(dai)
    {
        // Disable the Clearinghouse
        vm.prank(emergency);
        clearinghouse.emergencyShutdown();

        uint256[] memory idsA = _idsA();

        // Grant approvals
        _grantCallerApprovals(
            walletA,
            address(clearinghouse),
            address(coolerA),
            address(coolerB),
            idsA
        );

        // Expect revert
        vm.expectRevert("SavingsDai/insufficient-balance");

        // Consolidate loans
        _consolidateWithNewOwner(
            walletA,
            address(clearinghouse),
            address(clearinghouse),
            address(coolerA),
            address(coolerB),
            idsA
        );
    }

    function test_consolidateWithNewOwner_protocolFee_daiToUsds()
        public
        givenPolicyActive
        givenActivated
        givenCoolerB(usds)
        givenAdminHasRole
        givenProtocolFee(1000) // 1%
    {
        uint256[] memory idsA = _idsA();

        (, uint256 interest, , uint256 protocolFee) = utils.fundsRequired(
            address(clearinghouseUsds),
            address(coolerA),
            idsA
        );

        // Grant approvals
        _grantCallerApprovals(
            walletA,
            address(clearinghouseUsds),
            address(coolerA),
            address(coolerB),
            idsA
        );

        // Deal fees in USDS to the wallet
        deal(address(usds), walletA, interest + protocolFee);
        // Make sure the wallet has no DAI
        deal(address(dai), walletA, 0);

        // Record the amount of USDS in the wallet
        uint256 initPrincipal = usds.balanceOf(walletA);

        // Consolidate loans
        _consolidateWithNewOwner(
            walletA,
            address(clearinghouse),
            address(clearinghouseUsds),
            address(coolerA),
            address(coolerB),
            idsA
        );

        _assertCoolerLoansCrossClearinghouse(address(coolerA), address(coolerB), _GOHM_AMOUNT);
        _assertTokenBalances(
            address(usds),
            address(coolerA),
            address(coolerB),
            initPrincipal - interest - protocolFee,
            0,
            protocolFee,
            _GOHM_AMOUNT
        );
        _assertApprovals(address(coolerA), address(coolerB));
    }

    function test_consolidateWithNewOwner_protocolFee_usdsToDai()
        public
        givenPolicyActive
        givenActivated
        givenCoolerB(dai)
        givenAdminHasRole
        givenProtocolFee(1000) // 1%
    {
        uint256[] memory idsA = _idsA();

        // Create loans for walletA on the USDS Clearinghouse
        deal(address(gohm), walletA, _GOHM_AMOUNT);
        address coolerUsds = _createCooler(coolerFactory, walletA, usds);
        _createLoans(clearinghouseUsds, Cooler(coolerUsds), walletA);
        (, uint256 interest, , uint256 protocolFee) = utils.fundsRequired(
            address(clearinghouse),
            coolerUsds,
            idsA
        );

        // Grant approvals
        _grantCallerApprovals(
            walletA,
            address(clearinghouse),
            address(coolerUsds),
            address(coolerB),
            idsA
        );

        // Deal fees in DAI to the wallet
        deal(address(dai), walletA, interest + protocolFee);
        // Make sure the wallet has no USDS
        deal(address(usds), walletA, 0);

        // Record the amount of DAI in the wallet
        uint256 initPrincipal = dai.balanceOf(walletA);

        // Consolidate loans
        _consolidateWithNewOwner(
            walletA,
            address(clearinghouseUsds),
            address(clearinghouse),
            coolerUsds,
            address(coolerB),
            idsA
        );

        // Check that coolerUsds has no loans
        _assertCoolerLoansCrossClearinghouse(address(coolerUsds), address(coolerB), _GOHM_AMOUNT);
        _assertTokenBalances(
            address(dai),
            address(coolerUsds),
            address(coolerB),
            initPrincipal - interest - protocolFee,
            0,
            protocolFee,
            _GOHM_AMOUNT
        );
        _assertApprovals(address(coolerUsds), address(coolerB));
    }

    function test_consolidateWithNewOwner_protocolFee_usdsToUsds()
        public
        givenPolicyActive
        givenActivated
        givenCoolerB(usds)
        givenAdminHasRole
        givenProtocolFee(1000) // 1%
    {
        uint256[] memory idsA = _idsA();

        // Create loans for walletA on the USDS Clearinghouse
        deal(address(gohm), walletA, _GOHM_AMOUNT);
        address coolerUsds = _createCooler(coolerFactory, walletA, usds);
        _createLoans(clearinghouseUsds, Cooler(coolerUsds), walletA);
        (, uint256 interest, , uint256 protocolFee) = utils.fundsRequired(
            address(clearinghouseUsds),
            coolerUsds,
            idsA
        );

        // Grant approvals
        _grantCallerApprovals(
            walletA,
            address(clearinghouseUsds),
            address(coolerUsds),
            address(coolerB),
            idsA
        );

        // Deal fees in USDS to the wallet
        deal(address(usds), walletA, interest + protocolFee);
        // Make sure the wallet has no DAI
        deal(address(dai), walletA, 0);

        // Record the amount of USDS in the wallet
        uint256 initPrincipal = usds.balanceOf(walletA);

        // Consolidate loans
        _consolidateWithNewOwner(
            walletA,
            address(clearinghouseUsds),
            address(clearinghouseUsds),
            coolerUsds,
            address(coolerB),
            idsA
        );

        _assertCoolerLoansCrossClearinghouse(address(coolerUsds), address(coolerB), _GOHM_AMOUNT);
        _assertTokenBalances(
            address(usds),
            address(coolerUsds),
            address(coolerB),
            initPrincipal - interest - protocolFee,
            0,
            protocolFee,
            _GOHM_AMOUNT
        );
        _assertApprovals(address(coolerUsds), address(coolerB));
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
    //  [X] it returns the correct values
    // when the caller has 1 loan
    //  [X] it returns the correct values
    // when the protocol fee is zero
    //  [X] it returns the correct values
    // when the protocol fee is non-zero
    //  [X] it returns the correct values
    // when the lender fee is non-zero
    //  [X] it returns the correct values
    // when clearinghouseFrom is DAI and clearinghouseTo is USDS
    //  [X] it provides the correct values
    // when clearinghouseFrom is USDS and clearinghouseTo is DAI
    //  [X] it provides the correct values
    // when clearinghouseFrom is USDS and clearinghouseTo is USDS
    //  [X] it provides the correct values
    // when clearinghouseFrom is DAI and clearinghouseTo is DAI
    //  [X] it provides the correct values
    // given clearinghouseFrom has a lower LTC than clearinghouseTo
    //  [X] gOHM approval is higher than the collateral amount for the existing loans
    // given clearinghouseFrom has a higher LTC than clearinghouseTo
    //  [X] gOHM approval is lower than the collateral amount for the existing loans

    function test_requiredApprovals_policyNotActive_reverts() public {
        uint256[] memory ids = _idsA();

        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(LoanConsolidator.OnlyPolicyActive.selector));

        utils.requiredApprovals(address(clearinghouse), address(coolerA), ids);
    }

    function test_requiredApprovals_noLoans() public givenPolicyActive {
        uint256[] memory ids = new uint256[](0);

        (
            address owner,
            uint256 gOhmApproval,
            address reserveTo,
            uint256 ownerReserveTo,
            uint256 callerReserveTo
        ) = utils.requiredApprovals(address(clearinghouse), address(coolerA), ids);

        assertEq(owner, walletA, "owner");
        assertEq(gOhmApproval, 0, "gOHM approval");
        assertEq(reserveTo, address(dai), "reserveTo");
        assertEq(ownerReserveTo, 0, "ownerReserveTo");
        assertEq(callerReserveTo, 0, "callerReserveTo");
    }

    function test_requiredApprovals_oneLoan() public givenPolicyActive {
        uint256[] memory ids = new uint256[](1);
        ids[0] = 0;

        (
            address owner,
            uint256 gOhmApproval,
            address reserveTo,
            uint256 ownerReserveTo,
            uint256 callerReserveTo
        ) = utils.requiredApprovals(address(clearinghouse), address(coolerA), ids);

        uint256 expectedCollateral;
        uint256 expectedPrincipal;
        uint256 expectedInterest;
        for (uint256 i = 0; i < ids.length; i++) {
            Cooler.Loan memory loan = coolerA.getLoan(ids[i]);

            expectedCollateral += loan.collateral;
            expectedPrincipal += loan.principal;
            expectedInterest += loan.interestDue;
        }

        uint256 expectedProtocolFee = 0;
        uint256 expectedLenderFee = 0;

        assertEq(owner, walletA, "owner");
        assertEq(gOhmApproval, expectedCollateral, "gOHM approval");
        assertEq(reserveTo, address(dai), "reserveTo");
        assertEq(ownerReserveTo, expectedPrincipal, "ownerReserveTo");
        assertEq(
            callerReserveTo,
            expectedInterest + expectedProtocolFee + expectedLenderFee,
            "callerReserveTo"
        );
    }

    function test_requiredApprovals_noProtocolFee() public givenPolicyActive {
        uint256[] memory ids = _idsA();

        (
            address owner_,
            uint256 gohmApproval,
            address reserveTo,
            uint256 ownerReserveTo,
            uint256 callerReserveTo
        ) = utils.requiredApprovals(address(clearinghouse), address(coolerA), ids);

        uint256 expectedPrincipal;
        uint256 expectedInterest;
        for (uint256 i = 0; i < ids.length; i++) {
            Cooler.Loan memory loan = coolerA.getLoan(ids[i]);

            expectedPrincipal += loan.principal;
            expectedInterest += loan.interestDue;
        }

        uint256 expectedProtocolFee = 0;
        uint256 expectedLenderFee = 0;

        assertEq(owner_, walletA, "owner");
        assertEq(gohmApproval, _GOHM_AMOUNT, "gOHM approval");
        assertEq(reserveTo, address(dai), "reserveTo");
        assertEq(ownerReserveTo, expectedPrincipal, "ownerReserveTo");
        assertEq(
            callerReserveTo,
            expectedInterest + expectedProtocolFee + expectedLenderFee,
            "callerReserveTo"
        );
    }

    function test_requiredApprovals_protocolFee()
        public
        givenPolicyActive
        givenAdminHasRole
        givenProtocolFee(1000) // 1%
    {
        uint256[] memory ids = _idsA();

        (
            address owner_,
            uint256 gohmApproval,
            address reserveTo,
            uint256 ownerReserveTo,
            uint256 callerReserveTo
        ) = utils.requiredApprovals(address(clearinghouse), address(coolerA), ids);

        uint256 expectedPrincipal;
        uint256 expectedInterest;
        for (uint256 i = 0; i < ids.length; i++) {
            Cooler.Loan memory loan = coolerA.getLoan(ids[i]);

            expectedPrincipal += loan.principal;
            expectedInterest += loan.interestDue;
        }

        uint256 expectedProtocolFee = ((expectedPrincipal + expectedInterest) * 1000) /
            _ONE_HUNDRED_PERCENT;
        uint256 expectedLenderFee = 0;

        assertEq(owner_, walletA, "owner");
        assertEq(gohmApproval, _GOHM_AMOUNT, "gOHM approval");
        assertEq(reserveTo, address(dai), "reserveTo");
        assertEq(ownerReserveTo, expectedPrincipal, "ownerReserveTo");
        assertEq(
            callerReserveTo,
            expectedInterest + expectedProtocolFee + expectedLenderFee,
            "callerReserveTo"
        );
    }

    function test_requiredApprovals_lenderFee()
        public
        givenPolicyActive
        givenAdminHasRole
        givenMockFlashloanLender
        givenMockFlashloanLenderFee(1000) // 10%
        givenMockFlashloanLenderHasBalance(20_000_000e18)
    {
        uint256[] memory ids = _idsA();

        (
            address owner_,
            uint256 gohmApproval,
            address reserveTo,
            uint256 ownerReserveTo,
            uint256 callerReserveTo
        ) = utils.requiredApprovals(address(clearinghouse), address(coolerA), ids);

        uint256 expectedPrincipal;
        uint256 expectedInterest;
        for (uint256 i = 0; i < ids.length; i++) {
            Cooler.Loan memory loan = coolerA.getLoan(ids[i]);

            expectedPrincipal += loan.principal;
            expectedInterest += loan.interestDue;
        }

        uint256 expectedProtocolFee = 0;
        uint256 expectedLenderFee = (expectedPrincipal * 1000) / _ONE_HUNDRED_PERCENT;

        assertEq(owner_, walletA, "owner");
        assertEq(gohmApproval, _GOHM_AMOUNT, "gOHM approval");
        assertEq(reserveTo, address(dai), "reserveTo");
        assertEq(ownerReserveTo, expectedPrincipal, "ownerReserveTo");
        assertEq(
            callerReserveTo,
            expectedInterest + expectedProtocolFee + expectedLenderFee,
            "callerReserveTo"
        );
    }

    function test_requiredApprovals_protocolFee_daiToUsds()
        public
        givenPolicyActive
        givenAdminHasRole
        givenProtocolFee(1000) // 1%
    {
        uint256[] memory ids = _idsA();

        (
            address owner_,
            uint256 gohmApproval,
            address reserveTo,
            uint256 ownerReserveTo,
            uint256 callerReserveTo
        ) = utils.requiredApprovals(address(clearinghouseUsds), address(coolerA), ids);

        uint256 expectedPrincipal;
        uint256 expectedInterest;
        for (uint256 i = 0; i < ids.length; i++) {
            Cooler.Loan memory loan = coolerA.getLoan(ids[i]);

            expectedPrincipal += loan.principal;
            expectedInterest += loan.interestDue;
        }

        uint256 expectedProtocolFee = ((expectedPrincipal + expectedInterest) * 1000) /
            _ONE_HUNDRED_PERCENT;
        uint256 expectedLenderFee = 0;

        assertEq(owner_, walletA, "owner");
        assertEq(gohmApproval, _GOHM_AMOUNT, "gOHM approval");
        assertEq(reserveTo, address(usds), "reserveTo");
        assertEq(ownerReserveTo, expectedPrincipal, "ownerReserveTo");
        assertEq(
            callerReserveTo,
            expectedInterest + expectedProtocolFee + expectedLenderFee,
            "callerReserveTo"
        );
    }

    function test_requiredApprovals_protocolFee_usdsToDai()
        public
        givenPolicyActive
        givenAdminHasRole
        givenProtocolFee(1000) // 1%
    {
        uint256[] memory ids = _idsA();

        // Create Cooler loans on the USDS Clearinghouse
        deal(address(gohm), walletA, _GOHM_AMOUNT);
        _createCoolerAndLoans(clearinghouseUsds, coolerFactory, walletA, usds);

        (
            address owner_,
            uint256 gohmApproval,
            address reserveTo,
            uint256 ownerReserveTo,
            uint256 callerReserveTo
        ) = utils.requiredApprovals(address(clearinghouse), address(coolerA), ids);

        uint256 expectedPrincipal;
        uint256 expectedInterest;
        for (uint256 i = 0; i < ids.length; i++) {
            Cooler.Loan memory loan = coolerA.getLoan(ids[i]);

            expectedPrincipal += loan.principal;
            expectedInterest += loan.interestDue;
        }

        uint256 expectedProtocolFee = ((expectedPrincipal + expectedInterest) * 1000) /
            _ONE_HUNDRED_PERCENT;
        uint256 expectedLenderFee = 0;

        assertEq(owner_, walletA, "owner");
        assertEq(gohmApproval, _GOHM_AMOUNT, "gOHM approval");
        assertEq(reserveTo, address(dai), "reserveTo");
        assertEq(ownerReserveTo, expectedPrincipal, "ownerReserveTo");
        assertEq(
            callerReserveTo,
            expectedInterest + expectedProtocolFee + expectedLenderFee,
            "callerReserveTo"
        );
    }

    function test_requiredApprovals_protocolFee_usdsToUsds()
        public
        givenPolicyActive
        givenAdminHasRole
        givenProtocolFee(1000) // 1%
    {
        uint256[] memory ids = _idsA();

        // Create Cooler loans on the USDS Clearinghouse
        deal(address(gohm), walletA, _GOHM_AMOUNT);
        _createCoolerAndLoans(clearinghouseUsds, coolerFactory, walletA, usds);

        (
            address owner_,
            uint256 gohmApproval,
            address reserveTo,
            uint256 ownerReserveTo,
            uint256 callerReserveTo
        ) = utils.requiredApprovals(address(clearinghouseUsds), address(coolerA), ids);

        uint256 expectedPrincipal;
        uint256 expectedInterest;
        for (uint256 i = 0; i < ids.length; i++) {
            Cooler.Loan memory loan = coolerA.getLoan(ids[i]);

            expectedPrincipal += loan.principal;
            expectedInterest += loan.interestDue;
        }

        uint256 expectedProtocolFee = ((expectedPrincipal + expectedInterest) * 1000) /
            _ONE_HUNDRED_PERCENT;
        uint256 expectedLenderFee = 0;

        assertEq(owner_, walletA, "owner");
        assertEq(gohmApproval, _GOHM_AMOUNT, "gOHM approval");
        assertEq(reserveTo, address(usds), "reserveTo");
        assertEq(ownerReserveTo, expectedPrincipal, "ownerReserveTo");
        assertEq(
            callerReserveTo,
            expectedInterest + expectedProtocolFee + expectedLenderFee,
            "callerReserveTo"
        );
    }

    function test_requiredApprovals_fuzz(
        uint256 loanOneCollateral_,
        uint256 loanTwoCollateral_
    ) public givenPolicyActive givenCoolerB(dai) {
        // Bound the collateral values
        loanOneCollateral_ = bound(loanOneCollateral_, 1, 1e18);
        loanTwoCollateral_ = bound(loanTwoCollateral_, 1, 1e18);

        // Fund the wallet with gOHM
        deal(address(gohm), walletB, loanOneCollateral_ + loanTwoCollateral_);

        // Approve clearinghouse to spend gOHM
        vm.prank(walletB);
        gohm.approve(address(clearinghouse), loanOneCollateral_ + loanTwoCollateral_);

        // Take loans
        uint256 totalPrincipal;
        {
            vm.startPrank(walletB);
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

    function test_requiredApprovals_clearinghouseFromLowerLTC() public givenPolicyActive {
        // Create a new Clearinghouse with a higher LTC
        Clearinghouse newClearinghouse = _createClearinghouseWithHigherLTC();

        // Calculate the collateral required for the existing loans
        (uint256 existingPrincipal, ) = clearinghouse.getLoanForCollateral(_GOHM_AMOUNT);
        uint256 newCollateralRequired = newClearinghouse.getCollateralForLoan(existingPrincipal);

        uint256[] memory loanIds = _idsA();
        (, uint256 gohmApproval, , , ) = utils.requiredApprovals(
            address(newClearinghouse),
            address(coolerA),
            loanIds
        );

        assertEq(gohmApproval, newCollateralRequired, "gOHM approval");
    }

    function test_requiredApprovals_clearinghouseFromHigherLTC() public givenPolicyActive {
        // Create a new Clearinghouse with a lower LTC
        Clearinghouse newClearinghouse = _createClearinghouseWithLowerLTC();

        // Calculate the collateral required for the existing loans
        (uint256 existingPrincipal, ) = clearinghouse.getLoanForCollateral(_GOHM_AMOUNT);
        uint256 newCollateralRequired = newClearinghouse.getCollateralForLoan(existingPrincipal);

        uint256[] memory loanIds = _idsA();
        (, uint256 gohmApproval, , , ) = utils.requiredApprovals(
            address(newClearinghouse),
            address(coolerA),
            loanIds
        );

        assertEq(gohmApproval, newCollateralRequired, "gOHM approval");
    }

    // collateralRequired
    // given clearinghouseFrom has the same LTC as clearinghouseTo
    //  [X] it returns the correct values
    // given clearinghouseFrom has a lower LTC than clearinghouseTo
    //  [X] additional collateral is 0
    // given clearinghouseFrom has a higher LTC than clearinghouseTo
    //  [X] additional collateral is required

    function test_collateralRequired_fuzz(
        uint256 loanOneCollateral_,
        uint256 loanTwoCollateral_
    ) public givenPolicyActive givenCoolerB(dai) {
        // Bound the collateral values
        loanOneCollateral_ = bound(loanOneCollateral_, 1, 1e18);
        loanTwoCollateral_ = bound(loanTwoCollateral_, 1, 1e18);

        // Fund the wallet with gOHM
        deal(address(gohm), walletB, loanOneCollateral_ + loanTwoCollateral_);

        // Approve clearinghouse to spend gOHM
        vm.prank(walletB);
        gohm.approve(address(clearinghouse), loanOneCollateral_ + loanTwoCollateral_);

        // Take loans
        uint256 totalPrincipal;
        {
            vm.startPrank(walletB);
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

    function test_collateralRequired_clearinghouseFromLowerLTC() public givenPolicyActive {
        // Create a new Clearinghouse with a higher LTC
        Clearinghouse newClearinghouse = _createClearinghouseWithHigherLTC();

        // Calculate the collateral required for the existing loans
        (uint256 existingPrincipal, ) = clearinghouse.getLoanForCollateral(_GOHM_AMOUNT);
        uint256 newCollateralRequired = newClearinghouse.getCollateralForLoan(existingPrincipal);

        uint256[] memory loanIds = _idsA();

        (
            uint256 consolidatedLoanCollateral,
            uint256 existingLoanCollateral,
            uint256 additionalCollateral
        ) = utils.collateralRequired(address(newClearinghouse), address(coolerA), loanIds);

        // Assert values
        // Consolidated loan collateral is the same as what the new Clearinghouse requires
        assertEq(consolidatedLoanCollateral, newCollateralRequired, "consolidated loan collateral");

        // Existing loan collateral is the same as what has been deposited already
        assertEq(existingLoanCollateral, _GOHM_AMOUNT, "existing loan collateral");

        // Additional collateral is 0, as less collateral is required
        assertEq(additionalCollateral, 0, "additional collateral");
    }

    function test_collateralRequired_clearinghouseFromHigherLTC() public givenPolicyActive {
        // Create a new Clearinghouse with a lower LTC
        Clearinghouse newClearinghouse = _createClearinghouseWithLowerLTC();

        // Calculate the collateral required for the existing loans
        (uint256 existingPrincipal, ) = clearinghouse.getLoanForCollateral(_GOHM_AMOUNT);
        uint256 newCollateralRequired = newClearinghouse.getCollateralForLoan(existingPrincipal);

        uint256[] memory loanIds = _idsA();

        (
            uint256 consolidatedLoanCollateral,
            uint256 existingLoanCollateral,
            uint256 additionalCollateral
        ) = utils.collateralRequired(address(newClearinghouse), address(coolerA), loanIds);

        // Assert values
        // Consolidated loan collateral is the same as what the new Clearinghouse requires
        assertEq(consolidatedLoanCollateral, newCollateralRequired, "consolidated loan collateral");

        // Existing loan collateral is the same as what has been deposited already
        assertEq(existingLoanCollateral, _GOHM_AMOUNT, "existing loan collateral");

        // Additional collateral is the difference between the existing loan collateral and what the new Clearinghouse requires
        assertEq(
            additionalCollateral,
            newCollateralRequired - _GOHM_AMOUNT,
            "additional collateral"
        );
    }

    // fundsRequired
    // given there is no protocol fee
    //  [X] it returns the correct values
    // given there is a lender fee
    //  [X] it returns the correct values
    // given the loan has interest due
    //  [X] it returns the correct values
    // given clearinghouseTo is DAI
    //  [X] it returns the correct values
    // given clearinghouseTo is USDS
    //  [X] it returns the correct values

    function test_fundsRequired_noProtocolFee() public givenPolicyActive {
        uint256[] memory ids = _idsA();

        // Calculate the interest due
        uint256 expectedPrincipal;
        uint256 expectedInterest;
        for (uint256 i = 0; i < ids.length; i++) {
            Cooler.Loan memory loan = coolerA.getLoan(ids[i]);

            expectedPrincipal += loan.principal;
            expectedInterest += loan.interestDue;
        }

        uint256 expectedProtocolFee = 0;
        uint256 expectedLenderFee = 0;

        (address reserveTo, uint256 interest, uint256 lenderFee, uint256 protocolFee) = utils
            .fundsRequired(address(clearinghouse), address(coolerA), ids);

        assertEq(reserveTo, address(dai), "reserveTo");
        assertEq(interest, expectedInterest, "interest");
        assertEq(lenderFee, expectedLenderFee, "lenderFee");
        assertEq(protocolFee, expectedProtocolFee, "protocolFee");
    }

    function test_fundsRequired_lenderFee()
        public
        givenPolicyActive
        givenAdminHasRole
        givenMockFlashloanLender
        givenMockFlashloanLenderFee(10000) // 10%
        givenMockFlashloanLenderHasBalance(20_000_000e18)
    {
        uint256[] memory ids = _idsA();

        // Calculate the interest due
        uint256 expectedPrincipal;
        uint256 expectedInterest;
        for (uint256 i = 0; i < ids.length; i++) {
            Cooler.Loan memory loan = coolerA.getLoan(ids[i]);

            expectedPrincipal += loan.principal;
            expectedInterest += loan.interestDue;
        }

        uint256 expectedProtocolFee = 0;
        uint256 expectedLenderFee = (expectedPrincipal * 10000) / _ONE_HUNDRED_PERCENT;

        (address reserveTo, uint256 interest, uint256 lenderFee, uint256 protocolFee) = utils
            .fundsRequired(address(clearinghouse), address(coolerA), ids);

        assertEq(reserveTo, address(dai), "reserveTo");
        assertEq(interest, expectedInterest, "interest");
        assertEq(lenderFee, expectedLenderFee, "lenderFee");
        assertEq(protocolFee, expectedProtocolFee, "protocolFee");
    }

    function test_fundsRequired_interestDue()
        public
        givenPolicyActive
        givenAdminHasRole
        givenProtocolFee(1000)
    {
        // Warp to the future, so that there is interest due
        vm.warp(block.timestamp + 1 days);

        uint256[] memory ids = _idsA();

        // Calculate the interest due
        uint256 expectedPrincipal;
        uint256 expectedInterest;
        for (uint256 i = 0; i < ids.length; i++) {
            Cooler.Loan memory loan = coolerA.getLoan(ids[i]);

            expectedPrincipal += loan.principal;
            expectedInterest += loan.interestDue;
        }

        uint256 expectedProtocolFee = ((expectedPrincipal + expectedInterest) * 1000) /
            _ONE_HUNDRED_PERCENT;
        uint256 expectedLenderFee = 0;

        (address reserveTo, uint256 interest, uint256 lenderFee, uint256 protocolFee) = utils
            .fundsRequired(address(clearinghouse), address(coolerA), ids);

        assertEq(reserveTo, address(dai), "reserveTo");
        assertEq(interest, expectedInterest, "interest");
        assertEq(lenderFee, expectedLenderFee, "lenderFee");
        assertEq(protocolFee, expectedProtocolFee, "protocolFee");
    }

    function test_fundsRequired_toUsds()
        public
        givenPolicyActive
        givenAdminHasRole
        givenProtocolFee(1000)
    {
        uint256[] memory ids = _idsA();

        // Calculate the interest due
        uint256 expectedPrincipal;
        uint256 expectedInterest;
        for (uint256 i = 0; i < ids.length; i++) {
            Cooler.Loan memory loan = coolerA.getLoan(ids[i]);

            expectedPrincipal += loan.principal;
            expectedInterest += loan.interestDue;
        }

        uint256 expectedProtocolFee = ((expectedPrincipal + expectedInterest) * 1000) /
            _ONE_HUNDRED_PERCENT;
        uint256 expectedLenderFee = 0;

        (address reserveTo, uint256 interest, uint256 lenderFee, uint256 protocolFee) = utils
            .fundsRequired(address(clearinghouseUsds), address(coolerA), ids);

        assertEq(reserveTo, address(usds), "reserveTo");
        assertEq(interest, expectedInterest, "interest");
        assertEq(lenderFee, expectedLenderFee, "lenderFee");
        assertEq(protocolFee, expectedProtocolFee, "protocolFee");
    }

    function test_fundsRequired_toDai() public givenPolicyActive givenAdminHasRole {
        uint256[] memory ids = _idsA();

        // Calculate the interest due
        uint256 expectedPrincipal;
        uint256 expectedInterest;
        for (uint256 i = 0; i < ids.length; i++) {
            Cooler.Loan memory loan = coolerA.getLoan(ids[i]);

            expectedPrincipal += loan.principal;
            expectedInterest += loan.interestDue;
        }

        uint256 expectedProtocolFee = 0;
        uint256 expectedLenderFee = 0;

        (address reserveTo, uint256 interest, uint256 lenderFee, uint256 protocolFee) = utils
            .fundsRequired(address(clearinghouse), address(coolerA), ids);

        assertEq(reserveTo, address(dai), "reserveTo");
        assertEq(interest, expectedInterest, "interest");
        assertEq(lenderFee, expectedLenderFee, "lenderFee");
        assertEq(protocolFee, expectedProtocolFee, "protocolFee");
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
        assertEq(utils.consolidatorActive(), false, "consolidator should be inactive");
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

    function test_activate_policyNotActive_reverts() public givenAdminHasRole {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(LoanConsolidator.OnlyPolicyActive.selector));

        vm.prank(emergency);
        utils.activate();
    }

    function test_activate_notAdminOrEmergency_reverts()
        public
        givenPolicyActive
        givenDeactivated
        givenAdminHasRole
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
        givenPolicyActive
        givenDeactivated
        givenAdminHasRole
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
        givenPolicyActive
        givenDeactivated
        givenAdminHasRole
    {
        vm.prank(emergency);
        utils.activate();

        assertTrue(utils.consolidatorActive(), "consolidator active");
    }

    function test_activate_asEmergency_alreadyActive() public givenPolicyActive givenAdminHasRole {
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

    function test_deactivate_policyNotActive_reverts() public givenAdminHasRole {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(LoanConsolidator.OnlyPolicyActive.selector));

        vm.prank(emergency);
        utils.deactivate();
    }

    function test_deactivate_notAdminOrEmergency_reverts()
        public
        givenPolicyActive
        givenAdminHasRole
    {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ROLE_EMERGENCY_SHUTDOWN)
        );

        utils.deactivate();
    }

    function test_deactivate_asAdmin_reverts() public givenPolicyActive givenAdminHasRole {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ROLE_EMERGENCY_SHUTDOWN)
        );

        vm.prank(admin);
        utils.deactivate();
    }

    function test_deactivate_asEmergency() public givenPolicyActive givenAdminHasRole {
        vm.prank(emergency);
        utils.deactivate();

        assertFalse(utils.consolidatorActive(), "consolidator active");
    }

    function test_deactivate_asEmergency_alreadyDeactivated()
        public
        givenPolicyActive
        givenDeactivated
        givenAdminHasRole
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
