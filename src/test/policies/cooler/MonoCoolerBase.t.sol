// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Test, Vm} from "forge-std/Test.sol";
import {MonoCooler} from "policies/cooler/MonoCooler.sol";
import {IMonoCooler} from "policies/interfaces/IMonoCooler.sol";
import {CoolerLtvOracle} from "policies/cooler/CoolerLtvOracle.sol";

import {MockOhm} from "test/mocks/MockOhm.sol";
import {MockStaking} from "test/mocks/MockStaking.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockGohm} from "test/mocks/MockGohm.sol";
import {MockERC4626} from "solmate/test/utils/mocks/MockERC4626.sol";
import {RolesAdmin, Kernel, Actions} from "policies/RolesAdmin.sol";
import {OlympusRoles} from "modules/ROLES/OlympusRoles.sol";
import {OlympusMinter} from "modules/MINTR/OlympusMinter.sol";
import {OlympusTreasury} from "modules/TRSRY/OlympusTreasury.sol";
import {OlympusGovDelegation, DLGTEv1} from "modules/DLGTE/OlympusGovDelegation.sol";
import {DelegateEscrowFactory} from "src/external/cooler/DelegateEscrowFactory.sol";

abstract contract MonoCoolerBaseTest is Test {
    MockOhm internal ohm;
    MockGohm internal gohm;
    MockERC20 internal usds;
    MockERC4626 internal susds;

    Kernel public kernel;
    MockStaking internal staking;
    OlympusRoles internal ROLES;
    OlympusMinter internal MINTR;
    OlympusTreasury internal TRSRY;
    OlympusGovDelegation internal DLGTE;
    RolesAdmin internal rolesAdmin;

    CoolerLtvOracle internal ltvOracle;
    MonoCooler public cooler;
    DelegateEscrowFactory public escrowFactory;

    address internal immutable OVERSEER = makeAddr("overseer");
    address internal immutable ALICE = makeAddr("alice");
    address internal immutable BOB = makeAddr("bob");
    address internal immutable OTHERS = makeAddr("others");

    uint96 internal constant DEFAULT_OLTV = 2_961.64e18; // [USDS/gOHM] == ~11 [USDS/OHM]
    uint96 internal constant DEFAULT_OLTV_MAX_DELTA = 100e18; // 100 USDS
    uint32 internal constant DEFAULT_OLTV_MIN_TARGET_TIME_DELTA = 1 weeks;
    uint96 internal constant DEFAULT_OLTV_MAX_RATE_OF_CHANGE = uint96(0.1e18) / 1 days; // 0.1 USDS / day
    uint16 internal constant DEFAULT_LLTV_MAX_PREMIUM_BPS = 333;
    uint16 internal constant DEFAULT_LLTV_PREMIUM_BPS = 100; // LLTV is 1% above OLTV
    uint96 internal constant DEFAULT_LLTV = DEFAULT_OLTV * (10_000 + DEFAULT_LLTV_PREMIUM_BPS) / 10_000;

    uint16 internal constant DEFAULT_INTEREST_RATE_BPS = 50; // 0.5%
    uint256 internal constant DEFAULT_MIN_DEBT_REQUIRED = 1_000e18;
    uint256 internal constant INITIAL_TRSRY_MINT = 200_000_000e18;
    uint256 internal constant START_TIMESTAMP = 1_000_000;

    function setUp() public {
        vm.warp(START_TIMESTAMP);

        staking = new MockStaking();

        ohm = new MockOhm("OHM", "OHM", 9);
        gohm = new MockGohm("gOHM", "gOHM", 18);
        usds = new MockERC20("usds", "USDS", 18);
        susds = new MockERC4626(usds, "sUSDS", "sUSDS");

        kernel = new Kernel(); // this contract will be the executor
        escrowFactory = new DelegateEscrowFactory(address(gohm));

        TRSRY = new OlympusTreasury(kernel);
        MINTR = new OlympusMinter(kernel, address(ohm));
        ROLES = new OlympusRoles(kernel);
        DLGTE = new OlympusGovDelegation(kernel, address(gohm), escrowFactory);

        ltvOracle = new CoolerLtvOracle(
            address(kernel),
            address(gohm),
            address(usds),
            DEFAULT_OLTV, 
            DEFAULT_OLTV_MAX_DELTA, 
            DEFAULT_OLTV_MIN_TARGET_TIME_DELTA, 
            DEFAULT_OLTV_MAX_RATE_OF_CHANGE,
            DEFAULT_LLTV_MAX_PREMIUM_BPS,
            DEFAULT_LLTV_PREMIUM_BPS
        );

        cooler = new MonoCooler(
            address(ohm),
            address(gohm),
            address(staking),
            address(susds),
            address(kernel),
            address(ltvOracle),
            DEFAULT_INTEREST_RATE_BPS,
            DEFAULT_MIN_DEBT_REQUIRED
        );

        rolesAdmin = new RolesAdmin(kernel);

        kernel.executeAction(Actions.InstallModule, address(TRSRY));
        kernel.executeAction(Actions.InstallModule, address(MINTR));
        kernel.executeAction(Actions.InstallModule, address(ROLES));
        kernel.executeAction(Actions.InstallModule, address(DLGTE));

        kernel.executeAction(Actions.ActivatePolicy, address(cooler));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));

        /// Configure access control
        rolesAdmin.grantRole("cooler_overseer", OVERSEER);

        // Setup Treasury
        usds.mint(address(TRSRY), INITIAL_TRSRY_MINT);
        // Deposit all reserves into the DSR
        vm.startPrank(address(TRSRY));
        usds.approve(address(susds), INITIAL_TRSRY_MINT);
        susds.deposit(INITIAL_TRSRY_MINT, address(TRSRY));
        vm.stopPrank();

        // Fund others so that TRSRY is not the only account with sUSDS shares
        usds.mint(OTHERS, INITIAL_TRSRY_MINT * 33);
        vm.startPrank(OTHERS);
        usds.approve(address(susds), INITIAL_TRSRY_MINT * 33);
        susds.deposit(INITIAL_TRSRY_MINT * 33, OTHERS);
        vm.stopPrank();
    }

    function checkGlobalState(
        uint128 expectedTotalDebt,
        uint256 expectedInterestAccumulator
    ) internal view {
        (uint128 totalDebt, uint256 interestAccumulatorRay) = cooler.globalState();
        assertEq(totalDebt, expectedTotalDebt, "globalState::totalDebt");
        assertEq(
            interestAccumulatorRay,
            expectedInterestAccumulator,
            "globalState::interestAccumulatorRay"
        );
    }

    function addCollateral(address account, uint128 collateralAmount) internal {
        addCollateral(account, account, collateralAmount, new DLGTEv1.DelegationRequest[](0));
    }

    function addCollateral(
        address caller,
        address onBehalfOf,
        uint128 collateralAmount,
        DLGTEv1.DelegationRequest[] memory delegationRequests
    ) internal {
        gohm.mint(caller, collateralAmount);
        vm.startPrank(caller);
        gohm.approve(address(cooler), collateralAmount);
        cooler.addCollateral(collateralAmount, onBehalfOf, delegationRequests);
        vm.stopPrank();
    }

    function withdrawCollateral(
        address caller,
        address onBehalfOf,
        address recipient,
        uint128 collateralAmount,
        DLGTEv1.DelegationRequest[] memory delegationRequests
    ) internal {
        vm.startPrank(caller);
        cooler.withdrawCollateral(collateralAmount, onBehalfOf, recipient, delegationRequests);
        vm.stopPrank();
    }

    function borrow(
        address caller,
        address onBehalfOf,
        uint128 amount,
        address recipient
    ) internal {
        vm.startPrank(caller);
        cooler.borrow(amount, onBehalfOf, recipient);
        vm.stopPrank();
    }

    function expectNoDelegations(address account) internal view {
        DLGTEv1.AccountDelegation[] memory delegations = cooler.accountDelegationsList(
            account,
            0,
            100
        );
        assertEq(delegations.length, 0, "AccountDelegation::length::0");
    }

    function expectOneDelegation(
        address account,
        address expectedDelegate,
        uint256 expectedDelegationAmount
    ) internal view {
        DLGTEv1.AccountDelegation[] memory delegations = cooler.accountDelegationsList(
            account,
            0,
            100
        );
        assertEq(delegations.length, 1, "AccountDelegation::length::1");
        assertEq(delegations[0].delegate, expectedDelegate, "AccountDelegation::delegate");
        assertEq(
            delegations[0].totalAmount,
            expectedDelegationAmount,
            "AccountDelegation::totalAmount"
        );
        assertEq(
            gohm.balanceOf(delegations[0].escrow),
            expectedDelegationAmount,
            "AccountDelegation::escrow::gOHM::balanceOf"
        );
    }

    function expectTwoDelegations(
        address account,
        address expectedDelegate1,
        uint256 expectedDelegationAmount1,
        address expectedDelegate2,
        uint256 expectedDelegationAmount2
    ) internal view {
        DLGTEv1.AccountDelegation[] memory delegations = cooler.accountDelegationsList(
            account,
            0,
            100
        );
        assertEq(delegations.length, 2, "AccountDelegation::length::2");
        assertEq(delegations[0].delegate, expectedDelegate1, "AccountDelegation::delegate1");
        assertEq(
            delegations[0].totalAmount,
            expectedDelegationAmount1,
            "AccountDelegation::totalAmount1"
        );
        assertEq(
            gohm.balanceOf(delegations[0].escrow),
            expectedDelegationAmount1,
            "AccountDelegation::escrow1::gOHM::balanceOf"
        );
        assertEq(delegations[1].delegate, expectedDelegate2, "AccountDelegation::delegate2");
        assertEq(
            delegations[1].totalAmount,
            expectedDelegationAmount2,
            "AccountDelegation::totalAmount2"
        );
        assertEq(
            gohm.balanceOf(delegations[1].escrow),
            expectedDelegationAmount2,
            "AccountDelegation::escrow2::gOHM::balanceOf"
        );
    }

    function expectAccountDelegationSummary(
        address account,
        uint256 expectedTotalGOhm,
        uint256 expectedDelegatedGOhm,
        uint256 expectedNumDelegateAddresses,
        uint256 expectedMaxAllowedDelegateAddresses
    ) internal view {
        (
            uint256 totalGOhm,
            uint256 delegatedGOhm,
            uint256 numDelegateAddresses,
            uint256 maxAllowedDelegateAddresses
        ) = DLGTE.accountDelegationSummary(account);
        assertEq(totalGOhm, expectedTotalGOhm, "DLGTE::accountDelegationSummary::totalGOhm");
        assertEq(
            delegatedGOhm,
            expectedDelegatedGOhm,
            "DLGTE::accountDelegationSummary::delegatedGOhm"
        );
        assertEq(
            numDelegateAddresses,
            expectedNumDelegateAddresses,
            "DLGTE::accountDelegationSummary::expectedNumDelegateAddresses"
        );
        assertEq(
            maxAllowedDelegateAddresses,
            expectedMaxAllowedDelegateAddresses,
            "DLGTE::accountDelegationSummary::expectedMaxAllowedDelegateAddresses"
        );
    }

    function checkAccountState(
        address account,
        IMonoCooler.AccountState memory expectedAccountState
    ) internal view {
        IMonoCooler.AccountState memory aState = cooler.accountState(account);
        assertEq(aState.collateral, expectedAccountState.collateral, "AccountState::collateral");
        assertEq(
            aState.debtCheckpoint,
            expectedAccountState.debtCheckpoint,
            "AccountState::debtCheckpoint"
        );
        assertEq(
            aState.interestAccumulatorRay,
            expectedAccountState.interestAccumulatorRay,
            "AccountState::interestAccumulatorRay"
        );
    }

    function checkAccountPosition(
        address account,
        IMonoCooler.AccountPosition memory expectedPosition
    ) internal view {
        IMonoCooler.AccountPosition memory position = cooler.accountPosition(account);
        assertEq(position.collateral, expectedPosition.collateral, "AccountPosition::collateral");
        assertEq(
            position.currentDebt,
            expectedPosition.currentDebt,
            "AccountPosition::currentDebt"
        );
        assertEq(
            position.maxOriginationDebtAmount,
            expectedPosition.maxOriginationDebtAmount,
            "AccountPosition::maxOriginationDebtAmount"
        );
        assertEq(
            position.liquidationDebtAmount,
            expectedPosition.liquidationDebtAmount,
            "AccountPosition::liquidationDebtAmount"
        );
        assertEq(
            position.healthFactor,
            expectedPosition.healthFactor,
            "AccountPosition::healthFactor"
        );
        assertEq(position.currentLtv, expectedPosition.currentLtv, "AccountPosition::currentLtv");
        assertEq(
            position.totalDelegated,
            expectedPosition.totalDelegated,
            "AccountPosition::totalDelegated"
        );
        assertEq(
            position.numDelegateAddresses,
            expectedPosition.numDelegateAddresses,
            "AccountPosition::numDelegateAddresses"
        );
        assertEq(
            position.maxDelegateAddresses,
            expectedPosition.maxDelegateAddresses,
            "AccountPosition::maxDelegateAddresses"
        );
        
        assertEq(cooler.accountDebt(account), expectedPosition.currentDebt, "accountDebt()");
        assertEq(cooler.accountCollateral(account), expectedPosition.collateral, "accountCollateral()");
    }

    function checkLiquidityStatus(
        address account,
        IMonoCooler.LiquidationStatus memory expectedLiquidationStatus
    ) internal view {
        address[] memory accounts = new address[](1);
        accounts[0] = account;
        IMonoCooler.LiquidationStatus[] memory status = cooler.computeLiquidity(accounts);
        assertEq(status.length, 1, "LiquidationStatus::length::1");
        assertEq(
            status[0].collateral,
            expectedLiquidationStatus.collateral,
            "LiquidationStatus::collateral"
        );
        assertEq(
            status[0].currentDebt,
            expectedLiquidationStatus.currentDebt,
            "LiquidationStatus::currentDebt"
        );
        assertEq(
            status[0].currentLtv,
            expectedLiquidationStatus.currentLtv,
            "LiquidationStatus::currentLtv"
        );
        assertEq(
            status[0].exceededLiquidationLtv,
            expectedLiquidationStatus.exceededLiquidationLtv,
            "LiquidationStatus::exceededLiquidationLtv"
        );
        assertEq(
            status[0].exceededMaxOriginationLtv,
            expectedLiquidationStatus.exceededMaxOriginationLtv,
            "LiquidationStatus::exceededMaxOriginationLtv"
        );
    }

    function noDelegationRequest() internal pure returns (DLGTEv1.DelegationRequest[] memory) {
        return new DLGTEv1.DelegationRequest[](0);
    }

    function delegationRequest(
        address to,
        uint256 amount
    ) internal pure returns (DLGTEv1.DelegationRequest[] memory delegationRequests) {
        delegationRequests = new DLGTEv1.DelegationRequest[](1);
        delegationRequests[0] = DLGTEv1.DelegationRequest({delegate: to, amount: int256(amount)});
    }

    function unDelegationRequest(
        address from,
        uint256 amount
    ) internal pure returns (DLGTEv1.DelegationRequest[] memory delegationRequests) {
        delegationRequests = new DLGTEv1.DelegationRequest[](1);
        delegationRequests[0] = DLGTEv1.DelegationRequest({
            delegate: from,
            amount: int256(amount) * -1
        });
    }

    function transferDelegationRequest(
        address from,
        address to,
        uint256 amount
    ) internal pure returns (DLGTEv1.DelegationRequest[] memory delegationRequests) {
        delegationRequests = new DLGTEv1.DelegationRequest[](2);
        delegationRequests[0] = DLGTEv1.DelegationRequest({
            delegate: from,
            amount: int256(amount) * -1
        });
        delegationRequests[0] = DLGTEv1.DelegationRequest({delegate: to, amount: int256(amount)});
    }
}
