// SPDX-License-Identifier: MAGPL-3.0-only
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";
import {MockGohm} from "test/mocks/MockGohm.sol";

import {OlympusGovDelegation} from "modules/DLGTE/OlympusGovDelegation.sol";
import {DLGTEv1} from "modules/DLGTE/DLGTE.v1.sol";
import {Module, Kernel, Actions, Keycode} from "src/Kernel.sol";
import {SafeCast} from "libraries/SafeCast.sol";
import {DelegateEscrowFactory} from "src/external/cooler/DelegateEscrowFactory.sol";

contract DLGTETestBase is Test {
    using ModuleTestFixtureGenerator for OlympusGovDelegation;

    Kernel internal kernel;

    OlympusGovDelegation internal dlgte;
    MockGohm internal gohm;

    address public immutable ALICE = makeAddr("ALICE");
    address public immutable BOB = makeAddr("BOB");
    address public immutable CHARLIE = makeAddr("CHARLIE");
    address public immutable DANIEL = makeAddr("DANIEL");

    address public policy;
    address public policy2;

    DelegateEscrowFactory escrowFactory;

    event DelegateEscrowCreated(
        address indexed caller,
        address indexed delegate,
        address indexed escrow
    );

    event Delegate(
        address indexed escrow,
        address indexed caller,
        address indexed onBehalfOf,
        int256 delegationAmountDelta
    );

    event DelegationApplied(address indexed account, address indexed delegate, int256 amount);

    function setUp() public {
        vm.warp(1_000_000);

        // Deploy Kernel and modules
        kernel = new Kernel();
        gohm = new MockGohm("gOHM", "gOHM", 18);
        escrowFactory = new DelegateEscrowFactory(address(gohm));
        dlgte = new OlympusGovDelegation(kernel, address(gohm), escrowFactory);

        // Generate fixtures
        policy = dlgte.generateGodmodeFixture(type(OlympusGovDelegation).name);
        policy2 = dlgte.generateGodmodeFixture(type(OlympusGovDelegation).name);

        // Install modules and policies on Kernel
        kernel.executeAction(Actions.InstallModule, address(dlgte));
        kernel.executeAction(Actions.ActivatePolicy, policy);
        kernel.executeAction(Actions.ActivatePolicy, policy2);
    }

    function setupUndelegated(address forPolicy, address account, uint256 amount) internal {
        vm.startPrank(forPolicy);
        deal(address(gohm), address(forPolicy), amount);
        gohm.approve(address(dlgte), amount);
        dlgte.depositUndelegatedGohm(account, amount);
    }

    function verifyAccountSummary(
        address forPolicy,
        address account,
        uint256 expectedTotalGOhm,
        uint256 expectedDelegatedGOhm,
        uint256 expectedNumDelegateAddresses,
        uint256 expectedMaxAllowedDelegateAddresses,
        uint256 expectedPolicyAcctBalance
    ) internal view {
        (
            uint256 totalGOhm,
            uint256 delegatedGOhm,
            uint256 numDelegateAddresses,
            uint256 maxAllowedDelegateAddresses
        ) = dlgte.accountDelegationSummary(account);
        assertEq(totalGOhm, expectedTotalGOhm, "expectedTotalGOhm");
        assertEq(delegatedGOhm, expectedDelegatedGOhm, "expectedDelegatedGOhm");
        assertEq(
            numDelegateAddresses,
            expectedNumDelegateAddresses,
            "expectedNumDelegateAddresses"
        );
        assertEq(
            maxAllowedDelegateAddresses,
            expectedMaxAllowedDelegateAddresses,
            "expectedMaxAllowedDelegateAddresses"
        );

        assertEq(
            dlgte.policyAccountBalances(forPolicy, account),
            expectedPolicyAcctBalance,
            "policyAccountBalances"
        );
    }

    function verifyDelegationsZero(address account) internal view {
        DLGTEv1.AccountDelegation[] memory delegations = dlgte.accountDelegationsList(
            account,
            0,
            10
        );
        assertEq(delegations.length, 0);
    }

    function verifyDelegationsOne(
        address account,
        address expectedDelegate,
        address expectedEscrow,
        uint256 expectedTotalAmount
    ) internal view {
        DLGTEv1.AccountDelegation[] memory delegations = dlgte.accountDelegationsList(
            account,
            0,
            10
        );
        assertEq(delegations.length, 1);
        assertEq(delegations[0].delegate, expectedDelegate, "delegate");
        assertEq(delegations[0].escrow, expectedEscrow, "escrow");
        assertEq(delegations[0].totalAmount, expectedTotalAmount, "totalAmount");
    }

    function verifyDelegationsTwo(
        address account,
        address expectedDelegate1,
        address expectedEscrow1,
        uint256 expectedTotalAmount1,
        address expectedDelegate2,
        address expectedEscrow2,
        uint256 expectedTotalAmount2
    ) internal view {
        DLGTEv1.AccountDelegation[] memory delegations = dlgte.accountDelegationsList(
            account,
            0,
            10
        );
        assertEq(delegations.length, 2);
        assertEq(delegations[0].delegate, expectedDelegate1, "delegate1");
        assertEq(delegations[0].escrow, expectedEscrow1, "escrow1");
        assertEq(delegations[0].totalAmount, expectedTotalAmount1, "totalAmount1");
        assertEq(delegations[1].delegate, expectedDelegate2, "delegate2");
        assertEq(delegations[1].escrow, expectedEscrow2, "escrow2");
        assertEq(delegations[1].totalAmount, expectedTotalAmount2, "totalAmount2");
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
        delegationRequests[1] = DLGTEv1.DelegationRequest({delegate: to, amount: int256(amount)});
    }

    function verifyApplyDelegations(
        address onBehalfOf,
        DLGTEv1.DelegationRequest[] memory delegationRequests,
        uint256 expectedTotalDelegated,
        uint256 expectedTotalUndelegated,
        uint256 expectedUndelegatedBalance
    ) internal {
        (uint256 totalDelegated, uint256 totalUndelegated, uint256 undelegatedBalance) = dlgte.applyDelegations(
            onBehalfOf,
            delegationRequests
        );
        assertEq(totalDelegated, expectedTotalDelegated, "applyDelegations::totalDelegated");
        assertEq(totalUndelegated, expectedTotalUndelegated, "applyDelegations::totalUndelegated");
        assertEq(undelegatedBalance, expectedUndelegatedBalance, "applyDelegations::undelegatedBalance");
    }

    function seedDelegate() internal {
        vm.startPrank(policy);
        deal(address(gohm), address(policy), 100e18);
        gohm.approve(address(dlgte), 100e18);
        dlgte.depositUndelegatedGohm(ALICE, 100e18);
        verifyApplyDelegations(ALICE, delegationRequest(BOB, 100e18), 100e18, 0, 0);
    }
}

contract DLGTETestAdmin is DLGTETestBase {
    event MaxDelegateAddressesSet(address indexed account, uint256 maxDelegateAddresses);

    function test_constructor() public view {
        assertEq(address(dlgte.kernel()), address(kernel));
        assertEq(address(dlgte.gOHM()), address(gohm));
        assertEq(dlgte.DEFAULT_MAX_DELEGATE_ADDRESSES(), 10);
        assertEq(Keycode.unwrap(dlgte.KEYCODE()), bytes5(0x444c475445));
        (uint8 major, uint8 minor) = dlgte.VERSION();
        assertEq(major, 1);
        assertEq(minor, 0);
    }

    function test_maxDelegateAddresses_default() public view {
        assertEq(dlgte.maxDelegateAddresses(ALICE), 10);
    }

    function test_setMaxDelegateAddresses_zero() public {
        vm.startPrank(policy);
        vm.expectEmit(address(dlgte));
        emit MaxDelegateAddressesSet(ALICE, 0);
        dlgte.setMaxDelegateAddresses(ALICE, 0);
        assertEq(dlgte.maxDelegateAddresses(ALICE), 10);
    }

    function test_setMaxDelegateAddresses_many() public {
        vm.startPrank(policy);
        vm.expectEmit(address(dlgte));
        emit MaxDelegateAddressesSet(ALICE, 999);
        dlgte.setMaxDelegateAddresses(ALICE, 999);
        assertEq(dlgte.maxDelegateAddresses(ALICE), 999);
    }
}

contract DLGTETestAccess is DLGTETestBase {
    function test_setMaxDelegateAddresses_access() public {
        vm.startPrank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, ALICE));
        dlgte.setMaxDelegateAddresses(ALICE, 123);
    }

    function test_depositUndelegatedGohm_access() public {
        vm.startPrank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, ALICE));
        dlgte.depositUndelegatedGohm(ALICE, 0);
    }

    function test_withdrawUndelegatedGohm_access() public {
        vm.startPrank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, ALICE));
        dlgte.withdrawUndelegatedGohm(ALICE, 0);
    }

    function test_applyDelegations_access() public {
        vm.startPrank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, ALICE));
        dlgte.applyDelegations(policy, new DLGTEv1.DelegationRequest[](0));
    }
}

contract DLGTETestDeposit is DLGTETestBase {
    using ModuleTestFixtureGenerator for OlympusGovDelegation;

    function test_depositUndelegatedGohm_fail_invalidOnBehalfOf() public {
        vm.startPrank(policy);
        vm.expectRevert(abi.encodeWithSelector(DLGTEv1.DLGTE_InvalidAddress.selector));
        dlgte.depositUndelegatedGohm(address(0), 123);
    }

    function test_depositUndelegatedGohm_fail_invalidAmount() public {
        vm.startPrank(policy);
        vm.expectRevert(abi.encodeWithSelector(DLGTEv1.DLGTE_InvalidAmount.selector));
        dlgte.depositUndelegatedGohm(ALICE, 0);
    }

    function test_depositUndelegatedGohm_fail_notEnough() public {
        vm.startPrank(policy);
        deal(address(gohm), address(policy), 75e18);
        gohm.approve(address(dlgte), 75e18);
        vm.expectRevert("TRANSFER_FROM_FAILED");
        dlgte.depositUndelegatedGohm(
            ALICE,
            100e18 // more than what's approved
        );
    }

    function test_depositUndelegatedGohm_fail_tooBig() public {
        vm.startPrank(policy);
        uint256 amount = uint256(type(uint112).max) + 1;
        deal(address(gohm), address(policy), amount);
        gohm.approve(address(dlgte), amount);
        vm.expectRevert(abi.encodeWithSelector(SafeCast.Overflow.selector, amount));
        dlgte.depositUndelegatedGohm(ALICE, amount);
    }

    function test_depositUndelegatedGohm_success_onePolicy() public {
        vm.startPrank(policy);
        uint256 amount = 100e18;
        deal(address(gohm), address(policy), amount);
        gohm.approve(address(dlgte), amount);

        dlgte.depositUndelegatedGohm(ALICE, amount);
        verifyAccountSummary(address(policy), ALICE, amount, 0, 0, 10, amount);
    }

    function test_depositUndelegatedGohm_success_multiPolicy() public {
        setupUndelegated(policy, ALICE, 100e18);
        setupUndelegated(policy2, ALICE, 100e18);

        verifyAccountSummary(address(policy), ALICE, 200e18, 0, 0, 10, 100e18);
        verifyAccountSummary(address(policy2), ALICE, 200e18, 0, 0, 10, 100e18);
    }
}

contract DLGTETestWithdraw is DLGTETestBase {
    using ModuleTestFixtureGenerator for OlympusGovDelegation;

    function test_withdrawUndelegatedGohm_fail_invalidOnBehalfOf() public {
        vm.startPrank(policy);
        vm.expectRevert(abi.encodeWithSelector(DLGTEv1.DLGTE_InvalidAddress.selector));
        dlgte.withdrawUndelegatedGohm(address(0), 123);
    }

    function test_withdrawUndelegatedGohm_fail_invalidAmount() public {
        vm.startPrank(policy);
        vm.expectRevert(abi.encodeWithSelector(DLGTEv1.DLGTE_InvalidAmount.selector));
        dlgte.withdrawUndelegatedGohm(ALICE, 0);
    }

    function test_withdrawUndelegatedGohm_fail_notEnoughForPolicy() public {
        setupUndelegated(policy, ALICE, 100e18);

        vm.startPrank(policy2);
        vm.expectRevert(
            abi.encodeWithSelector(DLGTEv1.DLGTE_ExceededPolicyAccountBalance.selector, 0, 123)
        );
        dlgte.withdrawUndelegatedGohm(ALICE, 123);
    }

    function test_withdrawUndelegatedGohm_fail_notEnoughUndelegated() public {
        setupUndelegated(policy, ALICE, 100e18);

        dlgte.applyDelegations(ALICE, delegationRequest(ALICE, 25e18));
        vm.expectRevert(
            abi.encodeWithSelector(DLGTEv1.DLGTE_ExceededUndelegatedBalance.selector, 75e18, 100e18)
        );
        dlgte.withdrawUndelegatedGohm(ALICE, 100e18);
    }

    function test_withdrawUndelegatedGohm_success_fullWithdrawal() public {
        setupUndelegated(policy, ALICE, 100e18);
        dlgte.applyDelegations(ALICE, delegationRequest(ALICE, 25e18));

        dlgte.withdrawUndelegatedGohm(ALICE, 75e18);
        verifyAccountSummary(address(policy), ALICE, 25e18, 25e18, 1, 10, 25e18);
        assertEq(gohm.balanceOf(policy), 75e18);
        assertEq(gohm.balanceOf(ALICE), 0);
        assertEq(gohm.balanceOf(address(dlgte)), 0);

        address expectedAliceEscrow = 0xCB6f5076b5bbae81D7643BfBf57897E8E3FB1db9;
        assertEq(gohm.balanceOf(expectedAliceEscrow), 25e18);
    }

    function test_withdrawUndelegatedGohm_success_partialWithdrawal() public {
        setupUndelegated(policy, ALICE, 100e18);
        dlgte.applyDelegations(ALICE, delegationRequest(ALICE, 25e18));

        dlgte.withdrawUndelegatedGohm(ALICE, 25e18);
        verifyAccountSummary(address(policy), ALICE, 75e18, 25e18, 1, 10, 75e18);
        assertEq(gohm.balanceOf(policy), 25e18);
        assertEq(gohm.balanceOf(ALICE), 0);
        assertEq(gohm.balanceOf(address(dlgte)), 50e18);

        address expectedAliceEscrow = 0xCB6f5076b5bbae81D7643BfBf57897E8E3FB1db9;
        assertEq(gohm.balanceOf(expectedAliceEscrow), 25e18);
    }

    function test_withdrawUndelegatedGohm_success_multiPolicy() public {
        setupUndelegated(policy, ALICE, 100e18);
        setupUndelegated(policy2, ALICE, 100e18);

        vm.startPrank(policy);
        dlgte.withdrawUndelegatedGohm(ALICE, 25e18);
        vm.startPrank(policy2);
        dlgte.withdrawUndelegatedGohm(ALICE, 65e18);

        verifyAccountSummary(address(policy), ALICE, 200e18 - 90e18, 0, 0, 10, 75e18);
        verifyAccountSummary(address(policy2), ALICE, 200e18 - 90e18, 0, 0, 10, 35e18);

        assertEq(gohm.balanceOf(policy), 25e18);
        assertEq(gohm.balanceOf(policy2), 65e18);
        assertEq(gohm.balanceOf(ALICE), 0);
        assertEq(gohm.balanceOf(address(dlgte)), 110e18);
    }
}

contract DLGTETestApplyDelegationsOne is DLGTETestBase {
    function test_applyDelegations_fail_invalidOnBehalfOf() public {
        vm.startPrank(policy);
        vm.expectRevert(abi.encodeWithSelector(DLGTEv1.DLGTE_InvalidAddress.selector));
        dlgte.applyDelegations(address(0), new DLGTEv1.DelegationRequest[](0));
    }

    function test_applyDelegations_fail_invalidLength() public {
        vm.startPrank(policy);
        vm.expectRevert(abi.encodeWithSelector(DLGTEv1.DLGTE_InvalidDelegationRequests.selector));
        dlgte.applyDelegations(ALICE, new DLGTEv1.DelegationRequest[](0));
    }

    function test_applyDelegations_success_oneDelegate() public {
        setupUndelegated(policy, ALICE, 100e18);

        address expectedEscrow = 0xCB6f5076b5bbae81D7643BfBf57897E8E3FB1db9;
        vm.expectEmit(address(escrowFactory));
        emit DelegateEscrowCreated(address(dlgte), BOB, expectedEscrow);
        vm.expectEmit(address(escrowFactory));
        emit Delegate(expectedEscrow, address(dlgte), ALICE, 100e18);
        vm.expectEmit(address(dlgte));
        emit DelegationApplied(ALICE, BOB, 100e18);
        verifyApplyDelegations(ALICE, delegationRequest(BOB, 100e18), 100e18, 0, 0);
        assertEq(gohm.balanceOf(address(dlgte)), 0);
        assertEq(gohm.balanceOf(expectedEscrow), 100e18);
        verifyAccountSummary(address(policy), ALICE, 100e18, 100e18, 1, 10, 100e18);
        verifyDelegationsOne(ALICE, BOB, expectedEscrow, 100e18);
    }

    function test_applyDelegations_success_selfDelegate() public {
        setupUndelegated(policy, ALICE, 100e18);

        address expectedEscrow = 0xCB6f5076b5bbae81D7643BfBf57897E8E3FB1db9;
        vm.expectEmit(address(escrowFactory));
        emit DelegateEscrowCreated(address(dlgte), ALICE, expectedEscrow);
        vm.expectEmit(address(dlgte));
        emit DelegationApplied(ALICE, ALICE, 100e18);
        verifyApplyDelegations(ALICE, delegationRequest(ALICE, 100e18), 100e18, 0, 0);
        assertEq(gohm.balanceOf(address(dlgte)), 0);
        assertEq(gohm.balanceOf(expectedEscrow), 100e18);
        verifyAccountSummary(address(policy), ALICE, 100e18, 100e18, 1, 10, 100e18);
        verifyDelegationsOne(ALICE, ALICE, expectedEscrow, 100e18);
    }

    function test_applyDelegations_success_maxDelegate() public {
        setupUndelegated(policy, ALICE, 100e18);

        address expectedEscrow = 0xCB6f5076b5bbae81D7643BfBf57897E8E3FB1db9;
        vm.expectEmit(address(escrowFactory));
        emit DelegateEscrowCreated(address(dlgte), ALICE, expectedEscrow);
        vm.expectEmit(address(dlgte));
        emit DelegationApplied(ALICE, ALICE, 100e18);
        verifyApplyDelegations(
            ALICE,
            delegationRequest(ALICE, uint256(type(int256).max)),
            100e18,
            0,
            0
        );
        assertEq(gohm.balanceOf(address(dlgte)), 0);
        assertEq(gohm.balanceOf(expectedEscrow), 100e18);
        verifyAccountSummary(address(policy), ALICE, 100e18, 100e18, 1, 10, 100e18);
        verifyDelegationsOne(ALICE, ALICE, expectedEscrow, 100e18);
    }

    function test_applyDelegations_success_existingDelegate() public {
        setupUndelegated(policy, ALICE, 100e18);

        address expectedEscrow = 0xCB6f5076b5bbae81D7643BfBf57897E8E3FB1db9;
        verifyApplyDelegations(ALICE, delegationRequest(ALICE, 50e18), 50e18, 0, 50e18);
        assertEq(gohm.balanceOf(address(dlgte)), 50e18);
        assertEq(gohm.balanceOf(expectedEscrow), 50e18);
        verifyAccountSummary(address(policy), ALICE, 100e18, 50e18, 1, 10, 100e18);
        verifyDelegationsOne(ALICE, ALICE, expectedEscrow, 50e18);

        verifyApplyDelegations(ALICE, delegationRequest(ALICE, 25e18), 25e18, 0, 25e18);
        assertEq(gohm.balanceOf(address(dlgte)), 25e18);
        assertEq(gohm.balanceOf(expectedEscrow), 75e18);
        verifyAccountSummary(address(policy), ALICE, 100e18, 75e18, 1, 10, 100e18);
        verifyDelegationsOne(ALICE, ALICE, expectedEscrow, 75e18);
    }

    function test_applyDelegations_fail_delegateTooMuch() public {
        setupUndelegated(policy, ALICE, 100e18);

        vm.expectRevert(
            abi.encodeWithSelector(
                DLGTEv1.DLGTE_ExceededUndelegatedBalance.selector,
                100e18,
                100e18 + 1
            )
        );
        dlgte.applyDelegations(ALICE, delegationRequest(BOB, 100e18 + 1));
    }

    function test_applyDelegations_fail_badAddresses() public {
        setupUndelegated(policy, ALICE, 100e18);

        vm.expectRevert(abi.encodeWithSelector(DLGTEv1.DLGTE_InvalidAddress.selector));
        dlgte.applyDelegations(ALICE, delegationRequest(address(0), 100e18));

        vm.expectRevert(abi.encodeWithSelector(DLGTEv1.DLGTE_InvalidDelegateEscrow.selector));
        dlgte.applyDelegations(ALICE, transferDelegationRequest(ALICE, ALICE, 100e18));
    }

    function test_applyDelegations_fail_badAmount() public {
        vm.startPrank(policy);
        vm.expectRevert(abi.encodeWithSelector(DLGTEv1.DLGTE_InvalidAmount.selector));
        dlgte.applyDelegations(ALICE, delegationRequest(ALICE, 0));

        setupUndelegated(policy, ALICE, 100e18);

        vm.expectRevert(abi.encodeWithSelector(DLGTEv1.DLGTE_InvalidAmount.selector));
        dlgte.applyDelegations(ALICE, delegationRequest(ALICE, 0));
    }
}

contract DLGTETestDelegationsFromOneDelegate is DLGTETestBase {
    function test_applyDelegations_fail_invalidEscrow() public {
        seedDelegate();

        vm.expectRevert(abi.encodeWithSelector(DLGTEv1.DLGTE_InvalidDelegateEscrow.selector));
        dlgte.applyDelegations(ALICE, unDelegationRequest(ALICE, 100e18));
    }

    function test_applyDelegations_success_partialWithdraw() public {
        seedDelegate();

        address expectedEscrow = 0xCB6f5076b5bbae81D7643BfBf57897E8E3FB1db9;
        vm.expectEmit(address(escrowFactory));
        emit Delegate(expectedEscrow, address(dlgte), ALICE, -25e18);
        vm.expectEmit(address(dlgte));
        emit DelegationApplied(ALICE, BOB, -25e18);
        verifyApplyDelegations(ALICE, unDelegationRequest(BOB, 25e18), 0, 25e18, 25e18);
        assertEq(gohm.balanceOf(address(dlgte)), 25e18);
        assertEq(gohm.balanceOf(address(policy)), 0);
        assertEq(gohm.balanceOf(expectedEscrow), 75e18);
        verifyAccountSummary(address(policy), ALICE, 100e18, 75e18, 1, 10, 100e18);
        verifyDelegationsOne(ALICE, BOB, expectedEscrow, 75e18);
    }

    function test_applyDelegations_success_fullyWithdraw() public {
        seedDelegate();

        address expectedEscrow = 0xCB6f5076b5bbae81D7643BfBf57897E8E3FB1db9;
        vm.expectEmit(address(escrowFactory));
        emit Delegate(expectedEscrow, address(dlgte), ALICE, -100e18);
        vm.expectEmit(address(dlgte));
        emit DelegationApplied(ALICE, BOB, -100e18);
        verifyApplyDelegations(ALICE, unDelegationRequest(BOB, 100e18), 0, 100e18, 100e18);
        assertEq(gohm.balanceOf(address(dlgte)), 100e18);
        assertEq(gohm.balanceOf(address(policy)), 0);
        assertEq(gohm.balanceOf(expectedEscrow), 0);
        verifyAccountSummary(address(policy), ALICE, 100e18, 0, 0, 10, 100e18);
        verifyDelegationsZero(ALICE);
    }
}

contract DLGTETestDelegationsTransferDelegate is DLGTETestBase {
    function test_applyDelegations_success_fullyTransfer() public {
        seedDelegate();

        address expectedBobEscrow = 0xCB6f5076b5bbae81D7643BfBf57897E8E3FB1db9;
        address expectedCharlieEscrow = 0xA11d35fE4b9Ca9979F2FF84283a9Ce190F60Cd00;
        vm.expectEmit(address(dlgte));
        emit DelegationApplied(ALICE, BOB, -100e18);
        vm.expectEmit(address(escrowFactory));
        emit DelegateEscrowCreated(address(dlgte), CHARLIE, expectedCharlieEscrow);
        vm.expectEmit(address(dlgte));
        emit DelegationApplied(ALICE, CHARLIE, 100e18);
        verifyApplyDelegations(
            ALICE,
            transferDelegationRequest(BOB, CHARLIE, 100e18),
            100e18,
            100e18,
            0
        );
        assertEq(gohm.balanceOf(address(dlgte)), 0);
        assertEq(gohm.balanceOf(address(policy)), 0);
        assertEq(gohm.balanceOf(expectedBobEscrow), 0);
        assertEq(gohm.balanceOf(expectedCharlieEscrow), 100e18);
        verifyAccountSummary(address(policy), ALICE, 100e18, 100e18, 1, 10, 100e18);
        verifyDelegationsOne(ALICE, CHARLIE, expectedCharlieEscrow, 100e18);
    }

    function test_applyDelegations_success_partialTransfer() public {
        seedDelegate();

        address expectedBobEscrow = 0xCB6f5076b5bbae81D7643BfBf57897E8E3FB1db9;
        address expectedCharlieEscrow = 0xA11d35fE4b9Ca9979F2FF84283a9Ce190F60Cd00;
        vm.expectEmit(address(dlgte));
        emit DelegationApplied(ALICE, BOB, -25e18);
        vm.expectEmit(address(escrowFactory));
        emit DelegateEscrowCreated(address(dlgte), CHARLIE, expectedCharlieEscrow);
        vm.expectEmit(address(dlgte));
        emit DelegationApplied(ALICE, CHARLIE, 25e18);
        verifyApplyDelegations(ALICE, transferDelegationRequest(BOB, CHARLIE, 25e18), 25e18, 25e18, 0);
        assertEq(gohm.balanceOf(address(dlgte)), 0);
        assertEq(gohm.balanceOf(address(policy)), 0);
        assertEq(gohm.balanceOf(expectedBobEscrow), 75e18);
        assertEq(gohm.balanceOf(expectedCharlieEscrow), 25e18);
        verifyAccountSummary(address(policy), ALICE, 100e18, 100e18, 2, 10, 100e18);
        verifyDelegationsTwo(
            ALICE,
            BOB,
            expectedBobEscrow,
            75e18,
            CHARLIE,
            expectedCharlieEscrow,
            25e18
        );
    }
}

contract DLGTETestDelegationsMultipleDelegates is DLGTETestBase {
    using ModuleTestFixtureGenerator for OlympusGovDelegation;

    function test_fail_tooManyDelegates() public {
        vm.startPrank(policy);
        dlgte.setMaxDelegateAddresses(ALICE, 2);

        setupUndelegated(policy, ALICE, 100e18);
        verifyApplyDelegations(ALICE, delegationRequest(BOB, 50e18), 50e18, 0, 50e18);
        verifyApplyDelegations(ALICE, delegationRequest(CHARLIE, 25e18), 25e18, 0, 25e18);

        address expectedBobEscrow = 0xCB6f5076b5bbae81D7643BfBf57897E8E3FB1db9;
        address expectedCharlieEscrow = 0xA11d35fE4b9Ca9979F2FF84283a9Ce190F60Cd00;
        verifyAccountSummary(address(policy), ALICE, 100e18, 75e18, 2, 2, 100e18);
        verifyDelegationsTwo(
            ALICE,
            BOB,
            expectedBobEscrow,
            50e18,
            CHARLIE,
            expectedCharlieEscrow,
            25e18
        );

        vm.expectRevert(abi.encodeWithSelector(DLGTEv1.DLGTE_TooManyDelegates.selector));
        dlgte.applyDelegations(ALICE, delegationRequest(DANIEL, 10e18));
    }

    function test_multipleUsers_multiplePolicies() public {
        // Add for policy 1
        {
            setupUndelegated(policy, ALICE, 25e18);
            dlgte.applyDelegations(ALICE, delegationRequest(BOB, 25e18));
            setupUndelegated(policy, BOB, 33e18);
            dlgte.applyDelegations(BOB, delegationRequest(ALICE, 10e18));
        }

        // Add again for policy 2
        {
            setupUndelegated(policy2, ALICE, 25e18);
            dlgte.applyDelegations(ALICE, delegationRequest(BOB, 25e18));
            setupUndelegated(policy2, BOB, 33e18);
            dlgte.applyDelegations(BOB, delegationRequest(ALICE, 10e18));
        }

        // Same escrow used for both
        address expectedBobEscrow = 0xCB6f5076b5bbae81D7643BfBf57897E8E3FB1db9;
        address expectedAliceEscrow = 0xA11d35fE4b9Ca9979F2FF84283a9Ce190F60Cd00;
        verifyAccountSummary(address(policy), ALICE, 50e18, 50e18, 1, 10, 25e18);
        verifyAccountSummary(address(policy2), ALICE, 50e18, 50e18, 1, 10, 25e18);
        verifyAccountSummary(address(policy), BOB, 66e18, 20e18, 1, 10, 33e18);
        verifyAccountSummary(address(policy2), BOB, 66e18, 20e18, 1, 10, 33e18);

        verifyDelegationsOne(ALICE, BOB, expectedBobEscrow, 25e18 * 2);
        verifyDelegationsOne(BOB, ALICE, expectedAliceEscrow, 10e18 * 2);

        assertEq(gohm.balanceOf(address(dlgte)), 46e18);
        assertEq(gohm.balanceOf(address(policy)), 0);
        assertEq(gohm.balanceOf(address(policy2)), 0);
        assertEq(gohm.balanceOf(expectedBobEscrow), 50e18);
        assertEq(gohm.balanceOf(expectedAliceEscrow), 20e18);
    }
}
