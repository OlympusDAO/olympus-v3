// SPDX-License-Identifier: MAGPL-3.0-only
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";
import {MockGohm} from "test/mocks/MockGohm.sol";

import {OlympusGovDelegation} from "modules/DLGTE/OlympusGovDelegation.sol";
import {DLGTEv1} from "modules/DLGTE/DLGTE.v1.sol";
import {Module, Kernel, Actions, Keycode} from "src/Kernel.sol";

contract DLGTETestBase is Test {
    using ModuleTestFixtureGenerator for OlympusGovDelegation;

    Kernel internal kernel;

    OlympusGovDelegation internal dlgte;
    MockGohm internal gohm;

    address public immutable alice = makeAddr("ALICE");
    address public immutable bob = makeAddr("BOB");
    address public immutable charlie = makeAddr("CHARLIE");
    address public immutable daniel = makeAddr("DANIEL");

    address public policy;

    event TransferredGohm(
        address indexed policy,
        address indexed account, 
        int256 gOhmDelta
    );

    event DelegateEscrowCreated(
        address indexed delegate,
        address indexed escrow
    );

    event DelegationApplied(
        address indexed policy,
        address indexed account, 
        address indexed fromDelegate, 
        address toDelegate, 
        uint256 gOhmAmount
    );

    function setUp() public {
        vm.warp(1_000_000);

        // Deploy Kernel and modules
        kernel = new Kernel();
        gohm = new MockGohm("gOHM", "gOHM", 18);
        dlgte = new OlympusGovDelegation(kernel, address(gohm));

        // Generate fixtures
        policy = dlgte.generateGodmodeFixture(type(OlympusGovDelegation).name);

        // Install modules and policies on Kernel
        kernel.executeAction(Actions.InstallModule, address(dlgte));
        kernel.executeAction(Actions.ActivatePolicy, policy);
    }

    function setupUndelegated(address account) internal {
        vm.startPrank(policy);
        deal(address(gohm), address(policy), 100e18);
        gohm.approve(address(dlgte), 100e18);
        dlgte.applyDelegations(
            account, 
            100e18, 
            new DLGTEv1.DelegationRequest[](0),
            DLGTEv1.AllowedDelegationRequests.Any
        );
    }

    function verifyAccountSummary(
        address forPolicy,
        address account,
        uint256 expectedTotalGOhm,
        uint256 expectedDelegatedGOhm,
        uint256 expectedNumDelegateAddresses,
        uint256 expectedMaxAllowedDelegateAddresses
        ) internal {
        (
            uint256 totalGOhm,
            uint256 delegatedGOhm,
            uint256 numDelegateAddresses,
            uint256 maxAllowedDelegateAddresses
        ) = dlgte.accountDelegationSummary(forPolicy, account);
        assertEq(totalGOhm, expectedTotalGOhm, "expectedTotalGOhm");
        assertEq(delegatedGOhm, expectedDelegatedGOhm, "expectedDelegatedGOhm");
        assertEq(numDelegateAddresses, expectedNumDelegateAddresses, "expectedNumDelegateAddresses");
        assertEq(maxAllowedDelegateAddresses, expectedMaxAllowedDelegateAddresses, "expectedMaxAllowedDelegateAddresses");
    }

    function verifyDelegationsZero(
        address forPolicy,
        address account
    ) internal {
        DLGTEv1.AccountDelegation[] memory delegations = dlgte.accountDelegationsList(forPolicy ,account, 0, 10);
        assertEq(delegations.length, 0);
    }

    function verifyDelegationsOne(
        address forPolicy,
        address account,
        address expectedDelegate,
        address expectedEscrow,
        uint256 expectedTotalAmount
    ) internal {
        DLGTEv1.AccountDelegation[] memory delegations = dlgte.accountDelegationsList(forPolicy ,account, 0, 10);
        assertEq(delegations.length, 1);
        assertEq(delegations[0].delegate, expectedDelegate, "delegate");
        assertEq(delegations[0].escrow, expectedEscrow, "escrow");
        assertEq(delegations[0].totalAmount, expectedTotalAmount, "totalAmount");
    }

    function verifyDelegationsTwo(
        address forPolicy,
        address account,
        address expectedDelegate1,
        address expectedEscrow1,
        uint256 expectedTotalAmount1,
        address expectedDelegate2,
        address expectedEscrow2,
        uint256 expectedTotalAmount2
    ) internal {
        DLGTEv1.AccountDelegation[] memory delegations = dlgte.accountDelegationsList(forPolicy ,account, 0, 10);
        assertEq(delegations.length, 2);
        assertEq(delegations[0].delegate, expectedDelegate1, "delegate1");
        assertEq(delegations[0].escrow, expectedEscrow1, "escrow1");
        assertEq(delegations[0].totalAmount, expectedTotalAmount1, "totalAmount1");
        assertEq(delegations[1].delegate, expectedDelegate2, "delegate2");
        assertEq(delegations[1].escrow, expectedEscrow2, "escrow2");
        assertEq(delegations[1].totalAmount, expectedTotalAmount2, "totalAmount2");
    }

    function oneDelegationRequest(
        address from,
        address to,
        uint256 amount
    ) internal pure returns (
        DLGTEv1.DelegationRequest[] memory delegationRequests
    ) {
        delegationRequests = new DLGTEv1.DelegationRequest[](1);
        delegationRequests[0] = DLGTEv1.DelegationRequest({
            fromDelegate: from,
            toDelegate: to,
            amount: amount
        });
    }

    function seedDelegate() internal {
        vm.startPrank(policy);
        deal(address(gohm), address(policy), 100e18);
        gohm.approve(address(dlgte), 100e18);

        assertEq(
            dlgte.applyDelegations(
                alice, 
                100e18,
                oneDelegationRequest(address(0), bob, 100e18),
                DLGTEv1.AllowedDelegationRequests.Any
            ),
            100e18
        );
    }
}

contract DLGTETestAdmin is DLGTETestBase {
    event MaxDelegateAddressesSet(
        address indexed policy, 
        address indexed account, 
        uint256 maxDelegateAddresses
    );
    
    function test_constructor() public {
        assertEq(address(dlgte.kernel()), address(kernel));
        assertEq(address(dlgte.gOHM()), address(gohm));
        assertEq(dlgte.DEFAULT_MAX_DELEGATE_ADDRESSES(), 10);
        assertEq(Keycode.unwrap(dlgte.KEYCODE()), bytes5(0x444c475445));
        (uint8 major, uint8 minor) = dlgte.VERSION();
        assertEq(major, 1);
        assertEq(minor, 0);
    }

    function test_maxDelegateAddresses_default() public {
        assertEq(dlgte.maxDelegateAddresses(policy, alice), 10);
    }

    function test_setMaxDelegateAddresses_zero() public {
        vm.startPrank(policy);
        vm.expectEmit(address(dlgte));
        emit MaxDelegateAddressesSet(policy, alice, 0);
        dlgte.setMaxDelegateAddresses(alice, 0);
        assertEq(dlgte.maxDelegateAddresses(policy, alice), 10);
    }

    function test_setMaxDelegateAddresses_many() public {
        vm.startPrank(policy);
        vm.expectEmit(address(dlgte));
        emit MaxDelegateAddressesSet(policy, alice, 999);
        dlgte.setMaxDelegateAddresses(alice, 999);
        assertEq(dlgte.maxDelegateAddresses(policy, alice), 999);
    }
}

contract DLGTETestAccess is DLGTETestBase {
    function test_setMaxDelegateAddresses_access() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, alice));
        dlgte.setMaxDelegateAddresses(policy, 123);
    }

    function test_applyDelegations_access() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, alice));
        dlgte.applyDelegations(policy, 0, new DLGTEv1.DelegationRequest[](0), DLGTEv1.AllowedDelegationRequests.Any);
    }
}

contract DLGTETestDelegationsNoDelegates is DLGTETestBase {

    function test_applyDelegations_fail_invalidOnBehalfOf() public {
        vm.startPrank(policy);
        vm.expectRevert(abi.encodeWithSelector(DLGTEv1.DLGTE_InvalidAddress.selector));
        dlgte.applyDelegations(
            address(0),
            0,
            new DLGTEv1.DelegationRequest[](0),
            DLGTEv1.AllowedDelegationRequests.Any
        );
    }

    function test_applyDelegations_success_new_noChange() public {
        vm.startPrank(policy);
        assertEq(
            dlgte.applyDelegations(
                address(alice),
                0,
                new DLGTEv1.DelegationRequest[](0),
                DLGTEv1.AllowedDelegationRequests.Any
            ),
            0
        );
        assertEq(gohm.balanceOf(address(dlgte)), 0);
        verifyAccountSummary(address(policy), alice, 0, 0, 0, 10);
    }

    function test_applyDelegations_success_existing_noChange() public {
        setupUndelegated(alice);
        assertEq(gohm.balanceOf(address(dlgte)), 100e18);
        verifyAccountSummary(address(policy), alice, 100e18, 0, 0, 10);

        assertEq(
            dlgte.applyDelegations(
                address(alice),
                0,
                new DLGTEv1.DelegationRequest[](0),
                DLGTEv1.AllowedDelegationRequests.Any
            ),
            0
        );
        assertEq(gohm.balanceOf(address(dlgte)), 100e18);
        verifyAccountSummary(address(policy), alice, 100e18, 0, 0, 10);
    }

    function test_applyDelegations_sendGohm_fail_notEnough() public {
        vm.startPrank(policy);
        deal(address(gohm), address(policy), 75e18);
        gohm.approve(address(dlgte), 75e18);
        vm.expectRevert("TRANSFER_FROM_FAILED");
        dlgte.applyDelegations(
            alice, 
            100e18, // more than what's approved 
            new DLGTEv1.DelegationRequest[](0),
            DLGTEv1.AllowedDelegationRequests.Any
        );
    }

    function test_applyDelegations_sendGohm_success_undelegated() public {
        vm.startPrank(policy);
        deal(address(gohm), address(policy), 100e18);
        gohm.approve(address(dlgte), 100e18);

        vm.expectEmit(address(dlgte));
        emit TransferredGohm(address(policy), alice, 100e18);
        assertEq(
            dlgte.applyDelegations(
                alice, 
                100e18,
                new DLGTEv1.DelegationRequest[](0),
                DLGTEv1.AllowedDelegationRequests.Any
            ),
            0
        );
        assertEq(gohm.balanceOf(address(dlgte)), 100e18);
        verifyAccountSummary(address(policy), alice, 100e18, 0, 0, 10);
    }

    function test_applyDelegations_sendGohm_success_undelegated_twice() public {
        setupUndelegated(alice);
        
        deal(address(gohm), address(policy), 50e18);
        gohm.approve(address(dlgte), 50e18);

        vm.expectEmit(address(dlgte));
        emit TransferredGohm(address(policy), alice, 50e18);
        assertEq(
            dlgte.applyDelegations(
                alice, 
                50e18,
                new DLGTEv1.DelegationRequest[](0),
                DLGTEv1.AllowedDelegationRequests.Any
            ),
            0
        );
        assertEq(gohm.balanceOf(address(dlgte)), 150e18);
        verifyAccountSummary(address(policy), alice, 150e18, 0, 0, 10);
    }

    function test_applyDelegations_receiveGohm_fail_tooMuch() public {
        setupUndelegated(alice);
        
        vm.expectRevert(abi.encodeWithSelector(DLGTEv1.DLGTE_ExceededGOhmBalance.selector, 100e18, 100e18+1));
        dlgte.applyDelegations(
            alice, 
            -100e18 - 1,
            new DLGTEv1.DelegationRequest[](0),
            DLGTEv1.AllowedDelegationRequests.Any
        );
    }

    function test_applyDelegations_receiveGohm_success_undelegated() public {
        setupUndelegated(alice);
        
        vm.expectEmit(address(dlgte));
        emit TransferredGohm(address(policy), alice, -25e18);
        assertEq(
            dlgte.applyDelegations(
                alice, 
                -25e18,
                new DLGTEv1.DelegationRequest[](0),
                DLGTEv1.AllowedDelegationRequests.Any
            ),
            0
        );
        assertEq(gohm.balanceOf(address(dlgte)), 75e18);
        assertEq(gohm.balanceOf(address(policy)), 25e18);
        verifyAccountSummary(address(policy), alice, 75e18, 0, 0, 10);
    }
}

contract DLGTETestDelegationsToOneDelegate is DLGTETestBase {
    function test_applyDelegations_success_oneDelegate() public {
        vm.startPrank(policy);
        deal(address(gohm), address(policy), 100e18);
        gohm.approve(address(dlgte), 100e18);

        address expectedEscrow = 0x4f81992FCe2E1846dD528eC0102e6eE1f61ed3e2;
        vm.expectEmit(address(dlgte));
        emit TransferredGohm(address(policy), alice, 100e18);
        vm.expectEmit(address(dlgte));
        emit DelegateEscrowCreated(bob, expectedEscrow);
        vm.expectEmit(address(dlgte));
        emit DelegationApplied(address(policy), alice, address(0), bob, 100e18);
        assertEq(
            dlgte.applyDelegations(
                alice, 
                100e18,
                oneDelegationRequest(address(0), bob, 100e18),
                DLGTEv1.AllowedDelegationRequests.Any
            ),
            100e18
        );
        assertEq(gohm.balanceOf(address(dlgte)), 0);
        assertEq(gohm.balanceOf(expectedEscrow), 100e18);
        verifyAccountSummary(address(policy), alice, 100e18, 100e18, 1, 10);
        verifyDelegationsOne(address(policy), alice, bob, expectedEscrow, 100e18);
    }

    function test_applyDelegations_success_selfDelegate() public {
        vm.startPrank(policy);
        deal(address(gohm), address(policy), 100e18);
        gohm.approve(address(dlgte), 100e18);

        address expectedEscrow = 0x4f81992FCe2E1846dD528eC0102e6eE1f61ed3e2;
        vm.expectEmit(address(dlgte));
        emit TransferredGohm(address(policy), alice, 100e18);
        vm.expectEmit(address(dlgte));
        emit DelegateEscrowCreated(alice, expectedEscrow);
        vm.expectEmit(address(dlgte));
        emit DelegationApplied(address(policy), alice, address(0), alice, 100e18);
        assertEq(
            dlgte.applyDelegations(
                alice, 
                100e18,
                oneDelegationRequest(address(0), alice, 100e18),
                DLGTEv1.AllowedDelegationRequests.Any
            ),
            100e18
        );
        assertEq(gohm.balanceOf(address(dlgte)), 0);
        assertEq(gohm.balanceOf(expectedEscrow), 100e18);
        verifyAccountSummary(address(policy), alice, 100e18, 100e18, 1, 10);
        verifyDelegationsOne(address(policy), alice, alice, expectedEscrow, 100e18);
    }

    function test_applyDelegations_success_maxDelegate() public {
        vm.startPrank(policy);
        deal(address(gohm), address(policy), 100e18);
        gohm.approve(address(dlgte), 100e18);

        address expectedEscrow = 0x4f81992FCe2E1846dD528eC0102e6eE1f61ed3e2;
        vm.expectEmit(address(dlgte));
        emit TransferredGohm(address(policy), alice, 100e18);
        vm.expectEmit(address(dlgte));
        emit DelegateEscrowCreated(alice, expectedEscrow);
        vm.expectEmit(address(dlgte));
        emit DelegationApplied(address(policy), alice, address(0), alice, 100e18);
        assertEq(
            dlgte.applyDelegations(
                alice, 
                100e18,
                oneDelegationRequest(address(0), alice, type(uint256).max),
                DLGTEv1.AllowedDelegationRequests.Any
            ),
            100e18
        );
        assertEq(gohm.balanceOf(address(dlgte)), 0);
        assertEq(gohm.balanceOf(expectedEscrow), 100e18);
        verifyAccountSummary(address(policy), alice, 100e18, 100e18, 1, 10);
        verifyDelegationsOne(address(policy), alice, alice, expectedEscrow, 100e18);
    }

    function test_applyDelegations_success_existingDelegate() public {
        vm.startPrank(policy);
        deal(address(gohm), address(policy), 100e18);
        gohm.approve(address(dlgte), 100e18);

        address expectedEscrow = 0x4f81992FCe2E1846dD528eC0102e6eE1f61ed3e2;
        assertEq(
            dlgte.applyDelegations(
                alice, 
                100e18,
                oneDelegationRequest(address(0), alice, 50e18),
                DLGTEv1.AllowedDelegationRequests.Any
            ),
            50e18
        );
        assertEq(gohm.balanceOf(address(dlgte)), 50e18);
        assertEq(gohm.balanceOf(expectedEscrow), 50e18);
        verifyAccountSummary(address(policy), alice, 100e18, 50e18, 1, 10);
        verifyDelegationsOne(address(policy), alice, alice, expectedEscrow, 50e18);

        assertEq(
            dlgte.applyDelegations(
                alice, 
                0,
                oneDelegationRequest(address(0), alice, 25e18),
                DLGTEv1.AllowedDelegationRequests.Any
            ),
            75e18
        );
        assertEq(gohm.balanceOf(address(dlgte)), 25e18);
        assertEq(gohm.balanceOf(expectedEscrow), 75e18);
        verifyAccountSummary(address(policy), alice, 100e18, 75e18, 1, 10);
        verifyDelegationsOne(address(policy), alice, alice, expectedEscrow, 75e18);
    }

    function test_applyDelegations_fail_delegateTooMuch() public {
        vm.startPrank(policy);
        deal(address(gohm), address(policy), 100e18);
        gohm.approve(address(dlgte), 100e18);

        vm.expectRevert(abi.encodeWithSelector(DLGTEv1.DLGTE_ExceededGOhmBalance.selector, 100e18, 100e18+1));
        dlgte.applyDelegations(
            alice, 
            100e18,
            oneDelegationRequest(address(0), bob, 100e18+1),
            DLGTEv1.AllowedDelegationRequests.Any
        );
    }

    function test_applyDelegations_fail_badAddresses() public {
        vm.startPrank(policy);
        deal(address(gohm), address(policy), 100e18);
        gohm.approve(address(dlgte), 100e18);

        vm.expectRevert(abi.encodeWithSelector(DLGTEv1.DLGTE_InvalidAddress.selector));
        dlgte.applyDelegations(
            alice, 
            100e18,
            oneDelegationRequest(address(0), address(0), 100e18),
            DLGTEv1.AllowedDelegationRequests.Any
        );

        vm.expectRevert(abi.encodeWithSelector(DLGTEv1.DLGTE_InvalidAddress.selector));
        dlgte.applyDelegations(
            alice, 
            100e18,
            oneDelegationRequest(alice, alice, 100e18),
            DLGTEv1.AllowedDelegationRequests.Any
        );
    }

    function test_applyDelegations_fail_badAmount() public {
        vm.startPrank(policy);
        vm.expectRevert(abi.encodeWithSelector(DLGTEv1.DLGTE_InvalidAmount.selector));
        dlgte.applyDelegations(
            alice, 
            0,
            oneDelegationRequest(address(0), alice, 0),
            DLGTEv1.AllowedDelegationRequests.Any
        );

        deal(address(gohm), address(policy), 100e18);
        gohm.approve(address(dlgte), 100e18);

        vm.expectRevert(abi.encodeWithSelector(DLGTEv1.DLGTE_InvalidAmount.selector));
        dlgte.applyDelegations(
            alice, 
            100e18,
            oneDelegationRequest(address(0), alice, 0),
            DLGTEv1.AllowedDelegationRequests.Any
        );
    }

    function test_applyDelegations_fail_rescindOnly() public {
        vm.startPrank(policy);
        deal(address(gohm), address(policy), 100e18);
        gohm.approve(address(dlgte), 100e18);

        vm.expectRevert(abi.encodeWithSelector(DLGTEv1.DLGTE_CanOnlyRescindDelegation.selector));
        dlgte.applyDelegations(
            alice, 
            100e18,
            oneDelegationRequest(address(0), alice, 100e18),
            DLGTEv1.AllowedDelegationRequests.RescindOnly
        );
    }

}

contract DLGTETestDelegationsFromOneDelegate is DLGTETestBase {
    function test_applyDelegations_fail_invalidEscrow() public {
        seedDelegate();
        
        vm.expectRevert(abi.encodeWithSelector(DLGTEv1.DLGTE_InvalidDelegateEscrow.selector));
        dlgte.applyDelegations(
            alice, 
            -100e18,
            oneDelegationRequest(alice, address(0), 100e18),
            DLGTEv1.AllowedDelegationRequests.Any
        );
    }

    function test_applyDelegations_fail_withdrawTooMuch() public {
        seedDelegate();
        
        vm.expectRevert(abi.encodeWithSelector(DLGTEv1.DLGTE_ExceededGOhmBalance.selector, 25e18, 100e18));
        dlgte.applyDelegations(
            alice, 
            -100e18, // More than Alice has undelegated
            oneDelegationRequest(bob, address(0), 25e18),
            DLGTEv1.AllowedDelegationRequests.Any
        );
    }

    function test_applyDelegations_success_partialWithdraw() public {
        seedDelegate();
        
        address expectedEscrow = 0x4f81992FCe2E1846dD528eC0102e6eE1f61ed3e2;
        vm.expectEmit(address(dlgte));
        emit DelegationApplied(address(policy), alice, bob, address(0), 25e18);
        vm.expectEmit(address(dlgte));
        emit TransferredGohm(address(policy), alice, -10e18);
        assertEq(
            dlgte.applyDelegations(
                alice, 
                -10e18,
                oneDelegationRequest(bob, address(0), 25e18),
                DLGTEv1.AllowedDelegationRequests.Any
            ),
            75e18
        );
        assertEq(gohm.balanceOf(address(dlgte)), 15e18);
        assertEq(gohm.balanceOf(address(policy)), 10e18);
        assertEq(gohm.balanceOf(expectedEscrow), 75e18);
        verifyAccountSummary(address(policy), alice, 90e18, 75e18, 1, 10);
        verifyDelegationsOne(address(policy), alice, bob, expectedEscrow, 75e18);
    }

    function test_applyDelegations_success_fullyWithdraw() public {
        seedDelegate();
        
        address expectedEscrow = 0x4f81992FCe2E1846dD528eC0102e6eE1f61ed3e2;
        vm.expectEmit(address(dlgte));
        emit DelegationApplied(address(policy), alice, bob, address(0), 100e18);
        vm.expectEmit(address(dlgte));
        emit TransferredGohm(address(policy), alice, -100e18);
        assertEq(
            dlgte.applyDelegations(
                alice, 
                -100e18,
                oneDelegationRequest(bob, address(0), 100e18),
                DLGTEv1.AllowedDelegationRequests.Any
            ),
            0
        );
        assertEq(gohm.balanceOf(address(dlgte)), 0);
        assertEq(gohm.balanceOf(address(policy)), 100e18);
        assertEq(gohm.balanceOf(expectedEscrow), 0);
        verifyAccountSummary(address(policy), alice, 0, 0, 0, 10);
        verifyDelegationsZero(address(policy), alice);
    }

    function test_applyDelegations_success_rescindOnly() public {
        seedDelegate();
        
        address expectedEscrow = 0x4f81992FCe2E1846dD528eC0102e6eE1f61ed3e2;
        vm.expectEmit(address(dlgte));
        emit DelegationApplied(address(policy), alice, bob, address(0), 100e18);
        vm.expectEmit(address(dlgte));
        emit TransferredGohm(address(policy), alice, -100e18);
        assertEq(
            dlgte.applyDelegations(
                alice, 
                -100e18,
                oneDelegationRequest(bob, address(0), 100e18),
                DLGTEv1.AllowedDelegationRequests.RescindOnly
            ),
            0
        );
        assertEq(gohm.balanceOf(address(dlgte)), 0);
        assertEq(gohm.balanceOf(address(policy)), 100e18);
        assertEq(gohm.balanceOf(expectedEscrow), 0);
        verifyAccountSummary(address(policy), alice, 0, 0, 0, 10);
        verifyDelegationsZero(address(policy), alice);
    }
}

contract DLGTETestDelegationsTransferDelegate is DLGTETestBase {
    function test_applyDelegations_fail_pullTooMuch() public {
        seedDelegate();

        vm.expectRevert(abi.encodeWithSelector(DLGTEv1.DLGTE_ExceededGOhmBalance.selector, 0, 1));
        dlgte.applyDelegations(
            alice, 
            -1,
            oneDelegationRequest(bob, charlie, 100e18),
            DLGTEv1.AllowedDelegationRequests.Any
        );
    }

    function test_applyDelegations_success_fullyTransfer() public {
        seedDelegate();
        
        address expectedBobEscrow = 0x4f81992FCe2E1846dD528eC0102e6eE1f61ed3e2;
        address expectedCharlieEscrow = 0xCB6f5076b5bbae81D7643BfBf57897E8E3FB1db9;
        vm.expectEmit(address(dlgte));
        emit DelegateEscrowCreated(charlie, expectedCharlieEscrow);
        vm.expectEmit(address(dlgte));
        emit DelegationApplied(address(policy), alice, bob, charlie, 100e18);
        assertEq(
            dlgte.applyDelegations(
                alice, 
                0,
                oneDelegationRequest(bob, charlie, 100e18),
                DLGTEv1.AllowedDelegationRequests.Any
            ),
            100e18
        );
        assertEq(gohm.balanceOf(address(dlgte)), 0);
        assertEq(gohm.balanceOf(address(policy)), 0);
        assertEq(gohm.balanceOf(expectedBobEscrow), 0);
        assertEq(gohm.balanceOf(expectedCharlieEscrow), 100e18);
        verifyAccountSummary(address(policy), alice, 100e18, 100e18, 1, 10);
        verifyDelegationsOne(address(policy), alice, charlie, expectedCharlieEscrow, 100e18);
    }

    function test_applyDelegations_success_partialTransfer() public {
        seedDelegate();
        
        address expectedBobEscrow = 0x4f81992FCe2E1846dD528eC0102e6eE1f61ed3e2;
        address expectedCharlieEscrow = 0xCB6f5076b5bbae81D7643BfBf57897E8E3FB1db9;
        vm.expectEmit(address(dlgte));
        emit DelegateEscrowCreated(charlie, expectedCharlieEscrow);
        vm.expectEmit(address(dlgte));
        emit DelegationApplied(address(policy), alice, bob, charlie, 25e18);
        assertEq(
            dlgte.applyDelegations(
                alice, 
                0,
                oneDelegationRequest(bob, charlie, 25e18),
                DLGTEv1.AllowedDelegationRequests.Any
            ),
            100e18
        );
        assertEq(gohm.balanceOf(address(dlgte)), 0);
        assertEq(gohm.balanceOf(address(policy)), 0);
        assertEq(gohm.balanceOf(expectedBobEscrow), 75e18);
        assertEq(gohm.balanceOf(expectedCharlieEscrow), 25e18);
        verifyAccountSummary(address(policy), alice, 100e18, 100e18, 2, 10);
        verifyDelegationsTwo(
            address(policy), 
            alice, 
            bob, expectedBobEscrow, 75e18,
            charlie, expectedCharlieEscrow, 25e18
        );
    }
}

contract DLGTETestDelegationsMultipleDelegates is DLGTETestBase {
    using ModuleTestFixtureGenerator for OlympusGovDelegation;

    function test_fail_tooManyDelegates() public {
        vm.startPrank(policy);
        dlgte.setMaxDelegateAddresses(alice, 2);

        deal(address(gohm), address(policy), 100e18);
        gohm.approve(address(dlgte), 100e18);

        assertEq(
            dlgte.applyDelegations(
                alice, 
                100e18,
                oneDelegationRequest(address(0), bob, 50e18),
                DLGTEv1.AllowedDelegationRequests.Any
            ),
            50e18
        );
        assertEq(
            dlgte.applyDelegations(
                alice, 
                0,
                oneDelegationRequest(address(0), charlie, 25e18),
                DLGTEv1.AllowedDelegationRequests.Any
            ),
            75e18
        );

        address expectedBobEscrow = 0x4f81992FCe2E1846dD528eC0102e6eE1f61ed3e2;
        address expectedCharlieEscrow = 0xCB6f5076b5bbae81D7643BfBf57897E8E3FB1db9;
        verifyAccountSummary(address(policy), alice, 100e18, 75e18, 2, 2);
        verifyDelegationsTwo(
            address(policy), 
            alice, 
            bob, expectedBobEscrow, 50e18,
            charlie, expectedCharlieEscrow, 25e18
        );

        vm.expectRevert(abi.encodeWithSelector(DLGTEv1.DLGTE_TooManyDelegates.selector));
        dlgte.applyDelegations(
            alice, 
            0,
            oneDelegationRequest(address(0), daniel, 10e18),
            DLGTEv1.AllowedDelegationRequests.Any
        );
    }

    function test_multipleUsers_multiplePolicies() public {
        address policy2 = dlgte.generateGodmodeFixture(type(OlympusGovDelegation).name);
        kernel.executeAction(Actions.ActivatePolicy, policy2);

        // Add for policy 1
        {
            vm.startPrank(policy);
            deal(address(gohm), address(policy), 100e18);
            gohm.approve(address(dlgte), 100e18);
            dlgte.applyDelegations(
                alice, 
                25e18,
                oneDelegationRequest(address(0), bob, 25e18),
                DLGTEv1.AllowedDelegationRequests.Any
            );
            dlgte.applyDelegations(
                bob, 
                33e18,
                oneDelegationRequest(address(0), alice, 10e18),
                DLGTEv1.AllowedDelegationRequests.Any
            );
        }

        // Add again for policy 2
        {
            vm.startPrank(policy2);
            deal(address(gohm), address(policy2), 100e18);
            gohm.approve(address(dlgte), 100e18);
            dlgte.applyDelegations(
                alice, 
                25e18,
                oneDelegationRequest(address(0), bob, 25e18),
                DLGTEv1.AllowedDelegationRequests.Any
            );
            dlgte.applyDelegations(
                bob, 
                33e18,
                oneDelegationRequest(address(0), alice, 10e18),
                DLGTEv1.AllowedDelegationRequests.Any
            );
        }

        // Same escrow used for both
        address expectedBobEscrow = 0x4f81992FCe2E1846dD528eC0102e6eE1f61ed3e2;
        address expectedAliceEscrow = 0xCB6f5076b5bbae81D7643BfBf57897E8E3FB1db9;
        verifyAccountSummary(address(policy), alice, 25e18, 25e18, 1, 10);

        // note - see todo within accountDelegationsList()
        // The last number is the sum of all delegatation amounts to 
        // Bob (from Alice) across both policies
        verifyDelegationsOne(address(policy), alice, bob, expectedBobEscrow, 25e18 * 2);
        verifyAccountSummary(address(policy), bob, 33e18, 10e18, 1, 10);
        verifyDelegationsOne(address(policy), bob, alice, expectedAliceEscrow, 10e18 * 2);

        verifyAccountSummary(address(policy2), alice, 25e18, 25e18, 1, 10);
        verifyDelegationsOne(address(policy2), alice, bob, expectedBobEscrow, 25e18 * 2);
        verifyAccountSummary(address(policy2), bob, 33e18, 10e18, 1, 10);
        verifyDelegationsOne(address(policy2), bob, alice, expectedAliceEscrow, 10e18 * 2);

        assertEq(gohm.balanceOf(address(dlgte)), 46e18);
        assertEq(gohm.balanceOf(address(policy)), 42e18);
        assertEq(gohm.balanceOf(address(policy2)), 42e18);
        assertEq(gohm.balanceOf(expectedBobEscrow), 50e18);
        assertEq(gohm.balanceOf(expectedAliceEscrow), 20e18);
    }
}