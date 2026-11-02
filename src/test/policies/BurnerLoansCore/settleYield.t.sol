// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IERC20 as OZERC20} from "@openzeppelin-5.7.0/token/ERC20/IERC20.sol";
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansYieldClaim} from "src/policies/interfaces/burnerloans/IBurnerLoansYieldClaim.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IDepositManagerV1_1} from "src/policies/interfaces/deposits/IDepositManagerV1_1.sol";

// Libraries
import {BL_DEBT_POLICY_ROLE, BL_YIELD_CLAIMER_ROLE} from "src/policies/burnerloans/libraries/LoanActionRoles.sol";
import {DEPOSIT_OPERATOR_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansCoreTest} from "./BurnerLoansCoreTest.sol";
import {CoreCallbackToken} from "./fixtures/CoreCallbackToken.sol";
import {CoreService} from "./fixtures/CoreService.sol";
import {Vm} from "@forge-std-1.16.2/Vm.sol";
import {ReentrancyGuard} from "@openzeppelin-5.7.0/utils/ReentrancyGuard.sol";
import {Actions, Kernel, Policy} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {MockERC4626} from "src/test/mocks/MockERC4626.sol";

contract BurnerLoansCoreSettleYieldTest is BurnerLoansCoreTest {
    CoreService internal _actor;

    function setUp() public override {
        super.setUp();
        _actor = _service();
        _rolesAdmin.grantRole(BL_YIELD_CLAIMER_ROLE, address(_actor));
    }

    // Scenarios: BLCORE-SETTLE-YIELD-A02.
    function test_whenCallerLacksSettlementRole_reverts(address caller_) public {
        vm.assume(!_roles.hasRole(caller_, BL_YIELD_CLAIMER_ROLE));
        bytes32 before = _state();
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, BL_YIELD_CLAIMER_ROLE)
        );
        vm.prank(caller_);
        _core.settleYield(address(0), 0, address(0));
        assertEq(_state(), before, "Unauthorized instruction has no effects");
    }

    // Scenarios: BLCORE-SETTLE-YIELD-A03.
    function test_givenOnlySiblingRole_whenSettled_reverts() public {
        CoreService sibling = _service();
        _rolesAdmin.grantRole(BL_DEBT_POLICY_ROLE, address(sibling));
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, BL_YIELD_CLAIMER_ROLE)
        );
        vm.prank(address(sibling));
        _core.settleYield(address(0), 0, address(0));
    }

    // Scenarios: BLCORE-SETTLE-YIELD-A04.
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

    // Scenarios: BLCORE-SETTLE-YIELD-L01.
    function test_givenCoreDisabled_whenSettled_reverts() public {
        _core.disable("");
        bytes32 before = _state();
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(address(_actor));
        _core.settleYield(address(0), 0, address(0));
        assertEq(_state(), before, "Disabled Core rejects before inputs");
    }

    // Scenarios: BLCORE-SETTLE-YIELD-L02, BLCORE-SETTLE-YIELD-L03.
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
        _core.settleYield(address(0), 0, address(0));
        assertEq(_state(), before, "Own inactivity precedes local state and inputs");
    }

    // Scenarios: BLCORE-SETTLE-YIELD-D01.
    function test_givenCallerInactive_whenSettled() public {
        _kernel.executeAction(Actions.DeactivatePolicy, address(_actor));
        test_givenAdmittedAction_whenLocalPauseAndCoreBindingDiffer(false, address(_core));
    }

    // Scenarios: BLCORE-SETTLE-YIELD-D02.
    function test_givenRoleHoldingEOA_whenSettled(address caller_) public {
        vm.assume(caller_.code.length == 0 && caller_ != address(0));
        _grantRole(BL_YIELD_CLAIMER_ROLE, caller_);
        _settleAsCaller(caller_);
    }

    // Scenarios: BLCORE-SETTLE-YIELD-A01.
    function test_givenAdmittedAction_whenLocalPauseAndCoreBindingDiffer(
        bool disabled_,
        address bound_
    ) public {
        if (disabled_) _actor.disable("");
        _actor.setCore(bound_);
        _settleAsCaller(address(_actor));
    }

    function _settleAsCaller(address caller_) internal {
        vm.mockCall(
            address(_depositManager),
            abi.encodeWithSignature("claimYield(address,address,uint256,bool)"),
            abi.encode(address(_asset), uint256(1))
        );
        vm.prank(caller_);
        (address tokenOut, uint256 amountOut) = _core.settleYield(address(_asset), 1, _recipient);
        assertEq(tokenOut, address(_asset), "Role-holding caller receives the yield output token");
        assertEq(amountOut, 1, "Role-holding caller claims the requested yield");
    }

    // Scenarios: BLCORE-SETTLE-YIELD-A05.
    function test_givenNoOperatorRole_whenYieldSettled_reverts() public {
        _rolesAdmin.revokeRole(DEPOSIT_OPERATOR_ROLE, address(_core));
        bytes32 before = _ledger();
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, DEPOSIT_OPERATOR_ROLE)
        );
        vm.prank(address(_actor));
        _core.settleYield(address(_asset), 1, _recipient);
        assertEq(_ledger(), before, "Rejected yield claim changes no liabilities or custody");
    }

    // Scenarios: BLCORE-SETTLE-YIELD-D03.
    function test_givenDepositManagerPaused_whenYieldSettled_reverts() public {
        IEnabler(address(_depositManager)).disable("");
        bytes32 before = _ledger();
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(address(_actor));
        _core.settleYield(address(_asset), 1, _recipient);
        assertEq(_ledger(), before, "Rejected yield claim changes no liabilities or custody");
    }

    // Scenarios: BLCORE-SETTLE-YIELD-I01.
    function test_givenUnregisteredAsset_whenYieldSettled_reverts() public {
        bytes32 before = _ledger();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_AssetNotConfigured.selector,
                address(0xCAFE)
            )
        );
        vm.prank(address(_actor));
        _core.settleYield(address(0xCAFE), 1, _recipient);
        assertEq(_ledger(), before, "Rejected yield claim changes no liabilities or custody");
    }

    // Scenarios: BLCORE-SETTLE-YIELD-I02.
    function test_givenZeroRecipient_whenYieldSettled_reverts() public {
        bytes32 before = _ledger();
        vm.expectRevert(
            abi.encodeWithSelector(IDepositManager.DepositManager_ZeroAddress.selector)
        );
        vm.prank(address(_actor));
        _core.settleYield(address(_asset), 1, address(0));
        assertEq(_ledger(), before, "Rejected yield claim changes no liabilities or custody");
    }

    // Scenarios: BLCORE-SETTLE-YIELD-I03.
    function test_givenCustodianRecipient_whenYieldSettled_reverts() public {
        bytes32 before = _ledger();
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManagerV1_1.DepositManager_InvalidRecipient.selector,
                address(_depositManager)
            )
        );
        vm.prank(address(_actor));
        _core.settleYield(address(_asset), 1, address(_depositManager));
        assertEq(_ledger(), before, "Rejected yield claim changes no liabilities or custody");
    }

    // Scenarios: BLCORE-SETTLE-YIELD-I04.
    function test_givenZeroAmount_whenYieldSettled_reverts() public {
        bytes32 before = _ledger();
        vm.expectRevert(abi.encodeWithSelector(IAssetManager.AssetManager_ZeroAmount.selector));
        vm.prank(address(_actor));
        _core.settleYield(address(_asset), 0, _recipient);
        assertEq(_ledger(), before, "Rejected yield claim changes no liabilities or custody");
    }

    // Scenarios: BLCORE-SETTLE-YIELD-P02.
    function test_givenIndependentDependencyOutput_whenSettled(
        uint256 requested_,
        uint256 actual_
    ) public {
        requested_ = bound(requested_, 1, type(uint256).max);
        actual_ = bound(actual_, 1, type(uint256).max);
        vm.mockCall(
            address(_depositManager),
            abi.encodeWithSignature("claimYield(address,address,uint256,bool)"),
            abi.encode(address(_ohm), actual_)
        );
        vm.expectEmit(true, true, false, true, address(_core));
        emit IBurnerLoansYieldClaim.YieldClaimed(
            address(_asset),
            requested_,
            address(_ohm),
            actual_,
            _recipient
        );
        vm.prank(address(_actor));
        (address token, uint256 output) = _core.settleYield(
            address(_asset),
            requested_,
            _recipient
        );
        assertEq(token, address(_ohm), "Actual token forwarded");
        assertEq(output, actual_, "Actual output not nominal request");
        (, , uint256 reserved) = _payout.payoutReserves(address(_ohm));
        assertEq(reserved, 0, "No deferred-yield obligation");
    }

    // Scenarios: BLCORE-SETTLE-YIELD-P02.
    function test_givenActualVaultYield_whenSettled() public {
        (CoreCallbackToken token, ) = _vaultFixture();
        uint256 liabilities = _depositManager.getOperatorLiabilities(
            IERC20(address(token)),
            address(_core)
        );
        vm.prank(address(_actor));
        (address output, uint256 amount) = _core.settleYield(address(token), 50, _recipient);
        assertEq(output, address(token), "Underlying output token");
        assertEq(amount, 50, "25 shares at 2 assets per share redeem 50 raw units");
        assertEq(token.balanceOf(_recipient), 50, "Vault delivers directly once");
        assertEq(token.balanceOf(address(_payout)), 0, "Yield bypasses Payout");
        assertEq(
            _depositManager.getOperatorLiabilities(IERC20(address(token)), address(_core)),
            liabilities,
            "Yield preserves collateral liabilities"
        );
    }

    // Scenarios: BLCORE-SETTLE-YIELD-I05.
    function test_givenSubShareYield_whenSettled() public {
        (CoreCallbackToken token, ) = _vaultFixture();
        bytes32 before = _ledger();
        vm.recordLogs();
        vm.prank(address(_actor));
        (address output, uint256 amount) = _core.settleYield(address(token), 1, _recipient);
        assertEq(output, address(token), "Zero share conversion still returns token");
        assertEq(amount, 0, "1 asset at 2 assets per share rounds down to zero shares");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i)
            assertTrue(
                logs[i].emitter != address(_core),
                "Core emits no YieldClaimed for zero output"
            );
        assertEq(_ledger(), before, "Zero-share quote changes no custody");
    }

    // Scenarios: BLCORE-SETTLE-YIELD-P01.
    function test_givenInsolventWithdrawal_whenYieldSettled_reverts() public {
        (CoreCallbackToken token, ) = _vaultFixture();
        bytes32 before = _ledger();
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManager.DepositManager_Insolvent.selector,
                address(token),
                uint256(100),
                uint256(50),
                uint256(0)
            )
        );
        vm.prank(address(_actor));
        _core.settleYield(address(token), 150, _recipient);
        assertEq(
            _ledger(),
            before,
            "Insolvency rolls back vault redemption and recipient transfer"
        );
    }

    // Scenarios: BLCORE-SETTLE-YIELD-D04.
    function test_givenYieldDeliveryFailure_whenSettled_reverts() public {
        (CoreCallbackToken token, MockERC4626 vault) = _vaultFixture();
        vm.mockCallRevert(
            address(token),
            abi.encodeWithSignature("transfer(address,uint256)", _recipient, 50),
            abi.encodeWithSelector(DependencyFailed.selector)
        );
        bytes32 before = _ledger();
        uint256 assets = token.balanceOf(address(vault));
        vm.expectRevert(DependencyFailed.selector);
        vm.prank(address(_actor));
        _core.settleYield(address(token), 50, _recipient);
        assertEq(_ledger(), before, "Mandatory yield delivery rolls back");
        assertEq(token.balanceOf(address(vault)), assets, "Vault token backing restored");
    }

    // Scenarios: BLCORE-SETTLE-YIELD-C01.
    function test_givenVaultCallback_whenCaught() public {
        (CoreCallbackToken token, MockERC4626 vault) = _vaultFixture();
        _authorizeCollateralCallback(_actor);
        token.setCallbackFrom(
            address(vault),
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
        _core.settleYield(address(token), 50, _recipient);
        assertEq(
            token.callbackRevertSelector(),
            ReentrancyGuard.ReentrancyGuardReentrantCall.selector,
            "Authorized nested yield reaches Core lock"
        );
        assertEq(token.balanceOf(_recipient), 50, "Yield delivered once");
        assertEq(_position().depositedCollateral, 100, "Collateral principal preserved");
    }

    // Scenarios: BLCORE-SETTLE-YIELD-C02.
    function test_givenVaultCallback_whenPropagated() public {
        (CoreCallbackToken token, MockERC4626 vault) = _vaultFixture();
        _authorizeCollateralCallback(_actor);
        token.setCallbackFrom(
            address(vault),
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
        _core.settleYield(address(token), 50, _recipient);
        assertEq(
            _ledger(),
            before,
            "Mandatory vault callback propagation restores custody and liabilities"
        );
    }

    function _vaultFixture() internal returns (CoreCallbackToken token, MockERC4626 vault) {
        token = new CoreCallbackToken();
        _asset = token;
        vault = new MockERC4626(OZERC20(address(token)), "Yield vault", "YLD");
        _price.setPrice(address(token), 1e18);
        _depositManager.addAsset(
            IERC20(address(token)),
            IERC4626(address(vault)),
            type(uint256).max,
            0
        );
        _depositManager.addAssetPeriod(IERC20(address(token)), 1, address(_core));
        _config.addAsset(
            address(token),
            100000e9,
            IBurnerLoansRisk.AssetRiskConfigInput(8500, 12500, 100, 30 days, 90 days, 1000e6),
            IBurnerLoansRisk.AssetFeeConfig(25, 8000, 100, 900),
            false
        );
        token.mint(_borrower, 1000);
        vm.prank(_borrower);
        token.approve(address(_core), type(uint256).max);
        _deposit(100);
        token.mint(address(vault), 100);
    }
}
