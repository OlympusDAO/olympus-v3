// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";
import {BL_COLLATERAL_POLICY_ROLE, BL_DEBT_POLICY_ROLE, BL_LIQUIDATION_POLICY_ROLE} from "src/policies/burnerloans/libraries/LoanActionRoles.sol";
import {ADMIN_ROLE, BURNER_LOANS_SEIZER_ROLE, HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansCoreTest} from "./BurnerLoansCoreTest.sol";
import {BurnerLoansActionHandler} from "./fixtures/BurnerLoansActionHandler.sol";
import {CoreCallbackToken} from "./fixtures/CoreCallbackToken.sol";
import {CoreService} from "./fixtures/CoreService.sol";
import {ReentrancyGuard} from "@openzeppelin-5.7.0/utils/ReentrancyGuard.sol";
import {Actions, Kernel, Policy} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

contract BurnerLoansCoreSettleSeizeTest is BurnerLoansCoreTest {
    CoreService internal _actor;
    BurnerLoansActionHandler internal _accountingHandler;

    function setUp() public override {
        super.setUp();
        _actor = _service();
        _rolesAdmin.grantRole(BL_LIQUIDATION_POLICY_ROLE, address(_actor));
        _accountingHandler = new BurnerLoansActionHandler(
            _collateral,
            _debt,
            _liquidation,
            _asset,
            _ohm,
            _price,
            address(_core)
        );
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = _accountingHandler.deposit.selector;
        selectors[1] = _accountingHandler.borrow.selector;
        selectors[2] = _accountingHandler.repay.selector;
        selectors[3] = _accountingHandler.withdraw.selector;
        selectors[4] = _accountingHandler.seizeExpired.selector;
        targetSelector(FuzzSelector(address(_accountingHandler), selectors));
        targetContract(address(_accountingHandler));
    }

    function _borrowers() internal view returns (address[] memory borrowers) {
        borrowers = new address[](1);
        borrowers[0] = _borrower;
    }

    // Scenarios: BLCORE-SETTLE-SEIZE-A02.
    function test_whenCallerLacksSettlementRole_reverts(address caller_) public {
        vm.assume(!_roles.hasRole(caller_, BL_LIQUIDATION_POLICY_ROLE));
        bytes32 before = _state();
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, BL_LIQUIDATION_POLICY_ROLE)
        );
        vm.prank(caller_);
        _core.settleSeize(
            address(0),
            new address[](0),
            address(0),
            IBurnerLoansCore.PriceSnapshot(0, 0, 0)
        );
        assertEq(_state(), before, "Unauthorized instruction has no effects");
    }

    // Scenarios: BLCORE-SETTLE-SEIZE-A03.
    function test_givenOnlySiblingRole_whenSettled_reverts() public {
        CoreService sibling = _service();
        _rolesAdmin.grantRole(BL_DEBT_POLICY_ROLE, address(sibling));
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, BL_LIQUIDATION_POLICY_ROLE)
        );
        vm.prank(address(sibling));
        _core.settleSeize(
            address(0),
            new address[](0),
            address(0),
            IBurnerLoansCore.PriceSnapshot(0, 0, 0)
        );
    }

    // Scenarios: BLCORE-SETTLE-SEIZE-A04.
    function test_givenWrongKernelCaller_whenSettled() public {
        Kernel other = new Kernel();
        vm.prank(address(_kernel));
        _actor.changeKernel(other);
        vm.expectCall(address(_actor), abi.encodeWithSignature("kernel()"), uint64(0));
        vm.expectCall(
            address(_kernel),
            abi.encodeCall(_kernel.isPolicyActive, (Policy(address(_actor)))),
            uint64(0)
        );
        _settleAsCaller(address(_actor));
    }

    // Scenarios: BLCORE-SETTLE-SEIZE-L01.
    function test_givenCoreDisabled_whenSettled_reverts() public {
        _core.disable("");
        bytes32 before = _state();
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(address(_actor));
        _core.settleSeize(
            address(0),
            new address[](0),
            address(0),
            IBurnerLoansCore.PriceSnapshot(0, 0, 0)
        );
        assertEq(_state(), before, "Disabled Core rejects before inputs");
    }

    // Scenarios: BLCORE-SETTLE-SEIZE-L02, BLCORE-SETTLE-SEIZE-L03.
    function test_givenCoreInactive_whenSettled_reverts(bool enabled_) public {
        _setCoreLifecycle(false, enabled_);
        bytes32 before = _state();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_core)
            )
        );
        vm.prank(address(_actor));
        _core.settleSeize(
            address(0),
            new address[](0),
            address(0),
            IBurnerLoansCore.PriceSnapshot(0, 0, 0)
        );
        assertEq(_state(), before, "Own inactivity precedes local state and inputs");
    }

    // Scenarios: BLCORE-SETTLE-SEIZE-D01.
    function test_givenCallerInactive_whenSettled() public {
        _kernel.executeAction(Actions.DeactivatePolicy, address(_actor));
        test_givenAdmittedAction_whenLocalPauseAndCoreBindingDiffer(false, address(_core));
    }

    // Scenarios: BLCORE-SETTLE-SEIZE-D02.
    function test_givenRoleHoldingEOA_whenSettled(address caller_) public {
        vm.assume(caller_.code.length == 0 && caller_ != address(0));
        _grantRole(BL_LIQUIDATION_POLICY_ROLE, caller_);
        _settleAsCaller(caller_);
    }

    // Scenarios: BLCORE-SETTLE-SEIZE-A01.
    function test_givenAdmittedAction_whenLocalPauseAndCoreBindingDiffer(
        bool disabled_,
        address bound_
    ) public {
        if (disabled_) _actor.disable("");
        _actor.setCore(bound_);
        _settleAsCaller(address(_actor));
    }

    function _settleAsCaller(address caller_) internal {
        _deposit(2000e6);
        _borrow(100e9);
        vm.prank(caller_);
        _core.settleSeize(
            address(_asset),
            _borrowers(),
            _recipient,
            IBurnerLoansCore.PriceSnapshot(1e18, 1e18, 1e18)
        );
        assertEq(_core.totalActiveDebtOhm(), 0, "Role-holding caller settles the seizure");
    }

    // Scenarios: BLCORE-SETTLE-SEIZE-P01.
    function test_givenLaterBorrowerMissing_whenSeized_reverts() public {
        _deposit(2000e6);
        _borrow(100e9);
        address[] memory borrowers = new address[](2);
        borrowers[0] = _borrower;
        borrowers[1] = address(0xDEAD);
        bytes32 before = _ledger();
        vm.expectRevert(IBurnerLoansCore.BurnerLoansCore_NoDebt.selector);
        vm.prank(address(_actor));
        _core.settleSeize(
            address(_asset),
            borrowers,
            _recipient,
            IBurnerLoansCore.PriceSnapshot(1e18, 1e18, 1e18)
        );
        assertEq(_ledger(), before, "Later failure rolls back earlier default and indexes");
    }

    // Scenarios: BLCORE-SETTLE-SEIZE-I01.
    function test_givenLaterBorrowerWithoutDebt_whenSeized_reverts() public {
        _deposit(2000e6);
        _borrow(100e9);
        address second = address(0xDEAD);
        vm.prank(address(_collateral));
        _core.settleDeposit(address(_asset), 1, _borrower, second);
        address[] memory borrowers = new address[](2);
        borrowers[0] = _borrower;
        borrowers[1] = second;
        bytes32 before = _ledger();
        vm.expectRevert(IFLOANv1.FLOAN_InvalidAmount.selector);
        vm.prank(address(_actor));
        _core.settleSeize(
            address(_asset),
            borrowers,
            _recipient,
            IBurnerLoansCore.PriceSnapshot(1e18, 1e18, 1e18)
        );
        assertEq(_ledger(), before, "Earlier default rolls back when later position has no debt");
    }

    // Scenarios: BLCORE-SETTLE-SEIZE-I02.
    function test_givenUnexpectedOutputToken_whenSeized_reverts() public {
        _deposit(2000e6);
        _borrow(100e9);
        vm.mockCall(
            address(_depositManager),
            abi.encodeWithSignature("withdraw((address,uint8,address,address,uint256,bool),bool)"),
            abi.encode(address(_ohm), uint256(1))
        );
        bytes32 before = _ledger();
        vm.expectRevert(IBurnerLoansCore.BurnerLoansCore_InvalidSettlement.selector);
        vm.prank(address(_actor));
        _core.settleSeize(
            address(_asset),
            _borrowers(),
            _recipient,
            IBurnerLoansCore.PriceSnapshot(1e18, 1e18, 1e18)
        );
        assertEq(
            _ledger(),
            before,
            "Invalid seizure receipts or allocation roll back entire batch"
        );
    }

    // Scenarios: BLCORE-SETTLE-SEIZE-I04.
    function test_givenShortPayoutReceipt_whenSeized_reverts() public {
        _deposit(2000e6);
        _borrow(100e9);
        _asset.mint(address(_payout), 1000);
        vm.mockCall(
            address(_depositManager),
            abi.encodeWithSignature("withdraw((address,uint8,address,address,uint256,bool),bool)"),
            abi.encode(address(_asset), uint256(1))
        );
        bytes32 before = _ledger();
        vm.expectRevert(IBurnerLoansCore.BurnerLoansCore_InvalidSettlement.selector);
        vm.prank(address(_actor));
        _core.settleSeize(
            address(_asset),
            _borrowers(),
            _recipient,
            IBurnerLoansCore.PriceSnapshot(1e18, 1e18, 1e18)
        );
        assertEq(
            _ledger(),
            before,
            "Invalid seizure receipts or allocation roll back entire batch"
        );
    }

    // Scenarios: BLCORE-SETTLE-SEIZE-I06.
    function test_givenExcessiveReward_whenSeized_reverts() public {
        _deposit(2000e6);
        _borrow(100e9);
        vm.mockCall(
            address(_risk),
            abi.encodeWithSignature(
                "keeperReward((uint256,uint256,uint256),uint32,uint256,uint256,uint256,bool)"
            ),
            abi.encode(uint256(2000e6 + 1))
        );
        bytes32 before = _ledger();
        vm.expectRevert(IBurnerLoansCore.BurnerLoansCore_InvalidSettlement.selector);
        vm.prank(address(_actor));
        _core.settleSeize(
            address(_asset),
            _borrowers(),
            _recipient,
            IBurnerLoansCore.PriceSnapshot(1e18, 1e18, 1e18)
        );
        assertEq(
            _ledger(),
            before,
            "Invalid seizure receipts or allocation roll back entire batch"
        );
    }

    // Scenarios: BLCORE-SETTLE-SEIZE-I07.
    function test_givenPayoutCreditRejected_whenSeized_reverts() public {
        _deposit(2000e6);
        _borrow(100e9);
        vm.mockCallRevert(
            address(_payout),
            abi.encodeWithSignature("creditSeizure(address,address,uint256,uint256)"),
            abi.encodeWithSelector(IBurnerLoansCore.BurnerLoansCore_InvalidSettlement.selector)
        );
        bytes32 before = _ledger();
        vm.expectRevert(IBurnerLoansCore.BurnerLoansCore_InvalidSettlement.selector);
        vm.prank(address(_actor));
        _core.settleSeize(
            address(_asset),
            _borrowers(),
            _recipient,
            IBurnerLoansCore.PriceSnapshot(1e18, 1e18, 1e18)
        );
        assertEq(
            _ledger(),
            before,
            "Invalid seizure receipts or allocation roll back entire batch"
        );
    }

    // Scenarios: BLCORE-SETTLE-SEIZE-P02.
    function test_givenOrdinaryKeeper_whenSeized(uint128 reward_) public {
        _deposit(2000e6);
        _borrow(100e9);
        reward_ = uint128(bound(reward_, 0, 2000e6));
        uint32 market = _core.marketId(address(_asset));
        IBurnerLoansCore.PriceSnapshot memory snapshot = IBurnerLoansCore.PriceSnapshot(
            123,
            456,
            789
        );
        vm.mockCall(
            address(_risk),
            abi.encodeWithSignature(
                "keeperReward((uint256,uint256,uint256),uint32,uint256,uint256,uint256,bool)"
            ),
            abi.encode(uint256(reward_))
        );
        vm.expectCall(
            address(_risk),
            abi.encodeWithSignature(
                "keeperReward((uint256,uint256,uint256),uint32,uint256,uint256,uint256,bool)",
                snapshot,
                market,
                uint256(100e9),
                uint256(2000e6),
                uint256(2000e6),
                false
            )
        );
        uint256 keeperBefore = _asset.balanceOf(_recipient);
        uint256 treasuryBefore = _asset.balanceOf(_payout.treasury());
        vm.expectEmit(true, true, true, true, address(_core));
        emit IBurnerLoansCore.Seized(_recipient, address(_asset), _borrower, 100e9, 2000e6);
        vm.expectEmit(true, true, false, true, address(_core));
        emit IBurnerLoansCore.SeizureBatchSettled(
            _recipient,
            address(_asset),
            1,
            100e9,
            2000e6,
            address(_asset),
            reward_,
            2000e6 - reward_
        );
        vm.prank(address(_actor));
        IBurnerLoansCore.SeizePreview memory result = _core.settleSeize(
            address(_asset),
            _borrowers(),
            _recipient,
            snapshot
        );
        assertEq(result.seizedDebtOhm, 100e9, "Defaulted principal aggregated");
        assertEq(result.seizedCollateral, 2000e6, "Actual seized collateral aggregated");
        assertEq(result.keeperReward, reward_, "Arbitrary Risk output used unchanged");
        assertEq(
            result.collateralToTreasury,
            2000e6 - reward_,
            "Remainder subtracts reward without separate rounding"
        );
        assertEq(_asset.balanceOf(_recipient) - keeperBefore, reward_, "Keeper paid once");
        assertEq(
            _asset.balanceOf(_payout.treasury()) - treasuryBefore,
            2000e6 - reward_,
            "Treasury gets remainder"
        );
        assertEq(_core.totalActiveDebtOhm(), 0, "Canonical debt cleared");
        assertEq(_inventory.activePrincipalOhm(), 0, "Inventory debt cleared");
        assertEq(_floan.getActiveBorrowerCount(market), 0, "Raw active index cleared");
        assertEq(_position().depositedCollateral, 0, "Collateral cleared");
    }

    // Scenarios: BLCORE-SETTLE-SEIZE-P03.
    function test_givenProtocolKeeper_whenSeized(bool heart_) public {
        _deposit(2000e6);
        _borrow(100e9);
        _rolesAdmin.grantRole(heart_ ? HEART_ROLE : BURNER_LOANS_SEIZER_ROLE, _recipient);
        uint256 before = _asset.balanceOf(_payout.treasury());
        vm.prank(address(_actor));
        IBurnerLoansCore.SeizePreview memory result = _core.settleSeize(
            address(_asset),
            _borrowers(),
            _recipient,
            IBurnerLoansCore.PriceSnapshot(1e18, 1e18, 1e18)
        );
        assertEq(result.keeperReward, 0, "Protocol keeper receives no reward");
        assertEq(
            _asset.balanceOf(_payout.treasury()) - before,
            2000e6,
            "All actual output sent to Treasury"
        );
    }

    // Scenarios: BLCORE-SETTLE-SEIZE-D03.
    function test_givenKeeperTransferFailure_whenSeized() public {
        _deposit(2000e6);
        _borrow(100e9);
        vm.mockCallRevert(
            address(_asset),
            abi.encodeWithSignature("transfer(address,uint256)", _recipient),
            abi.encodeWithSelector(DependencyFailed.selector)
        );
        vm.prank(address(_actor));
        IBurnerLoansCore.SeizePreview memory result = _core.settleSeize(
            address(_asset),
            _borrowers(),
            _recipient,
            IBurnerLoansCore.PriceSnapshot(1e18, 1e18, 1e18)
        );
        uint256 expected = result.keeperReward;
        assertGt(expected, 0, "Fixture produces positive obligation");
        assertEq(
            _payout.pendingPayout(address(_asset), _recipient),
            expected,
            "Failed optional delivery preserves entitlement"
        );
        assertEq(_asset.balanceOf(address(_payout)), expected, "Deferred entitlement backed");
        assertEq(_position().debtOhm, 0, "Default committed despite optional transfer failure");
    }

    // Scenarios: BLCORE-SETTLE-SEIZE-D03.
    function test_givenTreasuryTransferFailure_whenSeized() public {
        _deposit(2000e6);
        _borrow(100e9);
        vm.mockCallRevert(
            address(_asset),
            abi.encodeWithSignature("transfer(address,uint256)", _payout.treasury()),
            abi.encodeWithSelector(DependencyFailed.selector)
        );
        vm.prank(address(_actor));
        IBurnerLoansCore.SeizePreview memory result = _core.settleSeize(
            address(_asset),
            _borrowers(),
            _recipient,
            IBurnerLoansCore.PriceSnapshot(1e18, 1e18, 1e18)
        );
        uint256 expected = result.collateralToTreasury;
        assertGt(expected, 0, "Fixture produces positive obligation");
        assertEq(
            _payout.pendingPayout(address(_asset), _payout.treasury()),
            expected,
            "Failed optional delivery preserves entitlement"
        );
        assertEq(_asset.balanceOf(address(_payout)), expected, "Deferred entitlement backed");
        assertEq(_position().debtOhm, 0, "Default committed despite optional transfer failure");
    }

    // Scenarios: BLCORE-SETTLE-SEIZE-C01.
    function test_givenSettlementCallback_whenCaught() public {
        CoreCallbackToken token = _callbackAsset();
        _deposit(100);
        _borrow(1);
        _rolesAdmin.grantRole(BL_COLLATERAL_POLICY_ROLE, address(_actor));
        _authorizeCollateralCallback(_actor);
        token.setCallbackFrom(
            address(_depositManager),
            address(_actor),
            abi.encodeWithSelector(
                CoreService.forward.selector,
                address(_collateral),
                abi.encodeWithSignature(
                    "depositCollateral(address,uint128,address)",
                    address(_asset),
                    uint128(1),
                    _recipient
                )
            )
        );
        token.setCallbackPhases(true, false);
        token.setBubbleCallbackFailure(false);
        bytes32 before = _ledger();
        vm.prank(address(_actor));
        _core.settleSeize(
            address(_asset),
            _borrowers(),
            _recipient,
            IBurnerLoansCore.PriceSnapshot(1e18, 1e18, 1e18)
        );
        assertEq(
            token.callbackRevertSelector(),
            ReentrancyGuard.ReentrancyGuardReentrantCall.selector,
            "Otherwise-authorized nested Settlement reaches settlement guard"
        );
        assertEq(_position().debtOhm, 0, "One outer default");
        assertEq(_position().depositedCollateral, 0, "Collateral seized once");
    }

    // Scenarios: BLCORE-SETTLE-SEIZE-C02.
    function test_givenSettlementCallback_whenPropagated() public {
        CoreCallbackToken token = _callbackAsset();
        _deposit(100);
        _borrow(1);
        _rolesAdmin.grantRole(BL_COLLATERAL_POLICY_ROLE, address(_actor));
        _authorizeCollateralCallback(_actor);
        token.setCallbackFrom(
            address(_depositManager),
            address(_actor),
            abi.encodeWithSelector(
                CoreService.forward.selector,
                address(_collateral),
                abi.encodeWithSignature(
                    "depositCollateral(address,uint128,address)",
                    address(_asset),
                    uint128(1),
                    _recipient
                )
            )
        );
        token.setCallbackPhases(true, false);
        token.setBubbleCallbackFailure(true);
        bytes32 before = _ledger();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        vm.prank(address(_actor));
        _core.settleSeize(
            address(_asset),
            _borrowers(),
            _recipient,
            IBurnerLoansCore.PriceSnapshot(1e18, 1e18, 1e18)
        );
        assertEq(
            _ledger(),
            before,
            "Propagated mandatory callback rolls back accounting and custody"
        );
    }

    // Scenarios: BLCORE-SETTLE-SEIZE-C01.
    function test_givenAdminMutationCallback_whenCaught() public {
        CoreCallbackToken token = _callbackAsset();
        _deposit(100);
        _borrow(1);
        _rolesAdmin.grantRole(BL_COLLATERAL_POLICY_ROLE, address(_actor));
        _rolesAdmin.grantRole(ADMIN_ROLE, address(_actor));
        token.setCallbackFrom(
            address(_depositManager),
            address(_actor),
            abi.encodeWithSelector(
                CoreService.forward.selector,
                address(_core),
                abi.encodeWithSignature("setGracePeriod(uint32)", uint32(1))
            )
        );
        token.setCallbackPhases(true, false);
        token.setBubbleCallbackFailure(false);
        bytes32 before = _ledger();
        vm.prank(address(_actor));
        _core.settleSeize(
            address(_asset),
            _borrowers(),
            _recipient,
            IBurnerLoansCore.PriceSnapshot(1e18, 1e18, 1e18)
        );
        assertEq(
            token.callbackRevertSelector(),
            ReentrancyGuard.ReentrancyGuardReentrantCall.selector,
            "Otherwise-authorized nested AdminMutation reaches settlement guard"
        );
        assertEq(_position().debtOhm, 0, "One outer default");
        assertEq(_position().depositedCollateral, 0, "Collateral seized once");
    }

    // Scenarios: BLCORE-SETTLE-SEIZE-C02.
    function test_givenAdminMutationCallback_whenPropagated() public {
        CoreCallbackToken token = _callbackAsset();
        _deposit(100);
        _borrow(1);
        _rolesAdmin.grantRole(BL_COLLATERAL_POLICY_ROLE, address(_actor));
        _rolesAdmin.grantRole(ADMIN_ROLE, address(_actor));
        token.setCallbackFrom(
            address(_depositManager),
            address(_actor),
            abi.encodeWithSelector(
                CoreService.forward.selector,
                address(_core),
                abi.encodeWithSignature("setGracePeriod(uint32)", uint32(1))
            )
        );
        token.setCallbackPhases(true, false);
        token.setBubbleCallbackFailure(true);
        bytes32 before = _ledger();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        vm.prank(address(_actor));
        _core.settleSeize(
            address(_asset),
            _borrowers(),
            _recipient,
            IBurnerLoansCore.PriceSnapshot(1e18, 1e18, 1e18)
        );
        assertEq(
            _ledger(),
            before,
            "Propagated mandatory callback rolls back accounting and custody"
        );
    }

    // Scenarios: BLCORE-SETTLE-SEIZE-C01.
    function test_givenPayoutRecoveryCallback_whenCaught() public {
        CoreCallbackToken token = _callbackAsset();
        _deposit(100);
        _borrow(1);
        _rolesAdmin.grantRole(BL_COLLATERAL_POLICY_ROLE, address(_actor));
        _rolesAdmin.grantRole(ADMIN_ROLE, address(_actor));
        token.setCallbackFrom(
            address(_depositManager),
            address(_actor),
            abi.encodeWithSelector(
                CoreService.forward.selector,
                address(_payout),
                abi.encodeWithSignature("rescue(address,address)", address(_asset), _recipient)
            )
        );
        token.setCallbackPhases(true, false);
        token.setBubbleCallbackFailure(false);
        bytes32 before = _ledger();
        vm.prank(address(_actor));
        _core.settleSeize(
            address(_asset),
            _borrowers(),
            _recipient,
            IBurnerLoansCore.PriceSnapshot(1e18, 1e18, 1e18)
        );
        assertEq(
            token.callbackRevertSelector(),
            ReentrancyGuard.ReentrancyGuardReentrantCall.selector,
            "Otherwise-authorized nested PayoutRecovery reaches settlement guard"
        );
        assertEq(_position().debtOhm, 0, "One outer default");
        assertEq(_position().depositedCollateral, 0, "Collateral seized once");
    }

    // Scenarios: BLCORE-SETTLE-SEIZE-C02.
    function test_givenPayoutRecoveryCallback_whenPropagated() public {
        CoreCallbackToken token = _callbackAsset();
        _deposit(100);
        _borrow(1);
        _rolesAdmin.grantRole(BL_COLLATERAL_POLICY_ROLE, address(_actor));
        _rolesAdmin.grantRole(ADMIN_ROLE, address(_actor));
        token.setCallbackFrom(
            address(_depositManager),
            address(_actor),
            abi.encodeWithSelector(
                CoreService.forward.selector,
                address(_payout),
                abi.encodeWithSignature("rescue(address,address)", address(_asset), _recipient)
            )
        );
        token.setCallbackPhases(true, false);
        token.setBubbleCallbackFailure(true);
        bytes32 before = _ledger();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        vm.prank(address(_actor));
        _core.settleSeize(
            address(_asset),
            _borrowers(),
            _recipient,
            IBurnerLoansCore.PriceSnapshot(1e18, 1e18, 1e18)
        );
        assertEq(
            _ledger(),
            before,
            "Propagated mandatory callback rolls back accounting and custody"
        );
    }

    // Scenarios: BLCORE-SETTLE-SEIZE-C03.
    function test_givenOptionalKeeperCallback_whenCaught() public {
        CoreCallbackToken token = _callbackAsset();
        _deposit(100);
        _borrow(1);
        _rolesAdmin.grantRole(BL_COLLATERAL_POLICY_ROLE, address(_actor));
        _rolesAdmin.grantRole(ADMIN_ROLE, address(_actor));
        vm.mockCall(
            address(_risk),
            abi.encodeWithSignature(
                "keeperReward((uint256,uint256,uint256),uint32,uint256,uint256,uint256,bool)"
            ),
            abi.encode(uint256(7))
        );
        token.setCallbackFrom(
            address(_payout),
            address(_actor),
            abi.encodeWithSelector(
                CoreService.forward.selector,
                address(_payout),
                abi.encodeWithSignature("rescue(address,address)", address(_asset), _recipient)
            )
        );
        token.setCallbackPhases(true, false);
        token.setCallbackTransferRecipient(_recipient);
        token.setBubbleCallbackFailure(false);
        vm.prank(address(_actor));
        _core.settleSeize(
            address(_asset),
            _borrowers(),
            _recipient,
            IBurnerLoansCore.PriceSnapshot(1e18, 1e18, 1e18)
        );
        uint256 expected = 7;
        uint256 pending = _payout.pendingPayout(address(_asset), _recipient);
        assertEq(
            token.callbackRevertSelector(),
            ReentrancyGuard.ReentrancyGuardReentrantCall.selector,
            "Payout local guard rejects nested recovery"
        );
        assertEq(pending, 0, "Caught optional callback permits delivery");
    }

    // Scenarios: BLCORE-SETTLE-SEIZE-C04.
    function test_givenOptionalKeeperCallback_whenPropagated() public {
        CoreCallbackToken token = _callbackAsset();
        _deposit(100);
        _borrow(1);
        _rolesAdmin.grantRole(BL_COLLATERAL_POLICY_ROLE, address(_actor));
        _rolesAdmin.grantRole(ADMIN_ROLE, address(_actor));
        vm.mockCall(
            address(_risk),
            abi.encodeWithSignature(
                "keeperReward((uint256,uint256,uint256),uint32,uint256,uint256,uint256,bool)"
            ),
            abi.encode(uint256(7))
        );
        token.setCallbackFrom(
            address(_payout),
            address(_actor),
            abi.encodeWithSelector(
                CoreService.forward.selector,
                address(_payout),
                abi.encodeWithSignature("rescue(address,address)", address(_asset), _recipient)
            )
        );
        token.setCallbackPhases(true, false);
        token.setCallbackTransferRecipient(_recipient);
        token.setBubbleCallbackFailure(true);
        vm.prank(address(_actor));
        _core.settleSeize(
            address(_asset),
            _borrowers(),
            _recipient,
            IBurnerLoansCore.PriceSnapshot(1e18, 1e18, 1e18)
        );
        uint256 expected = 7;
        uint256 pending = _payout.pendingPayout(address(_asset), _recipient);
        assertEq(pending, expected, "Optional callback propagation defers exactly one entitlement");
        assertEq(token.balanceOf(address(_payout)), expected, "Deferred entitlement backed");
        token.setCallbackFrom(address(0), address(0), bytes(""));
        uint256 before = token.balanceOf(_recipient);
        uint256 paid = _payout.transferPendingPayout(address(_asset), _recipient);
        assertEq(paid, expected, "Later retry pays exact entitlement");
        assertEq(token.balanceOf(_recipient), before + expected, "Recipient credited once");
        assertEq(
            _payout.transferPendingPayout(address(_asset), _recipient),
            0,
            "Second retry cannot pay again"
        );
    }

    // Scenarios: BLCORE-SETTLE-SEIZE-C03.
    function test_givenOptionalTreasuryCallback_whenCaught() public {
        CoreCallbackToken token = _callbackAsset();
        _deposit(100);
        _borrow(1);
        _rolesAdmin.grantRole(BL_COLLATERAL_POLICY_ROLE, address(_actor));
        _rolesAdmin.grantRole(ADMIN_ROLE, address(_actor));
        vm.mockCall(
            address(_risk),
            abi.encodeWithSignature(
                "keeperReward((uint256,uint256,uint256),uint32,uint256,uint256,uint256,bool)"
            ),
            abi.encode(uint256(7))
        );
        token.setCallbackFrom(
            address(_payout),
            address(_actor),
            abi.encodeWithSelector(
                CoreService.forward.selector,
                address(_payout),
                abi.encodeWithSignature("rescue(address,address)", address(_asset), _recipient)
            )
        );
        token.setCallbackPhases(true, false);
        token.setCallbackTransferRecipient(_payout.treasury());
        token.setBubbleCallbackFailure(false);
        vm.prank(address(_actor));
        _core.settleSeize(
            address(_asset),
            _borrowers(),
            _recipient,
            IBurnerLoansCore.PriceSnapshot(1e18, 1e18, 1e18)
        );
        uint256 expected = 93;
        uint256 pending = _payout.pendingPayout(address(_asset), _payout.treasury());
        assertEq(
            token.callbackRevertSelector(),
            ReentrancyGuard.ReentrancyGuardReentrantCall.selector,
            "Payout local guard rejects nested recovery"
        );
        assertEq(pending, 0, "Caught optional callback permits delivery");
    }

    // Scenarios: BLCORE-SETTLE-SEIZE-C04.
    function test_givenOptionalTreasuryCallback_whenPropagated() public {
        CoreCallbackToken token = _callbackAsset();
        _deposit(100);
        _borrow(1);
        _rolesAdmin.grantRole(BL_COLLATERAL_POLICY_ROLE, address(_actor));
        _rolesAdmin.grantRole(ADMIN_ROLE, address(_actor));
        vm.mockCall(
            address(_risk),
            abi.encodeWithSignature(
                "keeperReward((uint256,uint256,uint256),uint32,uint256,uint256,uint256,bool)"
            ),
            abi.encode(uint256(7))
        );
        token.setCallbackFrom(
            address(_payout),
            address(_actor),
            abi.encodeWithSelector(
                CoreService.forward.selector,
                address(_payout),
                abi.encodeWithSignature("rescue(address,address)", address(_asset), _recipient)
            )
        );
        token.setCallbackPhases(true, false);
        token.setCallbackTransferRecipient(_payout.treasury());
        token.setBubbleCallbackFailure(true);
        vm.prank(address(_actor));
        _core.settleSeize(
            address(_asset),
            _borrowers(),
            _recipient,
            IBurnerLoansCore.PriceSnapshot(1e18, 1e18, 1e18)
        );
        uint256 expected = 93;
        uint256 pending = _payout.pendingPayout(address(_asset), _payout.treasury());
        assertEq(pending, expected, "Optional callback propagation defers exactly one entitlement");
        assertEq(token.balanceOf(address(_payout)), expected, "Deferred entitlement backed");
        token.setCallbackFrom(address(0), address(0), bytes(""));
        uint256 before = token.balanceOf(_payout.treasury());
        uint256 paid = _payout.transferPendingPayout(address(_asset), _payout.treasury());
        assertEq(paid, expected, "Later retry pays exact entitlement");
        assertEq(token.balanceOf(_payout.treasury()), before + expected, "Recipient credited once");
        assertEq(
            _payout.transferPendingPayout(address(_asset), _payout.treasury()),
            0,
            "Second retry cannot pay again"
        );
    }

    // Scenarios: BLCORE-SETTLE-SEIZE-I03.
    function test_givenDecreasingBalance_whenSeized_reverts() public {
        CoreCallbackToken token = _callbackAsset();
        _deposit(100);
        _borrow(1);
        token.mint(address(_payout), 1);
        token.setCallbackFrom(
            address(_depositManager),
            address(token),
            abi.encodeWithSignature("burn(address,uint256)", address(_payout), uint256(101))
        );
        token.setCallbackPhases(true, false);
        bytes32 before = _ledger();
        vm.expectRevert(IBurnerLoansCore.BurnerLoansCore_InvalidSettlement.selector);
        vm.prank(address(_actor));
        _core.settleSeize(
            address(_asset),
            _borrowers(),
            _recipient,
            IBurnerLoansCore.PriceSnapshot(1e18, 1e18, 1e18)
        );
        assertEq(
            _ledger(),
            before,
            "Invalid redemption delta rolls back defaults and token callbacks"
        );
    }

    // Scenarios: BLCORE-SETTLE-SEIZE-I05.
    function test_givenExcessReceipt_whenSeized_reverts() public {
        CoreCallbackToken token = _callbackAsset();
        _deposit(100);
        _borrow(1);
        token.setCallbackFrom(
            address(_depositManager),
            address(token),
            abi.encodeWithSignature("mint(address,uint256)", address(_payout), uint256(1))
        );
        token.setCallbackPhases(true, false);
        bytes32 before = _ledger();
        vm.expectRevert(IBurnerLoansCore.BurnerLoansCore_InvalidSettlement.selector);
        vm.prank(address(_actor));
        _core.settleSeize(
            address(_asset),
            _borrowers(),
            _recipient,
            IBurnerLoansCore.PriceSnapshot(1e18, 1e18, 1e18)
        );
        assertEq(
            _ledger(),
            before,
            "Invalid redemption delta rolls back defaults and token callbacks"
        );
    }

    // Scenarios: BLCORE-SETTLE-SEIZE-N01.
    function test_givenInconsistentAggregate_whenSeized_reverts() public {
        _deposit(2);
        vm.prank(address(_collateral));
        _core.settleDeposit(address(_asset), 2, _borrower, address(0xCAFE));
        address[] memory borrowers = new address[](2);
        borrowers[0] = _borrower;
        borrowers[1] = address(0xCAFE);
        vm.mockCall(
            address(_floan),
            abi.encodeWithSignature("defaultPosition(uint64)"),
            abi.encode(type(uint128).max, uint128(0), uint128(0))
        );
        vm.mockCall(
            address(_risk),
            abi.encodeWithSignature(
                "keeperReward((uint256,uint256,uint256),uint32,uint256,uint256,uint256,bool)"
            ),
            abi.encode(uint256(0))
        );
        bytes32 before = _ledger();
        uint256 total = uint256(type(uint128).max) * 2;
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeCast.SafeCastOverflowedUintDowncast.selector,
                uint8(128),
                total
            )
        );
        vm.prank(address(_actor));
        _core.settleSeize(
            address(_asset),
            borrowers,
            _recipient,
            IBurnerLoansCore.PriceSnapshot(1e18, 1e18, 1e18)
        );
        assertEq(_ledger(), before, "Aggregate narrowing never truncates principal");
    }

    // Scenarios: BLCORE-SETTLE-DEPOSIT-P01, BLCORE-SETTLE-BORROW-I03, BLCORE-SETTLE-REPAY-N02, BLCORE-SETTLE-REPAY-N03, BLCORE-SETTLE-WITHDRAW-P02, BLCORE-SETTLE-SEIZE-P02.
    function invariant_canonicalDebtAndCustodyMatchIndependentModel() public view {
        uint32 market = _core.marketId(address(_asset));
        assertEq(
            _lens.getPosition(address(_asset), address(_accountingHandler)).depositedCollateral,
            _accountingHandler.collateral(),
            "Collateral matches independent flow model"
        );
        assertEq(
            _lens.getPosition(address(_asset), address(_accountingHandler)).debtOhm,
            _accountingHandler.principal(),
            "Principal matches independent flow model"
        );
        assertEq(
            _core.totalActiveDebtOhm(),
            _accountingHandler.principal(),
            "Canonical facility debt agrees"
        );
        assertEq(
            _floan.getMarketPrincipalDue(market),
            _accountingHandler.principal(),
            "Market debt agrees"
        );
        assertEq(
            _inventory.activePrincipalOhm(),
            _accountingHandler.principal(),
            "Inventory debt agrees"
        );
        assertEq(
            _floan.getMarketCollateral(market),
            _accountingHandler.collateral(),
            "Market collateral agrees"
        );
        assertEq(
            _depositManager.getOperatorLiabilities(IERC20(address(_asset)), address(_core)),
            _accountingHandler.collateral(),
            "Operator liabilities match collateral"
        );
        assertEq(
            _asset.balanceOf(address(_depositManager)),
            _accountingHandler.collateral(),
            "Raw collateral fully backed"
        );
        assertEq(_asset.balanceOf(address(_core)), 0, "Core retains no raw collateral");
        assertEq(
            _floan.getActiveBorrowerCount(market),
            _accountingHandler.principal() == 0 ? 0 : 1,
            "Underlying active index agrees with independent principal"
        );
        (, , uint256 reserved) = _payout.payoutReserves(address(_asset));
        assertEq(reserved, 0, "Ordinary-token payouts leave no deferred reserve");
    }
}
