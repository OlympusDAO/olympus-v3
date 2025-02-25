// SPDX-License-Identifier: MAGPL-3.0-only
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";
import {MockGohm} from "test/mocks/MockGohm.sol";

import {OlympusGovDelegation} from "modules/DLGTE/OlympusGovDelegation.sol";
import {IDLGTEv1} from "modules/DLGTE/IDLGTE.v1.sol";
import {Module, Kernel, Actions, Keycode} from "src/Kernel.sol";
import {SafeCast} from "libraries/SafeCast.sol";
import {DelegateEscrowFactory} from "src/external/cooler/DelegateEscrowFactory.sol";
import {DelegateEscrow} from "src/external/cooler/DelegateEscrow.sol";

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
        IDLGTEv1.AccountDelegation[] memory delegations = dlgte.accountDelegationsList(
            account,
            0,
            10
        );
        assertEq(delegations.length, 0);
    }

    function verifyDelegationsOne(
        address account,
        address expectedDelegate,
        uint256 expectedAmount,
        address expectedEscrow
    ) internal view {
        IDLGTEv1.AccountDelegation[] memory delegations = dlgte.accountDelegationsList(
            account,
            0,
            10
        );
        assertEq(delegations.length, 1);
        assertEq(delegations[0].delegate, expectedDelegate, "delegate");
        assertEq(delegations[0].amount, expectedAmount, "amount");
        assertEq(delegations[0].escrow, expectedEscrow, "escrow");
    }

    function verifyDelegationsTwo(
        address account,
        address expectedDelegate1,
        uint256 expectedAmount1,
        address expectedEscrow1,
        address expectedDelegate2,
        uint256 expectedAmount2,
        address expectedEscrow2
    ) internal view {
        IDLGTEv1.AccountDelegation[] memory delegations = dlgte.accountDelegationsList(
            account,
            0,
            10
        );
        assertEq(delegations.length, 2);
        assertEq(delegations[0].delegate, expectedDelegate1, "delegate1");
        assertEq(delegations[0].escrow, expectedEscrow1, "escrow1");
        assertEq(delegations[0].amount, expectedAmount1, "amount1");
        assertEq(delegations[1].delegate, expectedDelegate2, "delegate2");
        assertEq(delegations[1].escrow, expectedEscrow2, "escrow2");
        assertEq(delegations[1].amount, expectedAmount2, "amount2");
    }

    function delegationRequest(
        address to,
        uint256 amount
    ) internal pure returns (IDLGTEv1.DelegationRequest[] memory delegationRequests) {
        delegationRequests = new IDLGTEv1.DelegationRequest[](1);
        delegationRequests[0] = IDLGTEv1.DelegationRequest({delegate: to, amount: int256(amount)});
    }

    function unDelegationRequest(
        address from,
        uint256 amount
    ) internal pure returns (IDLGTEv1.DelegationRequest[] memory delegationRequests) {
        delegationRequests = new IDLGTEv1.DelegationRequest[](1);
        delegationRequests[0] = IDLGTEv1.DelegationRequest({
            delegate: from,
            amount: int256(amount) * -1
        });
    }

    function transferDelegationRequest(
        address from,
        address to,
        uint256 amount
    ) internal pure returns (IDLGTEv1.DelegationRequest[] memory delegationRequests) {
        delegationRequests = new IDLGTEv1.DelegationRequest[](2);
        delegationRequests[0] = IDLGTEv1.DelegationRequest({
            delegate: from,
            amount: int256(amount) * -1
        });
        delegationRequests[1] = IDLGTEv1.DelegationRequest({delegate: to, amount: int256(amount)});
    }

    function verifyApplyDelegations(
        address onBehalfOf,
        IDLGTEv1.DelegationRequest[] memory delegationRequests,
        uint256 expectedTotalDelegated,
        uint256 expectedTotalUndelegated,
        uint256 expectedUndelegatedBalance
    ) internal {
        (uint256 totalDelegated, uint256 totalUndelegated, uint256 undelegatedBalance) = dlgte
            .applyDelegations(onBehalfOf, delegationRequests);
        assertEq(totalDelegated, expectedTotalDelegated, "applyDelegations::totalDelegated");
        assertEq(totalUndelegated, expectedTotalUndelegated, "applyDelegations::totalUndelegated");
        assertEq(
            undelegatedBalance,
            expectedUndelegatedBalance,
            "applyDelegations::undelegatedBalance"
        );
    }

    function seedDelegate() internal {
        seedDelegate(policy, ALICE, BOB, 100e18);
    }

    function seedDelegate(address caller, address onBehalfOf, address delegate, uint256 amount) internal {
        vm.startPrank(caller);
        deal(address(gohm), caller, 100e18);
        gohm.approve(address(dlgte), 100e18);
        dlgte.depositUndelegatedGohm(onBehalfOf, amount);
        verifyApplyDelegations(onBehalfOf, delegationRequest(delegate, amount), amount, 0, 0);
    }

    function applyManyDelegations(uint256 totalCollateral, uint32 numDelegates) internal {
        vm.startPrank(policy);
        deal(address(gohm), address(policy), totalCollateral);
        gohm.approve(address(dlgte), totalCollateral);
        dlgte.depositUndelegatedGohm(ALICE, totalCollateral);

        address delegate;
        dlgte.setMaxDelegateAddresses(ALICE, numDelegates);

        for (uint256 i; i < numDelegates; ++i) {
            delegate = makeAddr(vm.toString(i));
            dlgte.applyDelegations(ALICE, delegationRequest(delegate, 1e18 + i));
        }

        // Mock some other policy delegating to the same (last) delegate
        DelegateEscrow escrow = escrowFactory.escrowFor(delegate);
        gohm.mint(policy2, 33e18);
        vm.startPrank(policy2);
        gohm.approve(address(escrow), 33e18);
        escrow.delegate(ALICE, 33e18);

        // And someone else externally
        address random = makeAddr("random");
        gohm.mint(random, 33e18);
        vm.startPrank(random);
        gohm.approve(address(escrow), 33e18);
        escrow.delegate(ALICE, 33e18);

        // And a donation
        gohm.mint(address(escrow), 33e18);
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
        dlgte.withdrawUndelegatedGohm(ALICE, 0, false);
    }

    function test_applyDelegations_access() public {
        vm.startPrank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, ALICE));
        dlgte.applyDelegations(policy, new IDLGTEv1.DelegationRequest[](0));
    }

    function test_rescindDelegations_access() public {
        vm.startPrank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, ALICE));
        dlgte.rescindDelegations(ALICE, 123);
    }
}

contract DLGTETestDeposit is DLGTETestBase {
    using ModuleTestFixtureGenerator for OlympusGovDelegation;

    function test_depositUndelegatedGohm_fail_invalidOnBehalfOf() public {
        vm.startPrank(policy);
        vm.expectRevert(abi.encodeWithSelector(IDLGTEv1.DLGTE_InvalidAddress.selector));
        dlgte.depositUndelegatedGohm(address(0), 123);
    }

    function test_depositUndelegatedGohm_fail_invalidAmount() public {
        vm.startPrank(policy);
        vm.expectRevert(abi.encodeWithSelector(IDLGTEv1.DLGTE_InvalidAmount.selector));
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
        vm.expectRevert(abi.encodeWithSelector(IDLGTEv1.DLGTE_InvalidAddress.selector));
        dlgte.withdrawUndelegatedGohm(address(0), 123, false);
    }

    function test_withdrawUndelegatedGohm_fail_invalidAmount() public {
        vm.startPrank(policy);
        vm.expectRevert(abi.encodeWithSelector(IDLGTEv1.DLGTE_InvalidAmount.selector));
        dlgte.withdrawUndelegatedGohm(ALICE, 0, false);
    }

    function test_withdrawUndelegatedGohm_fail_notEnoughForPolicy() public {
        setupUndelegated(policy, ALICE, 100e18);

        vm.startPrank(policy2);
        vm.expectRevert(
            abi.encodeWithSelector(IDLGTEv1.DLGTE_ExceededPolicyAccountBalance.selector, 0, 123)
        );
        dlgte.withdrawUndelegatedGohm(ALICE, 123, false);
    }

    function test_withdrawUndelegatedGohm_fail_notEnoughUndelegated_noAutoRescind() public {
        setupUndelegated(policy, ALICE, 100e18);

        dlgte.applyDelegations(ALICE, delegationRequest(ALICE, 25e18));
        vm.expectRevert(
            abi.encodeWithSelector(
                IDLGTEv1.DLGTE_ExceededUndelegatedBalance.selector,
                75e18,
                100e18
            )
        );
        dlgte.withdrawUndelegatedGohm(ALICE, 100e18, false);
    }

    function test_withdrawUndelegatedGohm_success_withAutoRescind() public {
        setupUndelegated(policy, ALICE, 100e18);

        dlgte.applyDelegations(ALICE, delegationRequest(ALICE, 25e18));
        verifyAccountSummary(address(policy), ALICE, 100e18, 25e18, 1, 10, 100e18);
        vm.expectEmit(address(dlgte));
        emit DelegationApplied(ALICE, ALICE, -25e18);
        dlgte.withdrawUndelegatedGohm(ALICE, 100e18, true);
        verifyAccountSummary(address(policy), ALICE, 0, 0, 0, 10, 0);
    }

    function test_withdrawUndelegatedGohm_success_fullWithdrawal() public {
        setupUndelegated(policy, ALICE, 100e18);
        dlgte.applyDelegations(ALICE, delegationRequest(ALICE, 25e18));

        dlgte.withdrawUndelegatedGohm(ALICE, 75e18, false);
        verifyAccountSummary(address(policy), ALICE, 25e18, 25e18, 1, 10, 25e18);
        assertEq(gohm.balanceOf(policy), 75e18);
        assertEq(gohm.balanceOf(ALICE), 0);
        assertEq(gohm.balanceOf(address(dlgte)), 0);

        address expectedAliceEscrow = 0xCB6f5076b5bbae81D7643BfBf57897E8E3FB1db9;
        assertEq(gohm.balanceOf(expectedAliceEscrow), 25e18);
    }

    function test_withdrawUndelegatedGohm_success_partialWithdrawal_noAutoRescind() public {
        setupUndelegated(policy, ALICE, 100e18);
        dlgte.applyDelegations(ALICE, delegationRequest(ALICE, 25e18));

        dlgte.withdrawUndelegatedGohm(ALICE, 25e18, false);
        verifyAccountSummary(address(policy), ALICE, 75e18, 25e18, 1, 10, 75e18);
        assertEq(gohm.balanceOf(policy), 25e18);
        assertEq(gohm.balanceOf(ALICE), 0);
        assertEq(gohm.balanceOf(address(dlgte)), 50e18);

        address expectedAliceEscrow = 0xCB6f5076b5bbae81D7643BfBf57897E8E3FB1db9;
        assertEq(gohm.balanceOf(expectedAliceEscrow), 25e18);
    }

    function test_withdrawUndelegatedGohm_success_partialWithdrawal_withAutoRescind1() public {
        setupUndelegated(policy, ALICE, 100e18);
        dlgte.applyDelegations(ALICE, delegationRequest(ALICE, 25e18));

        dlgte.withdrawUndelegatedGohm(ALICE, 25e18, true);
        verifyAccountSummary(address(policy), ALICE, 75e18, 25e18, 1, 10, 75e18);
        assertEq(gohm.balanceOf(policy), 25e18);
        assertEq(gohm.balanceOf(ALICE), 0);
        assertEq(gohm.balanceOf(address(dlgte)), 50e18);

        address expectedAliceEscrow = 0xCB6f5076b5bbae81D7643BfBf57897E8E3FB1db9;
        assertEq(gohm.balanceOf(expectedAliceEscrow), 25e18);
    }

    function test_withdrawUndelegatedGohm_success_partialWithdrawal_withAutoRescind2() public {
        setupUndelegated(policy, ALICE, 100e18);
        dlgte.applyDelegations(ALICE, delegationRequest(ALICE, 25e18));

        dlgte.withdrawUndelegatedGohm(ALICE, 85e18, true);
        verifyAccountSummary(address(policy), ALICE, 15e18, 15e18, 1, 10, 15e18);
        assertEq(gohm.balanceOf(policy), 85e18);
        assertEq(gohm.balanceOf(ALICE), 0);
        assertEq(gohm.balanceOf(address(dlgte)), 0);

        address expectedAliceEscrow = 0xCB6f5076b5bbae81D7643BfBf57897E8E3FB1db9;
        assertEq(gohm.balanceOf(expectedAliceEscrow), 15e18);
    }

    function test_withdrawUndelegatedGohm_success_multiPolicy() public {
        setupUndelegated(policy, ALICE, 100e18);
        setupUndelegated(policy2, ALICE, 100e18);

        vm.startPrank(policy);
        dlgte.withdrawUndelegatedGohm(ALICE, 25e18, false);
        vm.startPrank(policy2);
        dlgte.withdrawUndelegatedGohm(ALICE, 65e18, false);

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
        vm.expectRevert(abi.encodeWithSelector(IDLGTEv1.DLGTE_InvalidAddress.selector));
        dlgte.applyDelegations(address(0), new IDLGTEv1.DelegationRequest[](0));
    }

    function test_applyDelegations_fail_invalidLength() public {
        vm.startPrank(policy);
        vm.expectRevert(abi.encodeWithSelector(IDLGTEv1.DLGTE_InvalidDelegationRequests.selector));
        dlgte.applyDelegations(ALICE, new IDLGTEv1.DelegationRequest[](0));
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
        verifyDelegationsOne(ALICE, BOB, 100e18, expectedEscrow);
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
        verifyDelegationsOne(ALICE, ALICE, 100e18, expectedEscrow);
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
        verifyDelegationsOne(ALICE, ALICE, 100e18, expectedEscrow);
    }

    function test_applyDelegations_success_existingDelegate() public {
        setupUndelegated(policy, ALICE, 100e18);

        address expectedEscrow = 0xCB6f5076b5bbae81D7643BfBf57897E8E3FB1db9;
        verifyApplyDelegations(ALICE, delegationRequest(ALICE, 50e18), 50e18, 0, 50e18);
        assertEq(gohm.balanceOf(address(dlgte)), 50e18);
        assertEq(gohm.balanceOf(expectedEscrow), 50e18);
        verifyAccountSummary(address(policy), ALICE, 100e18, 50e18, 1, 10, 100e18);
        verifyDelegationsOne(ALICE, ALICE, 50e18, expectedEscrow);

        verifyApplyDelegations(ALICE, delegationRequest(ALICE, 25e18), 25e18, 0, 25e18);
        assertEq(gohm.balanceOf(address(dlgte)), 25e18);
        assertEq(gohm.balanceOf(expectedEscrow), 75e18);
        verifyAccountSummary(address(policy), ALICE, 100e18, 75e18, 1, 10, 100e18);
        verifyDelegationsOne(ALICE, ALICE, 75e18, expectedEscrow);
    }

    function test_applyDelegations_fail_delegateTooMuch() public {
        setupUndelegated(policy, ALICE, 100e18);

        vm.expectRevert(
            abi.encodeWithSelector(
                IDLGTEv1.DLGTE_ExceededUndelegatedBalance.selector,
                100e18,
                100e18 + 1
            )
        );
        dlgte.applyDelegations(ALICE, delegationRequest(BOB, 100e18 + 1));
    }

    function test_applyDelegations_fail_badAddresses() public {
        setupUndelegated(policy, ALICE, 100e18);

        vm.expectRevert(abi.encodeWithSelector(IDLGTEv1.DLGTE_InvalidAddress.selector));
        dlgte.applyDelegations(ALICE, delegationRequest(address(0), 100e18));

        vm.expectRevert(abi.encodeWithSelector(IDLGTEv1.DLGTE_InvalidDelegateEscrow.selector));
        dlgte.applyDelegations(ALICE, transferDelegationRequest(ALICE, ALICE, 100e18));
    }

    function test_applyDelegations_fail_badAmount() public {
        vm.startPrank(policy);
        vm.expectRevert(abi.encodeWithSelector(IDLGTEv1.DLGTE_InvalidAmount.selector));
        dlgte.applyDelegations(ALICE, delegationRequest(ALICE, 0));

        vm.expectRevert(abi.encodeWithSelector(IDLGTEv1.DLGTE_InvalidAmount.selector));
        dlgte.applyDelegations(ALICE, delegationRequest(ALICE, uint256(type(int256).max)));

        setupUndelegated(policy, ALICE, 100e18);

        vm.expectRevert(abi.encodeWithSelector(IDLGTEv1.DLGTE_InvalidAmount.selector));
        dlgte.applyDelegations(ALICE, delegationRequest(ALICE, 0));
    }
}

contract DLGTETestDelegationsFromOneDelegate is DLGTETestBase {
    function test_applyDelegations_fail_invalidEscrow() public {
        seedDelegate();

        vm.expectRevert(abi.encodeWithSelector(IDLGTEv1.DLGTE_InvalidDelegateEscrow.selector));
        dlgte.applyDelegations(ALICE, unDelegationRequest(ALICE, 100e18));
    }

    function test_applyDelegations_fail_badAmount() public {
        seedDelegate();

        vm.expectRevert(abi.encodeWithSelector(IDLGTEv1.DLGTE_InvalidAmount.selector));
        dlgte.applyDelegations(ALICE, unDelegationRequest(BOB, 0));

        vm.expectRevert(abi.encodeWithSelector(
            IDLGTEv1.DLGTE_ExceededDelegatedBalance.selector,
            BOB,
            100e18,
            100e18+1
        ));
        dlgte.applyDelegations(ALICE, unDelegationRequest(BOB, 100e18+1));
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
        verifyDelegationsOne(ALICE, BOB, 75e18, expectedEscrow);
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

    function test_applyDelegations_success_minUndelegate() public {
        seedDelegate();

        IDLGTEv1.DelegationRequest[] memory delegationRequests = new IDLGTEv1.DelegationRequest[](1);
        delegationRequests[0] = IDLGTEv1.DelegationRequest({
            delegate: BOB,
            amount: type(int256).min
        });

        address expectedEscrow = 0xCB6f5076b5bbae81D7643BfBf57897E8E3FB1db9;
        vm.expectEmit(address(escrowFactory));
        emit Delegate(expectedEscrow, address(dlgte), ALICE, -100e18);
        vm.expectEmit(address(dlgte));
        emit DelegationApplied(ALICE, BOB, -100e18);
        verifyApplyDelegations(
            ALICE,
            delegationRequests,
            0,
            100e18,
            100e18
        );
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
        verifyDelegationsOne(ALICE, CHARLIE, 100e18, expectedCharlieEscrow);
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
        verifyApplyDelegations(
            ALICE,
            transferDelegationRequest(BOB, CHARLIE, 25e18),
            25e18,
            25e18,
            0
        );
        assertEq(gohm.balanceOf(address(dlgte)), 0);
        assertEq(gohm.balanceOf(address(policy)), 0);
        assertEq(gohm.balanceOf(expectedBobEscrow), 75e18);
        assertEq(gohm.balanceOf(expectedCharlieEscrow), 25e18);
        verifyAccountSummary(address(policy), ALICE, 100e18, 100e18, 2, 10, 100e18);
        verifyDelegationsTwo(
            ALICE,
            BOB,
            75e18,
            expectedBobEscrow,
            CHARLIE,
            25e18,
            expectedCharlieEscrow
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
            50e18,
            expectedBobEscrow,
            CHARLIE,
            25e18,
            expectedCharlieEscrow
        );

        vm.expectRevert(abi.encodeWithSelector(IDLGTEv1.DLGTE_TooManyDelegates.selector));
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

        verifyDelegationsOne(ALICE, BOB, 25e18 * 2, expectedBobEscrow);
        verifyDelegationsOne(BOB, ALICE, 10e18 * 2, expectedAliceEscrow);

        assertEq(gohm.balanceOf(address(dlgte)), 46e18);
        assertEq(gohm.balanceOf(address(policy)), 0);
        assertEq(gohm.balanceOf(address(policy2)), 0);
        assertEq(gohm.balanceOf(expectedBobEscrow), 50e18);
        assertEq(gohm.balanceOf(expectedAliceEscrow), 20e18);
    }
}

contract DLGTETestRescindDelegations is DLGTETestBase {
    function test_rescindDelegations_badAddress() public {
        vm.startPrank(policy);
        vm.expectRevert(abi.encodeWithSelector(IDLGTEv1.DLGTE_InvalidAddress.selector));
        dlgte.rescindDelegations(address(0), 123);
    }

    function test_rescindDelegations_alreadyEnoughUndelegated() public {
        seedDelegate(policy, ALICE, BOB, 100e18);
        setupUndelegated(policy, ALICE, 33e18);

        address expectedEscrow = 0xCB6f5076b5bbae81D7643BfBf57897E8E3FB1db9;        
        vm.startPrank(policy);
        assertEq(dlgte.rescindDelegations(ALICE, 10e18), 33e18);
        verifyDelegationsOne(ALICE, BOB, 100e18, expectedEscrow);
    }

    function test_rescindDelegations_noDelegations() public {
        setupUndelegated(policy, ALICE, 33e18);

        vm.startPrank(policy);
        assertEq(dlgte.rescindDelegations(ALICE, 50e18), 33e18);
    }

    function test_rescindDelegations_oneDelegateMoreThanEnough() public {
        seedDelegate(policy, ALICE, BOB, 100e18);

        uint256 expectedRescindAmount = 33e18;
        address expectedEscrow = 0xCB6f5076b5bbae81D7643BfBf57897E8E3FB1db9;        
        vm.startPrank(policy);
        vm.expectEmit(address(dlgte));
        emit DelegationApplied(ALICE, BOB, -int256(expectedRescindAmount));
        assertEq(dlgte.rescindDelegations(ALICE, expectedRescindAmount), expectedRescindAmount);
        verifyDelegationsOne(ALICE, BOB, 100e18-expectedRescindAmount, expectedEscrow);
    }

    function test_rescindDelegations_oneDelegateLessThanEnough() public {
        seedDelegate(policy, ALICE, BOB, 100e18);

        uint256 expectedRescindAmount = 133e18;
        vm.startPrank(policy);
        vm.expectEmit(address(dlgte));
        emit DelegationApplied(ALICE, BOB, -int256(100e18));
        assertEq(dlgte.rescindDelegations(ALICE, expectedRescindAmount), 100e18);
        verifyDelegationsZero(ALICE);
    }

    function test_rescindDelegations_oneDelegateExactlyEnough() public {
        seedDelegate(policy, ALICE, BOB, 100e18);

        uint256 expectedRescindAmount = 100e18;
        vm.startPrank(policy);
        vm.expectEmit(address(dlgte));
        emit DelegationApplied(ALICE, BOB, -int256(100e18));
        assertEq(dlgte.rescindDelegations(ALICE, expectedRescindAmount), 100e18);
        verifyDelegationsZero(ALICE);
    }

    function test_rescindDelegations_withOtherPolicyDelegation() public {
        // policy is able to undelegate policy2's delegated amount.
        // Policy is not able to actually withdraw those funds though.
        seedDelegate(policy, ALICE, BOB, 100e18);
        seedDelegate(policy2, ALICE, BOB, 100e18);

        verifyAccountSummary(address(policy), ALICE, 200e18, 200e18, 1, 10, 100e18);
        verifyAccountSummary(address(policy2), ALICE, 200e18, 200e18, 1, 10, 100e18);

        uint256 expectedRescindAmount = 133e18;
        address expectedEscrow = 0xCB6f5076b5bbae81D7643BfBf57897E8E3FB1db9;        
        vm.startPrank(policy);
        vm.expectEmit(address(dlgte));
        emit DelegationApplied(ALICE, BOB, -int256(expectedRescindAmount));
        assertEq(dlgte.rescindDelegations(ALICE, expectedRescindAmount), expectedRescindAmount);
        verifyDelegationsOne(ALICE, BOB, 200e18-expectedRescindAmount, expectedEscrow);
        verifyAccountSummary(address(policy), ALICE, 200e18, 200e18-expectedRescindAmount, 1, 10, 100e18);

        vm.expectRevert(
            abi.encodeWithSelector(IDLGTEv1.DLGTE_ExceededPolicyAccountBalance.selector, 100e18, 133e18)
        );
        dlgte.withdrawUndelegatedGohm(ALICE, expectedRescindAmount, false);

        dlgte.withdrawUndelegatedGohm(ALICE, 100e18, false);
        verifyAccountSummary(address(policy), ALICE, 100e18, 200e18-expectedRescindAmount, 1, 10, 0);
        verifyAccountSummary(address(policy2), ALICE, 100e18, 200e18-expectedRescindAmount, 1, 10, 100e18);
    }

    function test_rescindDelegations_multiDelegatesMoreThanEnough() public {
        seedDelegate(policy, ALICE, ALICE, 100e18);
        seedDelegate(policy, ALICE, BOB, 100e18);
        seedDelegate(policy, ALICE, CHARLIE, 100e18);
        seedDelegate(policy2, ALICE, ALICE, 100e18);

        uint256 expectedRescindAmount = 320e18;
        address expectedEscrow = 0x5Fa39CD9DD20a3A77BA0CaD164bD5CF0d7bb3303;        
        vm.startPrank(policy);
        vm.expectEmit(address(dlgte));
        emit DelegationApplied(ALICE, ALICE, -200e18);
        vm.expectEmit(address(dlgte));
        emit DelegationApplied(ALICE, BOB, -100e18);
        vm.expectEmit(address(dlgte));
        emit DelegationApplied(ALICE, CHARLIE, -20e18);
        assertEq(dlgte.rescindDelegations(ALICE, expectedRescindAmount), expectedRescindAmount);
        verifyDelegationsOne(ALICE, CHARLIE, 80e18, expectedEscrow);
    }

    function test_rescindDelegations_multiDelegatesLessThanEnough() public {
        seedDelegate(policy, ALICE, ALICE, 100e18);
        seedDelegate(policy, ALICE, BOB, 100e18);
        seedDelegate(policy, ALICE, CHARLIE, 100e18);
        seedDelegate(policy2, ALICE, ALICE, 100e18);

        uint256 expectedRescindAmount = 520e18;
        vm.startPrank(policy);
        vm.expectEmit(address(dlgte));
        emit DelegationApplied(ALICE, ALICE, -200e18);
        vm.expectEmit(address(dlgte));
        emit DelegationApplied(ALICE, BOB, -100e18);
        vm.expectEmit(address(dlgte));
        emit DelegationApplied(ALICE, CHARLIE, -100e18);
        assertEq(dlgte.rescindDelegations(ALICE, expectedRescindAmount), 400e18);
        verifyDelegationsZero(ALICE);
    }

    function test_rescindDelegations_multiDelegatesExactlyEnough() public {
        seedDelegate(policy, ALICE, ALICE, 100e18);
        seedDelegate(policy, ALICE, BOB, 100e18);
        seedDelegate(policy, ALICE, CHARLIE, 100e18);
        seedDelegate(policy2, ALICE, ALICE, 100e18);

        uint256 expectedRescindAmount = 400e18;
        vm.startPrank(policy);
        vm.expectEmit(address(dlgte));
        emit DelegationApplied(ALICE, ALICE, -200e18);
        vm.expectEmit(address(dlgte));
        emit DelegationApplied(ALICE, BOB, -100e18);
        vm.expectEmit(address(dlgte));
        emit DelegationApplied(ALICE, CHARLIE, -100e18);
        assertEq(dlgte.rescindDelegations(ALICE, expectedRescindAmount), expectedRescindAmount);
        verifyDelegationsZero(ALICE);
    }

    function test_rescindDelegations_gas() public {
        uint256 totalCollateral = 100_000e18;
        uint32 numDelegates = 100;
        applyManyDelegations(totalCollateral, numDelegates);

        vm.startPrank(policy);
        uint256 actualUndelegatedBalance;
        uint256 gasBefore = gasleft();
        actualUndelegatedBalance = dlgte.rescindDelegations(ALICE, totalCollateral);
        assertLt(gasBefore-gasleft(), 3_600_000);
        assertEq(actualUndelegatedBalance, totalCollateral);
    }
}

contract DLGTETestViews is DLGTETestBase {
    function test_accountDelegationsList_underOnePage() public {
        uint256 totalCollateral = 100_000e18;
        uint32 numDelegates = 30;
        applyManyDelegations(totalCollateral, numDelegates);

        uint256 extra_i = ((numDelegates - 1) * numDelegates) / 2;
        verifyAccountSummary(
            address(policy),
            ALICE,
            totalCollateral,
            uint256(1e18) * numDelegates + extra_i,
            numDelegates,
            numDelegates,
            totalCollateral
        );

        IDLGTEv1.AccountDelegation[] memory delegations = dlgte.accountDelegationsList(
            ALICE,
            0,
            50
        );
        assertEq(delegations.length, numDelegates);
        assertNotEq(delegations[0].delegate, address(0));
        assertEq(delegations[0].amount, 1e18);
        assertEq(dlgte.totalDelegatedTo(delegations[0].delegate), 1e18);
        assertNotEq(delegations[0].escrow, address(0));
        assertNotEq(delegations[numDelegates - 1].delegate, address(0));
        assertEq(delegations[numDelegates - 1].amount, 1e18 + numDelegates - 1);
        assertEq(
            dlgte.totalDelegatedTo(delegations[numDelegates - 1].delegate),
            1e18 + numDelegates - 1 + 99e18
        );
        assertNotEq(delegations[numDelegates - 1].escrow, address(0));

        delegations = dlgte.accountDelegationsList(ALICE, 60, 80);
        assertEq(delegations.length, 0);
    }

    function test_accountDelegationsList_exactlyOnePage() public {
        uint256 totalCollateral = 100_000e18;
        uint32 numDelegates = 25;
        applyManyDelegations(totalCollateral, numDelegates);

        uint256 extra_i = ((numDelegates - 1) * numDelegates) / 2;
        verifyAccountSummary(
            address(policy),
            ALICE,
            totalCollateral,
            uint256(1e18) * numDelegates + extra_i,
            numDelegates,
            numDelegates,
            totalCollateral
        );

        IDLGTEv1.AccountDelegation[] memory delegations = dlgte.accountDelegationsList(
            ALICE,
            0,
            numDelegates
        );
        assertEq(delegations.length, numDelegates);
        assertNotEq(delegations[0].delegate, address(0));
        assertEq(delegations[0].amount, 1e18 + 0);
        assertEq(dlgte.totalDelegatedTo(delegations[0].delegate), 1e18 + 0);
        assertNotEq(delegations[0].escrow, address(0));
        assertNotEq(delegations[numDelegates - 1].delegate, address(0));
        assertEq(delegations[numDelegates - 1].amount, 1e18 + numDelegates - 1);
        assertEq(
            dlgte.totalDelegatedTo(delegations[numDelegates - 1].delegate),
            1e18 + numDelegates - 1 + 99e18
        );
        assertNotEq(delegations[numDelegates - 1].escrow, address(0));

        delegations = dlgte.accountDelegationsList(ALICE, numDelegates, 100);
        assertEq(delegations.length, 0);
    }

    function test_accountDelegationsList_partOnePage() public {
        uint256 totalCollateral = 100_000e18;
        uint32 numDelegates = 30;
        applyManyDelegations(totalCollateral, numDelegates);

        uint256 extra_i = ((numDelegates - 1) * numDelegates) / 2;
        verifyAccountSummary(
            address(policy),
            ALICE,
            totalCollateral,
            uint256(1e18) * numDelegates + extra_i,
            numDelegates,
            numDelegates,
            totalCollateral
        );

        IDLGTEv1.AccountDelegation[] memory delegations = dlgte.accountDelegationsList(
            ALICE,
            10,
            numDelegates
        );
        assertEq(delegations.length, numDelegates - 10);
        assertNotEq(delegations[0].delegate, address(0));
        assertEq(delegations[0].amount, 1e18 + 10);
        assertEq(dlgte.totalDelegatedTo(delegations[0].delegate), 1e18 + 10);
        assertNotEq(delegations[0].escrow, address(0));
        assertNotEq(delegations[delegations.length - 1].delegate, address(0));
        assertEq(delegations[delegations.length - 1].amount, 1e18 + numDelegates - 1);
        assertEq(
            dlgte.totalDelegatedTo(delegations[delegations.length - 1].delegate),
            1e18 + numDelegates - 1 + 99e18
        );
        assertNotEq(delegations[delegations.length - 1].escrow, address(0));

        delegations = dlgte.accountDelegationsList(ALICE, 0, 0);
        assertEq(delegations.length, 0);
        delegations = dlgte.accountDelegationsList(ALICE, 10, 0);
        assertEq(delegations.length, 0);
    }

    function test_accountDelegationsList_twoPages() public {
        // Nest for stack to deep with coverage
        {
            uint256 totalCollateral = 100_000e18;
            uint32 numDelegates = 30;
            applyManyDelegations(totalCollateral, numDelegates);

            uint256 extra_i = ((numDelegates - 1) * numDelegates) / 2;
            verifyAccountSummary(
                address(policy),
                ALICE,
                totalCollateral,
                uint256(1e18) * numDelegates + extra_i,
                numDelegates,
                numDelegates,
                totalCollateral
            );
        }

        {
            IDLGTEv1.AccountDelegation[] memory delegations = dlgte.accountDelegationsList(
                ALICE,
                0,
                15
            );
            IDLGTEv1.AccountDelegation memory adelegation = delegations[0];
            assertEq(delegations.length, 15);
            assertNotEq(adelegation.delegate, address(0));
            assertEq(adelegation.amount, 1e18);
            assertEq(dlgte.totalDelegatedTo(adelegation.delegate), 1e18);
            assertNotEq(adelegation.escrow, address(0));

            adelegation = delegations[delegations.length - 1];
            assertNotEq(adelegation.delegate, address(0));
            assertEq(adelegation.amount, 1e18 + 14);
            assertEq(dlgte.totalDelegatedTo(adelegation.delegate), 1e18 + 14);
            assertNotEq(adelegation.escrow, address(0));
        }

        {
            IDLGTEv1.AccountDelegation[] memory delegations = dlgte.accountDelegationsList(ALICE, 15, 50);
            IDLGTEv1.AccountDelegation memory adelegation = delegations[0];
            assertEq(delegations.length, 15);
            adelegation = delegations[0];
            assertNotEq(adelegation.delegate, address(0));
            assertEq(adelegation.amount, 1e18 + 15);
            assertEq(dlgte.totalDelegatedTo(adelegation.delegate), 1e18 + 15);
            assertNotEq(adelegation.escrow, address(0));

            adelegation = delegations[delegations.length - 1];
            assertNotEq(adelegation.delegate, address(0));
            assertEq(adelegation.amount, 1e18 + 29);
            assertEq(
                dlgte.totalDelegatedTo(adelegation.delegate),
                1e18 + 29 + 99e18
            );
            assertNotEq(adelegation.escrow, address(0));
        }
    }
}
