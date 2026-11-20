// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.20;
import {IDepositManagerV1_1} from "src/policies/interfaces/deposits/IDepositManagerV1_1.sol";
import {Actions, Policy, toKeycode} from "src/Kernel.sol";

// Scenario-specific literals and established test variable names remain inline for auditability.
// Setup calls intentionally ignore return values when subsequent assertions verify their effects.
// forge-lint: disable-start(literal-instead-of-constant, mixed-case-variable, unused-return)

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";

// Contracts
import {DepositManagerRescueToken} from "./fixtures/DepositManagerRescueToken.sol";
import {ERC20} from "@openzeppelin-5.7.0/token/ERC20/ERC20.sol";
import {ReentrancyGuardTransient} from "@openzeppelin-5.7.0/utils/ReentrancyGuardTransient.sol";
import {OlympusTreasury} from "src/modules/TRSRY/OlympusTreasury.sol";
import {DepositManagerConfigTimelock} from "src/policies/deposits/DepositManagerConfigTimelock.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {MockERC4626} from "src/test/mocks/MockERC4626.sol";
import {MockERC7540ExternalShareVault} from "src/test/mocks/MockERC7540ExternalShareVault.sol";
import {MockERC7575Vault} from "src/test/mocks/MockERC7575Vault.sol";
import {ReentrantFeeToken} from "src/test/mocks/ReentrantFeeToken.sol";
import {DepositManagerTest} from "src/test/policies/DepositManager/DepositManagerTest.sol";

contract DepositManagerRescueTest is DepositManagerTest {
    MockERC20 public randomToken;

    function setUp() public override {
        super.setUp();

        randomToken = new MockERC20("Random", "RAND", 18);
    }

    // ========== rescue ==========

    // Scenarios: DM-RESCUE-C01.
    function test_givenRescuedTokenCallback_whenBorrowingWithdrawal() public givenIsEnabled {
        ReentrantFeeToken callbackToken = new ReentrantFeeToken();
        vm.startPrank(ADMIN);
        rolesAdmin.grantRole("deposit_operator", address(callbackToken));
        depositManager.setOperatorName(address(callbackToken), "rsc");
        depositManager.addAsset(iAsset, IERC4626(address(0)), type(uint256).max, 0);
        depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD, address(callbackToken));
        vm.stopPrank();

        asset.mint(DEPOSITOR, 100);
        vm.prank(DEPOSITOR);
        asset.approve(address(depositManager), 100);
        vm.prank(address(callbackToken));
        depositManager.deposit(
            IDepositManager.DepositParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                amount: 100,
                shouldWrap: false
            })
        );
        IDepositManager.BorrowingWithdrawParams memory params = IDepositManager
            .BorrowingWithdrawParams({asset: iAsset, recipient: RECIPIENT, amount: 1});
        callbackToken.mint(address(depositManager), 10);
        callbackToken.setCallback(
            address(depositManager),
            abi.encodeCall(IDepositManager.borrowingWithdraw, (params))
        );
        assertEq(
            _preview(DEPOSITOR, address(callbackToken)),
            10,
            "callback quote equals seeded balance"
        );

        vm.prank(ADMIN);
        depositManager.rescue(address(callbackToken));

        assertFalse(callbackToken.callbackSucceeded(), "nested borrowing must fail");
        assertEq(
            callbackToken.callbackRevertSelector(),
            ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector,
            "guard must reject callback"
        );
        assertEq(callbackToken.balanceOf(address(trsry)), 10, "Treasury receives rescue once");
        assertEq(
            callbackToken.balanceOf(address(depositManager)),
            0,
            "rescue empties stray token balance"
        );
        assertEq(asset.balanceOf(address(depositManager)), 100, "managed custody unchanged");
        assertEq(
            depositManager.getBorrowedAmount(iAsset, address(callbackToken)),
            0,
            "no nested debt"
        );
        assertEq(
            depositManager.getOperatorLiabilities(iAsset, address(callbackToken)),
            100,
            "liabilities unchanged"
        );

        // The same authorized, funded action succeeds once the outer rescue has released the guard.
        vm.prank(address(callbackToken));
        depositManager.borrowingWithdraw(params);
        assertEq(asset.balanceOf(RECIPIENT), 1, "nested action is otherwise executable");
    }

    // Scenarios: DM-RESCUE-L07.
    function test_givenUtilizationExceedsLoweredCap_whenRescuingUnmanagedToken_succeeds(
        bool enabled_
    )
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAddedWithZeroAddress
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
    {
        vm.prank(DEPOSIT_OPERATOR);
        (, uint256 creditedAmount) = depositManager.deposit(
            IDepositManager.DepositParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                amount: MINT_AMOUNT,
                shouldWrap: false
            })
        );
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.borrowingWithdraw(
            IDepositManager.BorrowingWithdrawParams({
                asset: iAsset,
                amount: 1,
                recipient: RECIPIENT
            })
        );
        vm.prank(ADMIN);
        depositManager.setAssetDepositCap(iAsset, 0);
        vm.prank(ADMIN);
        depositManager.disableAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
        _pauseIfRequested(enabled_);
        randomToken.mint(address(depositManager), 100e18);
        bytes32 beforeState = _protectedState();
        assertEq(
            _preview(DEPOSITOR, address(randomToken)),
            100e18,
            "lowered cap does not prevent quote"
        );

        vm.prank(ADMIN);
        depositManager.rescue(address(randomToken));

        assertEq(randomToken.balanceOf(address(trsry)), 100e18, "Treasury rescued balance");
        assertEq(_protectedState(), beforeState, "disabled indebted route is unchanged");
        assertEq(
            depositManager.getBorrowedAmount(iAsset, DEPOSIT_OPERATOR),
            1,
            "outstanding debt is preserved"
        );
        assertEq(
            _assetDepositCapUtilization(iAsset),
            creditedAmount,
            "rescue should preserve utilization"
        );
    }

    // given the contract is disabled
    //  when the caller is admin
    //   [X] it transfers the balance to TRSRY
    //   [X] it emits a TokenRescued event
    function test_givenContractDisabled_whenCallerIsAdmin() public {
        _rescueAndAssert(ADMIN);
    }

    // Scenarios: DM-RESCUE-A03.
    function test_givenContractDisabled_whenCallerIsDepositManagerAdmin_reverts() public {
        vm.prank(ADMIN);
        depositManager.enable("");
        _configureController();
        _pauseIfRequested(false);
        _assertUnauthorizedRescue(DEPOSIT_MANAGER_ADMIN);
    }

    // Scenarios: DM-RESCUE-A02.
    function test_whenCallerIsUnauthorized_reverts(
        address caller_,
        address viewer_
    ) public givenIsEnabled givenProtectedPositions {
        _configureController();
        vm.assume(!roles.hasRole(caller_, "admin"));
        vm.assume(caller_ == address(0) || caller_ != depositManager.configOperator());
        _assertUnauthorizedRescue(caller_, viewer_);
    }

    function _assertUnauthorizedRescue(address caller_) internal {
        _assertUnauthorizedRescue(caller_, DEPOSITOR);
    }

    function _assertUnauthorizedRescue(address caller_, address viewer_) internal {
        randomToken.mint(address(depositManager), 100e18);
        bytes32 beforeState = _rescueState();
        vm.recordLogs();
        assertEq(
            _preview(viewer_, address(randomToken)),
            100e18,
            "independent viewer can quote without authorization"
        );
        vm.expectRevert(
            abi.encodeWithSelector(IConfigOperator.ConfigOperator_Unauthorized.selector, caller_)
        );
        vm.prank(caller_);
        depositManager.rescue(address(randomToken));
        assertEq(
            _rescueState(),
            beforeState,
            "unauthorized rescue preserves all state and custody"
        );
        assertEq(vm.getRecordedLogs().length, 0, "unauthorized rescue and preview emit no logs");
        assertEq(
            randomToken.balanceOf(address(depositManager)),
            100e18,
            "unauthorized rescue preserves custody"
        );
        assertEq(
            randomToken.balanceOf(address(trsry)),
            0,
            "unauthorized rescue does not pay Treasury"
        );
    }

    // given the token address is zero
    //  given there are no managed assets
    //   [X] it reverts
    //  given the managed asset has a vault with the zero address
    //   [X] it reverts
    //  given the managed asset has a vault with a non-zero address
    //   [X] it reverts
    // Scenarios: DM-RESCUE-I01.
    function test_rescue_givenNoManagedAssets_givenTokenAddressZero_reverts(
        bool enabled_,
        address viewer_
    ) public givenIsEnabled {
        _pauseIfRequested(enabled_);
        _assertCannotRescue(address(0), viewer_);
    }

    // Scenarios: DM-RESCUE-I01.
    function test_rescue_givenAssetWithZeroVault_givenTokenAddressZero_reverts(
        bool enabled_,
        address viewer_
    ) public givenIsEnabled givenFacilityNameIsSetDefault givenAssetIsAddedWithZeroAddress {
        _pauseIfRequested(enabled_);
        _assertCannotRescue(address(0), viewer_);
    }

    // Scenarios: DM-RESCUE-I01.
    function test_rescue_givenAssetWithVault_givenTokenAddressZero_reverts(
        bool enabled_,
        address viewer_
    ) public givenIsEnabled givenFacilityNameIsSetDefault givenAssetIsAdded {
        _pauseIfRequested(enabled_);
        _assertCannotRescue(address(0), viewer_);
    }

    // given the token address is a configured asset
    //  given the asset is disabled
    //   [X] it reverts
    //  [X] it reverts
    // Scenarios: DM-RESCUE-I07.
    function test_rescue_givenTokenIsConfiguredAsset_givenAssetDisabled_reverts()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
    {
        asset.mint(address(depositManager), 100e18);

        // Disable the asset period
        vm.prank(ADMIN);
        depositManager.disableAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);

        _assertCannotRescue(address(asset), DEPOSITOR);
    }

    // Scenarios: DM-RESCUE-I03.
    function test_rescue_givenTokenIsConfiguredAsset_reverts()
        public
        givenIsEnabled
        givenAssetIsAdded
    {
        asset.mint(address(depositManager), 100e18);

        _assertCannotRescue(address(asset), DEPOSITOR);
    }

    // given the token address is a configured vault
    //  [X] it reverts
    // Scenarios: DM-RESCUE-I04.
    function test_rescue_givenTokenIsConfiguredVault_reverts()
        public
        givenIsEnabled
        givenAssetIsAdded
    {
        _assertCannotRescue(address(vault), DEPOSITOR);
    }

    // Scenarios: DM-RESCUE-I05.
    function test_givenTokenIsConfiguredExternalShareToken_reverts() public givenIsEnabled {
        MockERC7540ExternalShareVault externalVault = new MockERC7540ExternalShareVault(
            asset,
            false,
            true,
            true
        );
        vm.prank(ADMIN);
        depositManager.addAsset(iAsset, IERC4626(address(externalVault)), type(uint256).max, 0);
        IERC20 shareToken = IERC20(externalVault.share());

        _assertCannotRescue(address(shareToken), DEPOSITOR);
    }

    // given the token address is not a configured asset or vault
    //  given the token has zero balance
    //   [X] it does not revert
    //   [X] it does not emit an event
    function test_rescue_givenTokenNotConfigured_givenZeroBalance_doesNotRevertOrEmit()
        public
        givenIsEnabled
    {
        vm.prank(ADMIN);
        depositManager.rescue(address(randomToken));

        assertEq(randomToken.balanceOf(address(depositManager)), 0, "zero balance remains zero");
        assertEq(randomToken.balanceOf(address(trsry)), 0, "zero rescue makes no Treasury payment");
    }

    //  given the token has a balance
    //   [X] it transfers the balance to TRSRY
    //   [X] it emits a TokenRescued event
    function test_rescue_givenTokenNotConfigured_givenHasBalance_transfersToTrsryAndEmits()
        public
        givenIsEnabled
    {
        _rescueAndAssert(ADMIN);
    }

    // Scenarios: DM-RESCUE-A03.
    function test_givenContractEnabled_whenCallerIsDepositManagerAdmin_reverts()
        public
        givenIsEnabled
    {
        _configureController();
        _assertUnauthorizedRescue(DEPOSIT_MANAGER_ADMIN);
    }

    function _rescueAndAssert(address caller_) internal {
        uint256 tokenAmount = 100e18;
        randomToken.mint(address(depositManager), tokenAmount);
        assertEq(
            _preview(DEPOSITOR, address(randomToken)),
            tokenAmount,
            "preview equals independently funded amount"
        );

        vm.expectEmit(address(depositManager));
        emit IDepositManager.TokenRescued(address(randomToken), tokenAmount);

        vm.prank(caller_);
        depositManager.rescue(address(randomToken));

        assertEq(
            randomToken.balanceOf(address(depositManager)),
            0,
            "DepositManager should not retain rescued tokens"
        );
        assertEq(
            randomToken.balanceOf(address(trsry)),
            tokenAmount,
            "Treasury should receive the rescued tokens"
        );
        assertEq(_preview(address(0), address(randomToken)), 0, "preview is zero after rescue");
    }

    // Scenarios: DM-RESCUE-L01.
    function test_givenInactiveAndDisabled_whenUnauthorizedCallerRescues_revertsActivityFirst(
        address caller_
    ) public {
        randomToken.mint(address(depositManager), 1);
        vm.prank(ADMIN);
        kernel.executeAction(Actions.DeactivatePolicy, address(depositManager));
        bytes32 beforeState = _rescueState();
        vm.recordLogs();
        vm.expectRevert(IDepositManagerV1_1.DepositManager_PolicyInactive.selector);
        _preview(caller_, address(0));
        vm.expectRevert(IDepositManagerV1_1.DepositManager_PolicyInactive.selector);
        vm.prank(caller_);
        depositManager.rescue(address(0));
        assertEq(
            _rescueState(),
            beforeState,
            "inactive competing faults preserve custody and accounting"
        );
        assertEq(vm.getRecordedLogs().length, 0, "inactive competing faults emit no logs");
    }

    // Scenarios: DM-RESCUE-A01, DM-RESCUE-A07, DM-RESCUE-L02, DM-RESCUE-N02.
    function test_givenSelectedOperator_whenRescuing_matchesPermissionlessPreview(
        address operator_,
        address viewer_,
        uint256 amount_,
        bool enabled_
    ) public givenIsEnabled givenProtectedPositions {
        vm.assume(operator_ != address(0));
        vm.prank(ADMIN);
        depositManager.setConfigOperator(operator_);
        if (!enabled_) {
            vm.prank(EMERGENCY);
            depositManager.disable("");
        }
        _fundAndRescue(operator_, viewer_, amount_);
        assertEq(depositManager.isEnabled(), enabled_, "rescue preserves local enablement");
    }

    // Scenarios: DM-RESCUE-A01, DM-RESCUE-L02, DM-RESCUE-N02.
    function test_givenAdmin_whenRescuing_matchesPermissionlessPreview(
        address caller_,
        address viewer_,
        uint256 amount_,
        bool enabled_
    ) public givenIsEnabled givenProtectedPositions {
        _grantAdmin(caller_);
        vm.prank(ADMIN);
        depositManager.setConfigOperator(CONFIG_OPERATOR);
        if (!enabled_) {
            vm.prank(EMERGENCY);
            depositManager.disable("");
        }
        _fundAndRescue(caller_, viewer_, amount_);
        assertEq(depositManager.isEnabled(), enabled_, "admin rescue preserves local enablement");
    }

    // Scenarios: DM-RESCUE-L03.
    function test_givenPolicyInactive_whenRescuing_revertsRegardlessOfEnablement(
        address caller_,
        address viewer_,
        uint256 amount_,
        bool enabled_
    ) public givenIsEnabled givenProtectedPositions {
        _grantAdmin(caller_);
        if (!enabled_) {
            vm.prank(EMERGENCY);
            depositManager.disable("");
        }
        vm.prank(ADMIN);
        kernel.executeAction(Actions.DeactivatePolicy, address(depositManager));
        randomToken.mint(address(depositManager), amount_);
        bytes32 beforeState = _rescueState();
        vm.recordLogs();
        vm.expectRevert(IDepositManagerV1_1.DepositManager_PolicyInactive.selector);
        _preview(viewer_, address(randomToken));
        vm.expectRevert(IDepositManagerV1_1.DepositManager_PolicyInactive.selector);
        vm.prank(caller_);
        depositManager.rescue(address(randomToken));
        assertEq(_rescueState(), beforeState, "inactive calls preserve custody and accounting");
        assertEq(vm.getRecordedLogs().length, 0, "inactive calls emit no logs");
        assertEq(
            depositManager.isEnabled(),
            enabled_,
            "inactivity does not change local enablement"
        );
    }

    // Scenarios: DM-RESCUE-L02, DM-RESCUE-N02.
    function test_givenLifecycleBoundarySeeds_whenRescuing() public {
        uint256 snapshot = vm.snapshotState();
        test_givenAdmin_whenRescuing_matchesPermissionlessPreview(ADMIN, address(0), 0, false);
        assertTrue(vm.revertToState(snapshot), "restore zero balance lifecycle seed");
        test_givenAdmin_whenRescuing_matchesPermissionlessPreview(
            ADMIN,
            DEPOSIT_MANAGER_ADMIN,
            1,
            false
        );
        assertTrue(vm.revertToState(snapshot), "restore one unit lifecycle seed");
        test_givenAdmin_whenRescuing_matchesPermissionlessPreview(
            ADMIN,
            address(this),
            type(uint256).max,
            true
        );
    }

    // Scenarios: DM-RESCUE-L03.
    function test_givenInactiveLifecycleBoundarySeeds_whenRescuing_reverts() public {
        uint256 snapshot = vm.snapshotState();
        test_givenPolicyInactive_whenRescuing_revertsRegardlessOfEnablement(
            ADMIN,
            address(0),
            0,
            false
        );
        assertTrue(vm.revertToState(snapshot), "restore active seed fixture");
        test_givenPolicyInactive_whenRescuing_revertsRegardlessOfEnablement(
            ADMIN,
            DEPOSIT_MANAGER_ADMIN,
            type(uint256).max,
            true
        );
    }

    // Scenarios: DM-RESCUE-L03.
    function test_givenSelectedOperatorAndPolicyInactive_whenRescuing_reverts(
        address operator_,
        address viewer_,
        uint256 amount_,
        bool enabled_
    ) public givenIsEnabled givenProtectedPositions {
        vm.assume(operator_ != address(0));
        vm.assume(!roles.hasRole(operator_, "admin"));
        vm.prank(ADMIN);
        depositManager.setConfigOperator(operator_);
        _pauseIfRequested(enabled_);
        vm.prank(ADMIN);
        kernel.executeAction(Actions.DeactivatePolicy, address(depositManager));
        randomToken.mint(address(depositManager), amount_);
        bytes32 beforeState = _rescueState();
        vm.recordLogs();
        vm.expectRevert(IDepositManagerV1_1.DepositManager_PolicyInactive.selector);
        _preview(viewer_, address(randomToken));
        vm.expectRevert(IDepositManagerV1_1.DepositManager_PolicyInactive.selector);
        vm.prank(operator_);
        depositManager.rescue(address(randomToken));
        assertEq(
            _rescueState(),
            beforeState,
            "inactive delegated rescue preserves all custody and accounting"
        );
        assertEq(vm.getRecordedLogs().length, 0, "inactive delegated calls emit no logs");
    }

    // Scenarios: DM-RESCUE-L03.
    function test_givenSelectedOperatorInactiveBoundarySeeds_whenRescuing_reverts() public {
        uint256 snapshot = vm.snapshotState();
        test_givenSelectedOperatorAndPolicyInactive_whenRescuing_reverts(
            CONFIG_OPERATOR,
            address(0),
            0,
            false
        );
        assertTrue(vm.revertToState(snapshot), "restore delegated inactive zero seed");
        test_givenSelectedOperatorAndPolicyInactive_whenRescuing_reverts(
            address(this),
            EMERGENCY,
            type(uint256).max,
            true
        );
    }

    // Scenarios: DM-RESCUE-L07.
    function test_givenIndebtedDisabledRouteLifecycleSeeds_whenRescuing() public {
        uint256 snapshot = vm.snapshotState();
        test_givenUtilizationExceedsLoweredCap_whenRescuingUnmanagedToken_succeeds(false);
        assertTrue(vm.revertToState(snapshot), "restore indebted disabled route seed");
        test_givenUtilizationExceedsLoweredCap_whenRescuingUnmanagedToken_succeeds(true);
    }

    // Scenarios: DM-RESCUE-A01, DM-RESCUE-A07, DM-RESCUE-N02.
    function test_givenEachAuthorityClass_whenRescuing() public {
        uint256 snapshot = vm.snapshotState();
        test_givenSelectedOperator_whenRescuing_matchesPermissionlessPreview(
            CONFIG_OPERATOR,
            EMERGENCY,
            1,
            false
        );
        assertTrue(vm.revertToState(snapshot), "restore operator-only authority seed");
        test_givenSelectedOperator_whenRescuing_matchesPermissionlessPreview(
            ADMIN,
            DEPOSIT_OPERATOR,
            1,
            true
        );
        assertTrue(vm.revertToState(snapshot), "restore overlapping authority seed");
        test_givenSelectedOperator_whenRescuing_matchesPermissionlessPreview(
            address(this),
            CONFIG_OPERATOR,
            1,
            false
        );
    }

    // Scenarios: DM-RESCUE-A02, DM-RESCUE-A03.
    function test_givenEachUnauthorizedClass_whenRescuing_reverts() public {
        uint256 snapshot = vm.snapshotState();
        test_whenCallerIsUnauthorized_reverts(address(0), ADMIN);
        assertTrue(vm.revertToState(snapshot), "restore zero caller seed");
        test_whenCallerIsUnauthorized_reverts(DEPOSIT_MANAGER_ADMIN, CONFIG_OPERATOR);
        assertTrue(vm.revertToState(snapshot), "restore manager-only seed");
        test_whenCallerIsUnauthorized_reverts(EMERGENCY, address(this));
        assertTrue(vm.revertToState(snapshot), "restore emergency-only seed");
        test_whenCallerIsUnauthorized_reverts(DEPOSIT_OPERATOR, address(0));
        assertTrue(vm.revertToState(snapshot), "restore operator-role-only seed");
        test_whenCallerIsUnauthorized_reverts(address(this), EMERGENCY);
    }

    // Scenarios: DM-RESCUE-A04.
    function test_givenOperatorRotated_whenOldOperatorRescues_reverts() public givenIsEnabled {
        vm.startPrank(ADMIN);
        depositManager.setConfigOperator(CONFIG_OPERATOR);
        depositManager.setConfigOperator(RECIPIENT);
        vm.stopPrank();
        _assertUnauthorizedRescue(CONFIG_OPERATOR);
    }

    // Scenarios: DM-RESCUE-A05.
    function test_givenDelegationCleared_whenZeroCallerRescues_reverts() public givenIsEnabled {
        vm.startPrank(ADMIN);
        depositManager.setConfigOperator(CONFIG_OPERATOR);
        depositManager.setConfigOperator(address(0));
        vm.stopPrank();
        _assertUnauthorizedRescue(address(0));
    }

    // Scenarios: DM-RESCUE-A06.
    function test_givenNoController_whenAdminRescues() public givenIsEnabled {
        _rescueAndAssert(ADMIN);
    }

    // Scenarios: DM-RESCUE-A06.
    function test_givenControllerViewsBroken_whenAdminRescues() public givenIsEnabled {
        vm.prank(ADMIN);
        depositManager.setConfigOperator(CONFIG_OPERATOR);
        vm.mockCallRevert(CONFIG_OPERATOR, abi.encodeWithSignature("isEnabled()"), hex"deadbeef");
        vm.mockCallRevert(CONFIG_OPERATOR, abi.encodeWithSignature("kernel()"), hex"deadbeef");
        _rescueAndAssert(ADMIN);
    }

    // Scenarios: DM-RESCUE-A06.
    function test_givenControllerDisabled_whenAdminRescues() public givenIsEnabled {
        DepositManagerConfigTimelock controller = _configureController();
        vm.prank(EMERGENCY);
        controller.disable("");
        _rescueAndAssert(ADMIN);
    }

    // Scenarios: DM-RESCUE-A06.
    function test_givenControllerInactive_whenAdminRescues() public givenIsEnabled {
        DepositManagerConfigTimelock controller = _configureController();
        vm.prank(ADMIN);
        kernel.executeAction(Actions.DeactivatePolicy, address(controller));
        _rescueAndAssert(ADMIN);
    }

    // Scenarios: DM-RESCUE-L04.
    function test_givenReEnabled_whenRescuing_preservesTransitionHistory(
        address caller_,
        address viewer_,
        uint256 amount_
    ) public givenIsEnabled {
        _grantAdmin(caller_);
        vm.prank(ADMIN);
        depositManager.setConfigOperator(CONFIG_OPERATOR);
        vm.prank(EMERGENCY);
        depositManager.disable("");
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        depositManager.reEnable();
        uint48 transition = depositManager.lastTransitionAt();
        _fundAndRescue(caller_, viewer_, amount_);
        assertEq(
            depositManager.lastTransitionAt(),
            transition,
            "recovery does not alter lifecycle history"
        );
    }

    // Scenarios: DM-RESCUE-L04.
    function test_givenSelectedOperatorAndReEnabled_whenRescuing_preservesTransitionHistory(
        address caller_,
        address viewer_,
        uint256 amount_
    ) public givenIsEnabled {
        vm.assume(caller_ != address(0));
        vm.assume(!roles.hasRole(caller_, "admin"));
        vm.prank(ADMIN);
        depositManager.setConfigOperator(caller_);
        vm.prank(EMERGENCY);
        depositManager.disable("");
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        depositManager.reEnable();
        uint48 transition = depositManager.lastTransitionAt();
        _fundAndRescue(caller_, viewer_, amount_);
        assertEq(
            depositManager.lastTransitionAt(),
            transition,
            "delegated recovery preserves lifecycle history"
        );
    }

    // Scenarios: DM-RESCUE-L03.
    function test_givenPolicyReactivated_whenRescuing() public givenIsEnabled {
        vm.startPrank(ADMIN);
        kernel.executeAction(Actions.DeactivatePolicy, address(depositManager));
        kernel.executeAction(Actions.ActivatePolicy, address(depositManager));
        vm.stopPrank();
        _fundAndRescue(ADMIN, address(0), 1);
    }

    // Scenarios: DM-RESCUE-L05.
    function test_givenUnauthorizedCaller_whenTokenZero_revertsAuthorityFirst(
        address caller_,
        bool enabled_
    ) public givenIsEnabled {
        vm.assume(!roles.hasRole(caller_, "admin"));
        if (!enabled_) {
            vm.prank(EMERGENCY);
            depositManager.disable("");
        }
        randomToken.mint(address(depositManager), 1);
        bytes32 beforeState = _rescueState();
        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManager.DepositManager_CannotRescueAsset.selector,
                address(0)
            )
        );
        _preview(caller_, address(0));
        vm.expectRevert(
            abi.encodeWithSelector(IConfigOperator.ConfigOperator_Unauthorized.selector, caller_)
        );
        vm.prank(caller_);
        depositManager.rescue(address(0));
        assertEq(
            _rescueState(),
            beforeState,
            "authority-first zero-token rejection preserves all custody and accounting"
        );
        assertEq(
            vm.getRecordedLogs().length,
            0,
            "authority-first zero-token rejection emits no logs"
        );
    }

    // Scenarios: DM-RESCUE-L05.
    function test_givenUnauthorizedCaller_whenManagedToken_revertsAuthorityFirst(
        address caller_,
        bool enabled_
    ) public givenIsEnabled givenAssetIsAdded {
        vm.assume(!roles.hasRole(caller_, "admin"));
        if (!enabled_) {
            vm.prank(EMERGENCY);
            depositManager.disable("");
        }
        asset.mint(address(depositManager), 1);
        bytes32 beforeState = _rescueState();
        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManager.DepositManager_CannotRescueAsset.selector,
                address(asset)
            )
        );
        _preview(caller_, address(asset));
        vm.expectRevert(
            abi.encodeWithSelector(IConfigOperator.ConfigOperator_Unauthorized.selector, caller_)
        );
        vm.prank(caller_);
        depositManager.rescue(address(asset));
        assertEq(
            _rescueState(),
            beforeState,
            "authority-first managed-token rejection preserves all custody and accounting"
        );
        assertEq(
            vm.getRecordedLogs().length,
            0,
            "authority-first managed-token rejection emits no logs"
        );
    }

    // Scenarios: DM-RESCUE-L05.
    function test_givenAuthorityFirstLifecycleSeeds_whenRescuing_reverts() public {
        uint256 snapshot = vm.snapshotState();
        test_givenUnauthorizedCaller_whenTokenZero_revertsAuthorityFirst(
            DEPOSIT_MANAGER_ADMIN,
            false
        );
        assertTrue(vm.revertToState(snapshot), "restore zero-token disabled precedence seed");
        test_givenUnauthorizedCaller_whenTokenZero_revertsAuthorityFirst(address(0), true);
        assertTrue(vm.revertToState(snapshot), "restore zero-token enabled precedence seed");
        test_givenUnauthorizedCaller_whenManagedToken_revertsAuthorityFirst(EMERGENCY, false);
        assertTrue(vm.revertToState(snapshot), "restore managed-token disabled precedence seed");
        test_givenUnauthorizedCaller_whenManagedToken_revertsAuthorityFirst(DEPOSIT_OPERATOR, true);
    }

    // Scenarios: DM-RESCUE-I02.
    function test_whenTokenHasNoCode_revertsConsistently(
        address token_,
        address viewer_,
        bool enabled_
    ) public givenIsEnabled {
        vm.assume(token_ != address(0) && token_.code.length == 0);
        _pauseIfRequested(enabled_);
        _assertCannotRescue(token_, viewer_);
    }

    // Scenarios: DM-RESCUE-I01, DM-RESCUE-I02.
    function test_givenZeroAndNoCodeLifecycleSeeds_whenRescuing_reverts() public {
        uint256 snapshot = vm.snapshotState();
        test_rescue_givenNoManagedAssets_givenTokenAddressZero_reverts(false, address(0));
        assertTrue(vm.revertToState(snapshot), "restore zero token no-assets disabled seed");
        test_rescue_givenNoManagedAssets_givenTokenAddressZero_reverts(true, ADMIN);
        assertTrue(vm.revertToState(snapshot), "restore zero token no-assets enabled seed");
        test_rescue_givenAssetWithZeroVault_givenTokenAddressZero_reverts(false, CONFIG_OPERATOR);
        assertTrue(vm.revertToState(snapshot), "restore zero token idle disabled seed");
        test_rescue_givenAssetWithZeroVault_givenTokenAddressZero_reverts(
            true,
            DEPOSIT_MANAGER_ADMIN
        );
        assertTrue(vm.revertToState(snapshot), "restore zero token idle enabled seed");
        test_rescue_givenAssetWithVault_givenTokenAddressZero_reverts(false, EMERGENCY);
        assertTrue(vm.revertToState(snapshot), "restore zero token vault disabled seed");
        test_rescue_givenAssetWithVault_givenTokenAddressZero_reverts(true, DEPOSIT_OPERATOR);
        assertTrue(vm.revertToState(snapshot), "restore zero token vault enabled seed");
        test_whenTokenHasNoCode_revertsConsistently(address(type(uint160).max), address(0), false);
        assertTrue(vm.revertToState(snapshot), "restore no-code address maximum seed");
        test_whenTokenHasNoCode_revertsConsistently(DEPOSITOR, EMERGENCY, true);
    }

    // Scenarios: DM-RESCUE-I03.
    function test_givenManagedUnderlying_whenBalanceVaries_reverts(
        uint96 balance_,
        address viewer_,
        bool enabled_
    ) public givenIsEnabled givenAssetIsAdded {
        asset.mint(address(depositManager), uint256(balance_));
        _pauseIfRequested(enabled_);
        _assertCannotRescue(address(asset), viewer_);
    }

    // Scenarios: DM-RESCUE-I03.
    function test_givenManagedIdleUnderlying_whenBalanceVaries_reverts(
        uint96 balance_,
        address viewer_,
        bool enabled_
    ) public givenIsEnabled givenAssetIsAddedWithZeroAddress {
        asset.mint(address(depositManager), uint256(balance_));
        _pauseIfRequested(enabled_);
        _assertCannotRescue(address(asset), viewer_);
    }

    // Scenarios: DM-RESCUE-I04.
    function test_givenManagedVault_whenBalanceVaries_reverts(
        uint96 balance_,
        address viewer_,
        bool enabled_
    ) public givenIsEnabled givenAssetIsAdded {
        deal(address(vault), address(depositManager), uint256(balance_));
        _pauseIfRequested(enabled_);
        _assertCannotRescue(address(vault), viewer_);
    }

    // Scenarios: DM-RESCUE-I05.
    function test_givenManagedExternalShares_whenBalanceVaries_reverts(
        uint96 balance_,
        address viewer_,
        bool enabled_
    ) public givenIsEnabled {
        MockERC7575Vault externalVault = _configureExternalVault();
        address storedShare = externalVault.share();
        deal(storedShare, address(depositManager), uint256(balance_));
        _pauseIfRequested(enabled_);
        _assertCannotRescue(storedShare, viewer_);
    }

    // Scenarios: DM-RESCUE-I03, DM-RESCUE-I04, DM-RESCUE-I05.
    function test_givenManagedBalanceBoundarySeeds_whenRescuing_reverts() public {
        uint256 snapshot = vm.snapshotState();
        test_givenManagedUnderlying_whenBalanceVaries_reverts(0, address(0), true);
        assertTrue(vm.revertToState(snapshot), "restore underlying zero seed");
        test_givenManagedUnderlying_whenBalanceVaries_reverts(1, EMERGENCY, false);
        assertTrue(vm.revertToState(snapshot), "restore underlying positive seed");
        test_givenManagedIdleUnderlying_whenBalanceVaries_reverts(0, DEPOSIT_OPERATOR, false);
        assertTrue(vm.revertToState(snapshot), "restore idle zero seed");
        test_givenManagedIdleUnderlying_whenBalanceVaries_reverts(1, ADMIN, true);
        assertTrue(vm.revertToState(snapshot), "restore idle positive seed");
        test_givenManagedVault_whenBalanceVaries_reverts(0, DEPOSIT_MANAGER_ADMIN, false);
        assertTrue(vm.revertToState(snapshot), "restore vault zero seed");
        test_givenManagedVault_whenBalanceVaries_reverts(1, CONFIG_OPERATOR, true);
        assertTrue(vm.revertToState(snapshot), "restore vault positive seed");
        test_givenManagedExternalShares_whenBalanceVaries_reverts(0, address(this), true);
        assertTrue(vm.revertToState(snapshot), "restore external share zero seed");
        test_givenManagedExternalShares_whenBalanceVaries_reverts(1, address(0), false);
    }

    // Scenarios: DM-RESCUE-I06.
    function test_givenVaultChangesReportedShare_whenRescuingStoredShare_reverts(
        address viewer_,
        uint96 balance_,
        bool enabled_
    ) public givenIsEnabled {
        MockERC7575Vault externalVault = _configureExternalVault();
        address storedShare = externalVault.share();
        deal(storedShare, address(depositManager), balance_);
        externalVault.setReportedShare(address(randomToken));
        _pauseIfRequested(enabled_);
        _assertCannotRescue(storedShare, viewer_);
    }

    // Scenarios: DM-RESCUE-I06.
    function test_givenVaultShareReadReverts_whenRescuingStoredShare_reverts(
        address viewer_,
        uint96 balance_,
        bool enabled_
    ) public givenIsEnabled {
        MockERC7575Vault externalVault = _configureExternalVault();
        address storedShare = externalVault.share();
        deal(storedShare, address(depositManager), balance_);
        externalVault.setShareQueryReverts(true);
        _pauseIfRequested(enabled_);
        _assertCannotRescue(storedShare, viewer_);
    }

    // Scenarios: DM-RESCUE-I07.
    function test_givenDisabledEmptyExternalShareRoute_whenRescuingAnyManagedToken_reverts(
        address viewer_,
        uint96 balance_,
        bool enabled_
    ) public givenIsEnabled {
        MockERC7575Vault externalVault = _configureExternalVault();
        asset.mint(address(depositManager), balance_);
        deal(address(externalVault), address(depositManager), balance_);
        deal(externalVault.share(), address(depositManager), balance_);
        vm.startPrank(ADMIN);
        depositManager.setOperatorName(DEPOSIT_OPERATOR, "one");
        depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
        depositManager.disableAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
        vm.stopPrank();
        _pauseIfRequested(enabled_);
        assertEq(
            depositManager.getOperatorLiabilities(iAsset, DEPOSIT_OPERATOR),
            0,
            "route has no obligations"
        );
        _assertCannotRescue(address(asset), viewer_);
        _assertCannotRescue(address(externalVault), viewer_);
        _assertCannotRescue(externalVault.share(), viewer_);
    }

    // Scenarios: DM-RESCUE-I06, DM-RESCUE-I07.
    function test_givenStoredShareAndRetiredRouteBoundarySeeds_whenRescuing_reverts() public {
        uint256 snapshot = vm.snapshotState();
        test_givenVaultChangesReportedShare_whenRescuingStoredShare_reverts(address(0), 0, false);
        assertTrue(vm.revertToState(snapshot), "restore changed share zero seed");
        test_givenVaultChangesReportedShare_whenRescuingStoredShare_reverts(ADMIN, 1, true);
        assertTrue(vm.revertToState(snapshot), "restore changed share positive seed");
        test_givenVaultShareReadReverts_whenRescuingStoredShare_reverts(EMERGENCY, 0, true);
        assertTrue(vm.revertToState(snapshot), "restore reverting share zero seed");
        test_givenVaultShareReadReverts_whenRescuingStoredShare_reverts(
            DEPOSIT_MANAGER_ADMIN,
            1,
            false
        );
        assertTrue(vm.revertToState(snapshot), "restore reverting share positive seed");
        test_givenDisabledEmptyExternalShareRoute_whenRescuingAnyManagedToken_reverts(
            CONFIG_OPERATOR,
            0,
            false
        );
        assertTrue(vm.revertToState(snapshot), "restore disabled empty zero seed");
        test_givenDisabledEmptyExternalShareRoute_whenRescuingAnyManagedToken_reverts(
            DEPOSIT_OPERATOR,
            1,
            true
        );
    }

    // Scenarios: DM-RESCUE-I08.
    function test_givenManagedTokenSurplus_whenRescuing_reverts(
        address viewer_,
        bool enabled_
    ) public givenIsEnabled givenProtectedPositions {
        asset.mint(address(depositManager), 1000);
        _pauseIfRequested(enabled_);
        _assertCannotRescue(address(asset), viewer_);
        IERC20[] memory assets = depositManager.getConfiguredAssets();
        IDepositManager.AssetConfiguration memory config = depositManager.getAssetConfiguration(
            assets[1]
        );
        MockERC20(address(assets[1])).mint(address(this), 1000);
        assets[1].approve(config.vault, 1000);
        IERC4626(config.vault).deposit(1000, address(depositManager));
        _assertCannotRescue(config.vault, viewer_);
    }

    // Scenarios: DM-RESCUE-I08.
    function test_givenStoredExternalShareSurplus_whenRescuing_reverts(
        address viewer_,
        bool enabled_
    ) public givenIsEnabled {
        MockERC7575Vault externalVault = _configureExternalVault();
        asset.mint(address(this), 1000);
        asset.approve(address(externalVault), 1000);
        externalVault.deposit(1000, address(depositManager));
        _pauseIfRequested(enabled_);
        assertEq(
            depositManager.getOperatorLiabilities(iAsset, DEPOSIT_OPERATOR),
            0,
            "external share surplus has no obligations"
        );
        _assertCannotRescue(externalVault.share(), viewer_);
    }

    // Scenarios: DM-RESCUE-I08.
    function test_givenManagedSurplusLifecycleSeeds_whenRescuing_reverts() public {
        uint256 snapshot = vm.snapshotState();
        test_givenManagedTokenSurplus_whenRescuing_reverts(address(0), false);
        assertTrue(
            vm.revertToState(snapshot),
            "restore underlying and vault surplus disabled seed"
        );
        test_givenManagedTokenSurplus_whenRescuing_reverts(DEPOSITOR, true);
        assertTrue(vm.revertToState(snapshot), "restore underlying and vault surplus enabled seed");
        test_givenStoredExternalShareSurplus_whenRescuing_reverts(EMERGENCY, false);
        assertTrue(vm.revertToState(snapshot), "restore stored share surplus disabled seed");
        test_givenStoredExternalShareSurplus_whenRescuing_reverts(CONFIG_OPERATOR, true);
    }

    // Scenarios: DM-RESCUE-N01.
    function test_givenZeroBalance_whenTransferWouldFail_isNoOp(
        address viewer_
    ) public givenIsEnabled {
        DepositManagerRescueToken token = new DepositManagerRescueToken(6);
        token.setTransferFails(true);
        vm.recordLogs();
        assertEq(_preview(viewer_, address(token)), 0, "zero balance quote");
        vm.prank(ADMIN);
        depositManager.rescue(address(token));
        assertEq(token.transferCalls(), 0, "zero rescue makes no transfer call");
        assertEq(vm.getRecordedLogs().length, 0, "zero preview and rescue emit no logs");
    }

    // Scenarios: DM-RESCUE-N01, DM-RESCUE-N02.
    function test_givenSixDecimals_whenRescuing_matchesRawBalance(
        uint256 amount_,
        address viewer_
    ) public givenIsEnabled givenProtectedPositions {
        _assertRawTokenRescue(6, amount_, viewer_);
    }

    // Scenarios: DM-RESCUE-N01, DM-RESCUE-N02.
    function test_givenNineDecimals_whenRescuing_matchesRawBalance(
        uint256 amount_,
        address viewer_
    ) public givenIsEnabled givenProtectedPositions {
        _assertRawTokenRescue(9, amount_, viewer_);
    }

    // Scenarios: DM-RESCUE-N01, DM-RESCUE-N02.
    function test_givenEighteenDecimals_whenRescuing_matchesRawBalance(
        uint256 amount_,
        address viewer_
    ) public givenIsEnabled givenProtectedPositions {
        _assertRawTokenRescue(18, amount_, viewer_);
    }

    // Scenarios: DM-RESCUE-N01, DM-RESCUE-N02.
    function test_givenTokenDecimalBoundarySeeds_whenRescuing_matchesRawBalance()
        public
        givenIsEnabled
        givenProtectedPositions
    {
        // Every token is newly deployed and Treasury starts with zero, including MAX256.
        _assertRawTokenRescue(6, 0, address(0));
        _assertRawTokenRescue(6, 1, DEPOSIT_MANAGER_ADMIN);
        _assertRawTokenRescue(6, type(uint256).max, EMERGENCY);
        _assertRawTokenRescue(9, 0, DEPOSIT_OPERATOR);
        _assertRawTokenRescue(9, 1, ADMIN);
        _assertRawTokenRescue(9, type(uint256).max, CONFIG_OPERATOR);
        _assertRawTokenRescue(18, 0, address(this));
        _assertRawTokenRescue(18, 1, DEPOSITOR);
        _assertRawTokenRescue(18, type(uint256).max, RECIPIENT);
        _assertRawTokenRescue(18, 123456789, DEPOSITOR);
    }

    function _assertRawTokenRescue(uint8 decimals_, uint256 amount_, address viewer_) private {
        DepositManagerRescueToken token = new DepositManagerRescueToken(decimals_);
        token.mint(address(depositManager), amount_);
        bytes32 protectedBefore = _protectedState();
        vm.recordLogs();
        assertEq(
            _preview(viewer_, address(token)),
            amount_,
            "quote equals independently funded raw balance"
        );
        assertEq(
            _preview(address(0), address(token)),
            amount_,
            "unrelated viewer gets same raw balance"
        );
        assertEq(token.transferCalls(), 0, "quote does not call transfer");
        assertEq(
            _protectedState(),
            protectedBefore,
            "quote preserves protected custody and accounting"
        );
        assertEq(vm.getRecordedLogs().length, 0, "quote emits no logs");
        if (amount_ > 0) {
            vm.expectEmit(address(depositManager));
            emit IDepositManager.TokenRescued(address(token), amount_);
        }
        vm.recordLogs();
        vm.prank(ADMIN);
        depositManager.rescue(address(token));
        assertEq(token.balanceOf(address(depositManager)), 0, "raw balance is fully swept");
        assertEq(
            token.balanceOf(address(trsry)),
            amount_,
            "Treasury receives raw units without scaling"
        );
        assertEq(
            token.transferCalls(),
            amount_ > 0 ? 1 : 0,
            "rescue transfers once only for positive balance"
        );
        assertEq(
            vm.getRecordedLogs().length,
            amount_ > 0 ? 2 : 0,
            "exact transfer and rescue log count"
        );
        assertEq(
            _protectedState(),
            protectedBefore,
            "raw rescue preserves protected custody and accounting"
        );
        assertEq(_preview(viewer_, address(token)), 0, "post-rescue quote is zero raw units");
    }

    // Scenarios: DM-RESCUE-P01.
    function test_givenAlreadyRescued_whenRescuingAgain_isNoOp(
        address viewer_,
        uint256 amount_
    ) public givenIsEnabled givenProtectedPositions {
        _fundAndRescue(ADMIN, viewer_, amount_);
        bytes32 beforeState = _rescueState();
        vm.recordLogs();
        vm.prank(ADMIN);
        depositManager.rescue(address(randomToken));
        assertEq(_rescueState(), beforeState, "second rescue changes nothing");
        assertEq(vm.getRecordedLogs().length, 0, "second rescue has no event");
    }

    // Scenarios: DM-RESCUE-P02.
    function test_givenTreasuryUpgraded_whenRescuing_usesCurrentModule(
        address viewer_,
        uint256 amount_
    ) public givenIsEnabled {
        OlympusTreasury newTreasury = new OlympusTreasury(kernel);
        vm.prank(ADMIN);
        kernel.executeAction(Actions.UpgradeModule, address(newTreasury));
        randomToken.mint(address(depositManager), amount_);
        assertEq(_preview(viewer_, address(randomToken)), amount_, "quote after Treasury upgrade");
        vm.prank(ADMIN);
        depositManager.rescue(address(randomToken));
        assertEq(randomToken.balanceOf(address(trsry)), 0, "old Treasury receives nothing");
        assertEq(
            randomToken.balanceOf(address(newTreasury)),
            amount_,
            "current Treasury receives full quoted balance"
        );
    }

    // Scenarios: DM-RESCUE-D01.
    function test_givenTreasuryMissing_whenPreviewAndRescue_revert(
        uint256 amount_,
        address viewer_
    ) public givenIsEnabled {
        randomToken.mint(address(depositManager), amount_);
        vm.mockCall(
            address(kernel),
            abi.encodeWithSignature("getModuleForKeycode(bytes5)", bytes5("TRSRY")),
            abi.encode(address(0))
        );
        bytes memory expected = abi.encodeWithSelector(
            Policy.Policy_ModuleDoesNotExist.selector,
            toKeycode("TRSRY")
        );
        vm.expectRevert(expected);
        _preview(viewer_, address(randomToken));
        vm.expectRevert(expected);
        vm.prank(ADMIN);
        depositManager.rescue(address(randomToken));
        assertEq(
            randomToken.balanceOf(address(depositManager)),
            amount_,
            "missing Treasury preserves stray balance"
        );
        assertEq(
            randomToken.balanceOf(address(trsry)),
            0,
            "missing module never falls back to cached Treasury"
        );
    }

    // Scenarios: DM-RESCUE-D01.
    function test_givenTreasuryMissing_whenBalanceAtBoundaries_reverts() public {
        uint256 snapshot = vm.snapshotState();
        test_givenTreasuryMissing_whenPreviewAndRescue_revert(0, address(0));
        assertTrue(vm.revertToState(snapshot), "restore missing Treasury zero seed");
        test_givenTreasuryMissing_whenPreviewAndRescue_revert(1, DEPOSIT_MANAGER_ADMIN);
    }

    // Scenarios: DM-RESCUE-T01.
    function test_givenBalanceReadFails_whenPreviewAndRescue_revert(
        address viewer_
    ) public givenIsEnabled givenProtectedPositions {
        DepositManagerRescueToken token = new DepositManagerRescueToken(9);
        token.mint(address(depositManager), 100);
        token.setBalanceReadFails(true);
        bytes32 beforeState = _protectedState();
        vm.expectRevert(DepositManagerRescueToken.RescueBalanceReadFailed.selector);
        _preview(viewer_, address(token));
        vm.expectRevert(DepositManagerRescueToken.RescueBalanceReadFailed.selector);
        vm.prank(ADMIN);
        depositManager.rescue(address(token));
        assertEq(_protectedState(), beforeState, "balance-read failure preserves protected state");
        token.setBalanceReadFails(false);
        assertEq(
            token.balanceOf(address(depositManager)),
            100,
            "balance-read failure preserves token custody"
        );
        assertEq(token.transferCalls(), 0, "failing balance read never transfers");
    }

    // Scenarios: DM-RESCUE-T02, DM-RESCUE-T03.
    function test_givenTransferFails_whenRestored_rescueRetriesOnce(
        address viewer_
    ) public givenIsEnabled givenProtectedPositions {
        DepositManagerRescueToken token = new DepositManagerRescueToken(18);
        token.mint(address(depositManager), 100);
        token.setTransferFails(true);
        bytes32 beforeState = _protectedState();
        assertEq(
            _preview(viewer_, address(token)),
            100,
            "quote does not attempt mandatory transfer"
        );
        vm.expectRevert(DepositManagerRescueToken.RescueTransferFailed.selector);
        vm.prank(ADMIN);
        depositManager.rescue(address(token));
        assertEq(
            token.balanceOf(address(depositManager)),
            100,
            "failed mandatory transfer restores custody"
        );
        assertEq(token.balanceOf(address(trsry)), 0, "failed transfer restores Treasury balance");
        assertEq(token.transferCalls(), 0, "token mutation before revert rolls back");
        assertEq(_protectedState(), beforeState, "failed transfer preserves all accounting");
        token.setTransferFails(false);
        assertEq(
            _preview(viewer_, address(token)),
            100,
            "retry quote remains full original entitlement"
        );
        vm.prank(ADMIN);
        depositManager.rescue(address(token));
        assertEq(token.balanceOf(address(trsry)), 100, "retry pays original amount once");
        assertEq(token.transferCalls(), 1, "only successful transfer remains recorded");
        assertEq(_protectedState(), beforeState, "retry preserves all accounting");
    }

    // Scenarios: DM-RESCUE-P04.
    function test_givenDonationAfterQuote_whenRescuing_usesFreshBalance() public givenIsEnabled {
        randomToken.mint(address(depositManager), 1);
        assertEq(_preview(DEPOSIT_MANAGER_ADMIN, address(randomToken)), 1, "first raw-unit quote");
        randomToken.mint(address(depositManager), 2);
        assertEq(
            _preview(address(0), address(randomToken)),
            3,
            "fresh quote includes intervening donation"
        );
        vm.prank(ADMIN);
        depositManager.rescue(address(randomToken));
        assertEq(randomToken.balanceOf(address(trsry)), 3, "rescue is not capped by stale quote");
    }

    function _pauseIfRequested(bool enabled_) private {
        if (!enabled_) {
            vm.prank(EMERGENCY);
            depositManager.disable("");
        }
    }

    function _configureController() private returns (DepositManagerConfigTimelock controller) {
        controller = new DepositManagerConfigTimelock(
            kernel,
            IDepositManager(address(depositManager))
        );
        vm.startPrank(ADMIN);
        kernel.executeAction(Actions.ActivatePolicy, address(controller));
        depositManager.setConfigOperator(address(controller));
        controller.enable("");
        vm.stopPrank();
    }

    function _configureExternalVault() private returns (MockERC7575Vault externalVault) {
        externalVault = new MockERC7575Vault(asset, true);
        vm.prank(ADMIN);
        depositManager.addAsset(iAsset, IERC4626(address(externalVault)), type(uint256).max, 0);
    }

    function _preview(address viewer_, address token_) internal returns (uint256) {
        vm.prank(viewer_);
        return IDepositManagerV1_1(address(depositManager)).previewRescue(token_);
    }

    function _fundAndRescue(address caller_, address viewer_, uint256 amount_) internal {
        randomToken.mint(address(depositManager), amount_);
        bytes32 beforeQuote = _rescueState();
        vm.recordLogs();
        assertEq(
            _preview(viewer_, address(randomToken)),
            amount_,
            "permissionless quote equals actual balance"
        );
        assertEq(_rescueState(), beforeQuote, "preview preserves state and allowances");
        assertEq(vm.getRecordedLogs().length, 0, "preview emits no logs");
        uint256 treasuryBefore = randomToken.balanceOf(address(trsry));
        bytes32 accountingBefore = _protectedState();
        if (amount_ > 0) {
            vm.expectEmit(address(depositManager));
            emit IDepositManager.TokenRescued(address(randomToken), amount_);
        }
        vm.recordLogs();
        vm.prank(caller_);
        depositManager.rescue(address(randomToken));
        assertEq(
            vm.getRecordedLogs().length,
            amount_ > 0 ? 2 : 0,
            "exactly one transfer and one rescue event for positive balance"
        );
        assertEq(randomToken.balanceOf(address(depositManager)), 0, "rescue sweeps live balance");
        assertEq(
            randomToken.balanceOf(address(trsry)) - treasuryBefore,
            amount_,
            "Treasury delta agrees with quote"
        );
        assertEq(
            _protectedState(),
            accountingBefore,
            "rescue preserves all managed routes and positions"
        );
        assertEq(_preview(viewer_, address(randomToken)), 0, "post-rescue quote is zero");
    }

    function _rescueState() internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    _protectedState(),
                    randomToken.balanceOf(address(depositManager)),
                    randomToken.balanceOf(address(trsry)),
                    randomToken.allowance(address(depositManager), address(trsry)),
                    asset.balanceOf(address(depositManager)),
                    vault.balanceOf(address(depositManager)),
                    depositManager.getOperatorLiabilities(iAsset, DEPOSIT_OPERATOR),
                    depositManager.getBorrowedAmount(iAsset, DEPOSIT_OPERATOR),
                    _assetDepositCapUtilization(iAsset)
                )
            );
    }

    modifier givenProtectedPositions() {
        _configureProtectedPositions();
        _;
    }

    function _grantAdmin(address caller_) internal {
        if (!roles.hasRole(caller_, "admin")) {
            vm.prank(ADMIN);
            rolesAdmin.grantRole("admin", caller_);
        }
    }

    function _configureProtectedPositions() internal {
        MockERC20 secondAsset = new MockERC20("Second managed asset", "M2", 18);
        MockERC4626 secondVault = new MockERC4626(
            ERC20(address(secondAsset)),
            "Second vault",
            "V2"
        );
        vm.startPrank(ADMIN);
        rolesAdmin.grantRole("deposit_operator", CONFIG_OPERATOR);
        depositManager.setOperatorName(DEPOSIT_OPERATOR, "one");
        depositManager.setOperatorName(CONFIG_OPERATOR, "two");
        depositManager.addAsset(iAsset, IERC4626(address(0)), type(uint256).max, 0);
        depositManager.addAsset(
            IERC20(address(secondAsset)),
            IERC4626(address(secondVault)),
            type(uint256).max,
            0
        );
        depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
        depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD, CONFIG_OPERATOR);
        depositManager.addAssetPeriod(
            IERC20(address(secondAsset)),
            DEPOSIT_PERIOD,
            DEPOSIT_OPERATOR
        );
        depositManager.addAssetPeriod(
            IERC20(address(secondAsset)),
            DEPOSIT_PERIOD,
            CONFIG_OPERATOR
        );
        vm.stopPrank();
        _depositProtectedPosition(asset, DEPOSIT_OPERATOR, 100);
        _depositProtectedPosition(asset, CONFIG_OPERATOR, 200);
        _depositProtectedPosition(secondAsset, DEPOSIT_OPERATOR, 300);
        _depositProtectedPosition(secondAsset, CONFIG_OPERATOR, 400);
    }

    function _depositProtectedPosition(
        MockERC20 token_,
        address operator_,
        uint256 amount_
    ) internal {
        token_.mint(DEPOSITOR, amount_);
        vm.prank(DEPOSITOR);
        token_.approve(address(depositManager), amount_);
        vm.prank(operator_);
        depositManager.deposit(
            IDepositManager.DepositParams({
                asset: IERC20(address(token_)),
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                amount: amount_,
                shouldWrap: false
            })
        );
    }

    function _protectedState() internal view returns (bytes32 state) {
        state = keccak256(
            abi.encode(
                depositManager.getAssetPeriods(),
                depositManager.getReceiptTokenIds(),
                depositManager.configOperator(),
                depositManager.isEnabled(),
                depositManager.lastTransitionAt()
            )
        );
        IERC20[] memory assets = depositManager.getConfiguredAssets();
        for (uint256 a; a < assets.length; ++a) {
            IDepositManager.AssetConfiguration memory config = depositManager.getAssetConfiguration(
                assets[a]
            );
            state = keccak256(
                abi.encode(
                    state,
                    config,
                    assets[a].balanceOf(address(depositManager)),
                    assets[a].allowance(address(depositManager), config.vault),
                    depositManager.getAssetDepositCapStatus(assets[a])
                )
            );
            if (config.vault != address(0)) {
                IERC20 share = depositManager.getAssetWithdrawalToken(assets[a], true);
                state = keccak256(
                    abi.encode(
                        state,
                        share.balanceOf(address(depositManager)),
                        assets[a].balanceOf(config.vault)
                    )
                );
            }
        }
        IDepositManager.AssetPeriod[] memory periods = depositManager.getAssetPeriods();
        for (uint256 i; i < periods.length; ++i) {
            IERC20 token = IERC20(periods[i].asset);
            (uint256 shares, uint256 assetsInShares) = depositManager.getOperatorAssets(
                token,
                periods[i].operator
            );
            uint256 id = depositManager.getReceiptTokenId(
                token,
                periods[i].depositPeriod,
                periods[i].operator
            );
            state = keccak256(
                abi.encode(
                    state,
                    shares,
                    assetsInShares,
                    depositManager.getOperatorLiabilities(token, periods[i].operator),
                    depositManager.getBorrowedAmount(token, periods[i].operator),
                    receiptTokenManager.balanceOf(DEPOSITOR, id),
                    receiptTokenManager.totalSupply(id)
                )
            );
        }
    }

    function _assertCannotRescue(address token_, address viewer_) internal {
        bytes32 beforeState = _protectedState();
        bytes memory expected = abi.encodeWithSelector(
            IDepositManager.DepositManager_CannotRescueAsset.selector,
            token_
        );
        vm.recordLogs();
        vm.expectRevert(expected);
        _preview(viewer_, token_);
        vm.expectRevert(expected);
        vm.prank(ADMIN);
        depositManager.rescue(token_);
        assertEq(_protectedState(), beforeState, "ineligible token preserves managed state");
        assertEq(vm.getRecordedLogs().length, 0, "ineligible calls emit no logs");
    }
}

// forge-lint: disable-end(literal-instead-of-constant, mixed-case-variable, unused-return)
