// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Finite seed and invariant loops intentionally call real contracts.
// Literal amounts and endpoints are independent expected test values.
// Tests read state after calls to assert exact effects and rollback.
// Expected-revert calls and repeat-configuration probes discard their return values.
// forge-lint: disable-start(calls-loop, literal-instead-of-constant, reentrancy-no-eth, unused-return)

// Interfaces
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansPayout} from "src/policies/interfaces/burnerloans/IBurnerLoansPayout.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Libraries
import {SafeERC20} from "@openzeppelin-5.7.0/token/ERC20/utils/SafeERC20.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {BurnerLoansPayoutTest} from "./BurnerLoansPayoutTest.sol";
import {MockRevertingTransferToken} from "src/test/mocks/MockRevertingTransferToken.sol";

contract BurnerLoansPayoutRescuePendingPayoutTest is BurnerLoansPayoutTest {
    // Scenarios: BLCU-PENDING-RESCUE-L03.
    function test_givenInactivePayoutAndRolesUpgrade_whenFormerAdminCalls_thenBlockedUntilReactivation()
        public
        givenPendingBuckets
    {
        address formerAdmin = address(0xabc1);
        _rolesAdmin.grantRole(ADMIN_ROLE, formerAdmin);
        _setState(_payout, false, true);
        OlympusRoles next = new OlympusRoles(_kernel);
        _kernel.executeAction(Actions.UpgradeModule, address(next));
        _rolesAdmin.grantRole(ADMIN_ROLE, _destination);
        assertEq(address(_payout.ROLES()), address(_roles), "Inactive Payout retains old cache");
        assertTrue(_roles.hasRole(formerAdmin, ADMIN_ROLE), "Former ADMIN remains in old module");
        assertFalse(
            next.hasRole(formerAdmin, ADMIN_ROLE),
            "Former ADMIN absent from current module"
        );
        bytes32 state = _ledgerDigest();
        _expectInactivePayout();
        vm.prank(formerAdmin);
        _payout.rescuePendingPayout(address(_token), _keeper, _destination, 1);
        _expectInactivePayout();
        vm.prank(formerAdmin);
        _payout.setConfigOperator(formerAdmin);
        assertEq(_ledgerDigest(), state, "Stale authority cannot redirect funds");
        _kernel.executeAction(Actions.ActivatePolicy, address(_payout));
        assertEq(address(_payout.ROLES()), address(next), "Reactivation refreshes authority");
        vm.prank(_destination);
        _payout.rescuePendingPayout(address(_token), _keeper, _destination, 1);
        assertEq(_token.balanceOf(_destination), 1, "Current ADMIN recovers after reactivation");
        _assertBuckets(address(_token), _keeper, 10, 20, 29, 59);
    }

    struct RescueAllocation {
        address keeper;
        address recipient;
        address destination;
        uint256 fee;
        uint256 seized;
        uint256 reward;
        uint256 quantity;
        uint256 rewardDebit;
        uint256 feeDebit;
        uint256 seizedDebit;
    }

    // Scenarios: BLCU-PENDING-RESCUE-A01.
    function test_whenUnauthorizedRecovery_reverts(address caller_) public givenPendingBuckets {
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE) && caller_ != _payout.configOperator());
        bytes32 state = _ledgerDigest();
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        _payout.rescuePendingPayout(address(_token), _keeper, _destination, 1);
        assertEq(_ledgerDigest(), state, "Unauthorized redirect preserves all obligations");
    }

    // Scenarios: BLCU-PENDING-RESCUE-A01.
    function test_givenFormerController_whenRecovering_reverts() public {
        address former = _controller;
        _payout.setConfigOperator(_recipient);
        test_whenUnauthorizedRecovery_reverts(former);
    }

    // Scenarios: BLCU-PENDING-RESCUE-N01.
    function test_whenAmountZero_reverts(
        address caller_,
        bool operatorOnly_,
        bool overlap_
    ) public givenPendingBuckets {
        _grantRecoveryCaller(caller_, operatorOnly_, overlap_);
        _expectPendingRejected(
            abi.encodeWithSelector(IBurnerLoansCore.BurnerLoansCore_ZeroAmount.selector),
            caller_,
            address(_token),
            _keeper,
            _destination,
            0
        );
    }

    // Scenarios: BLCU-PENDING-RESCUE-N02.
    function test_whenAmountExceedsEntitlement_reverts(
        uint256 amount_,
        address caller_,
        bool operatorOnly_,
        bool overlap_
    ) public givenPendingBuckets {
        amount_ = bound(amount_, 31, type(uint256).max);
        _grantRecoveryCaller(caller_, operatorOnly_, overlap_);
        _expectPendingRejected(
            abi.encodeWithSelector(
                IBurnerLoansPayout.BurnerLoans_InsufficientPendingPayout.selector,
                address(_token),
                amount_,
                uint256(30)
            ),
            caller_,
            address(_token),
            _keeper,
            _destination,
            amount_
        );
    }

    // Scenarios: BLCU-PENDING-RESCUE-D01.
    function test_givenTransferReverts_whenRedirected_thenCompleteRollback(
        address caller_,
        bool operatorOnly_,
        bool overlap_
    ) public givenPendingBuckets {
        _grantRecoveryCaller(caller_, operatorOnly_, overlap_);
        _token.setTransferReverts(_destination, true);
        _expectPendingTransferRejected(
            abi.encodeWithSelector(
                MockRevertingTransferToken.TransferReverted.selector,
                _destination
            ),
            caller_
        );
    }

    // Scenarios: BLCU-PENDING-RESCUE-D02.
    function test_givenTransferReturnsFalse_whenRedirected_thenCompleteRollback(
        address caller_,
        bool operatorOnly_,
        bool overlap_
    ) public givenPendingBuckets {
        _grantRecoveryCaller(caller_, operatorOnly_, overlap_);
        vm.mockCall(
            address(_token),
            abi.encodeCall(_token.transfer, (_destination, uint256(30))),
            abi.encode(false)
        );
        _expectPendingTransferRejected(
            abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(_token)),
            caller_
        );
    }

    function _expectPendingRejected(
        bytes memory reason_,
        address caller_,
        address token_,
        address recipient_,
        address destination_,
        uint256 amount_
    ) internal {
        bytes32 state = _ledgerDigest();
        vm.expectRevert(reason_);
        vm.prank(caller_);
        _payout.previewRescuePendingPayout(token_, recipient_, destination_, amount_);
        vm.expectRevert(reason_);
        vm.prank(caller_);
        _payout.rescuePendingPayout(token_, recipient_, destination_, amount_);
        assertEq(
            _ledgerDigest(),
            state,
            "Rejected redirect preserves all reserves, balances and stored indexes"
        );
    }

    function _expectPendingTransferRejected(bytes memory reason_, address caller_) internal {
        bytes32 state = _ledgerDigest();
        vm.prank(caller_);
        assertEq(
            _payout.previewRescuePendingPayout(address(_token), _keeper, _destination, 30),
            30,
            "Preview quotes entitlement before token failure"
        );
        vm.expectRevert(reason_);
        vm.prank(caller_);
        _payout.rescuePendingPayout(address(_token), _keeper, _destination, 30);
        assertEq(_ledgerDigest(), state, "Strict transfer restores debits and removed indexes");
    }

    function _assertAllocation(RescueAllocation memory a_, address caller_) internal {
        _seedBuckets(a_.fee, a_.seized, a_.reward, a_.keeper);
        uint256 total = a_.fee + a_.seized + a_.reward;
        uint256 beforeDestination = _token.balanceOf(a_.destination);
        bytes32 other = _bucketDigest(address(_otherToken));
        bytes32 retired = _retiredDigest();
        vm.prank(caller_);
        assertEq(
            _payout.previewRescuePendingPayout(
                address(_token),
                a_.recipient,
                a_.destination,
                a_.quantity
            ),
            _allocationEntitlement(a_),
            "Preview returns full entitlement, not requested debit"
        );
        _token.setTransferReverts(a_.destination, false);
        if (a_.rewardDebit != 0) {
            vm.expectEmit(address(_payout));
            emit IBurnerLoansPayout.PendingSeizureRewardRescued(
                address(_token),
                a_.recipient,
                a_.destination,
                a_.rewardDebit
            );
        }
        if (a_.feeDebit != 0) {
            vm.expectEmit(address(_payout));
            emit IBurnerLoansPayout.PendingFeeRescued(address(_token), a_.destination, a_.feeDebit);
        }
        if (a_.seizedDebit != 0) {
            vm.expectEmit(address(_payout));
            emit IBurnerLoansPayout.PendingSeizureRescued(
                address(_token),
                a_.destination,
                a_.seizedDebit
            );
        }
        uint256 calls = _token.transferCallCount();
        vm.prank(caller_);
        _payout.rescuePendingPayout(address(_token), a_.recipient, a_.destination, a_.quantity);
        assertEq(_token.transferCallCount(), calls + 1, "Exactly one strict token transfer");
        _assertBuckets(
            address(_token),
            a_.keeper,
            a_.fee - a_.feeDebit,
            a_.seized - a_.seizedDebit,
            a_.reward - a_.rewardDebit,
            total - a_.quantity
        );
        assertEq(
            _token.balanceOf(a_.destination),
            beforeDestination + a_.quantity,
            "Exact destination delta"
        );
        assertEq(
            _token.balanceOf(address(_payout)),
            total - a_.quantity,
            "Balance and liabilities debit together"
        );
        assertEq(_bucketDigest(address(_otherToken)), other, "Other token isolated");
        assertEq(_retiredDigest(), retired, "Other Payout isolated");
    }

    // Scenarios: BLCU-PENDING-RESCUE-I01.
    function test_givenZeroToken_whenRecovered_reverts(
        address caller_,
        bool operatorOnly_,
        bool overlap_
    ) public givenPendingBuckets {
        _grantRecoveryCaller(caller_, operatorOnly_, overlap_);
        _expectPendingRejected(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_InvalidAsset.selector,
                address(0)
            ),
            caller_,
            address(0),
            _keeper,
            _destination,
            1
        );
    }

    // Scenarios: BLCU-PENDING-RESCUE-I02.
    function test_givenEoaToken_whenRecovered_reverts(
        address caller_,
        bool operatorOnly_,
        bool overlap_
    ) public givenPendingBuckets {
        _grantRecoveryCaller(caller_, operatorOnly_, overlap_);
        _expectPendingRejected(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_InvalidAsset.selector,
                _recipient
            ),
            caller_,
            _recipient,
            _keeper,
            _destination,
            1
        );
    }

    // Scenarios: BLCU-PENDING-RESCUE-I03.
    function test_givenZeroDestination_whenRecovered_reverts(
        address caller_,
        bool operatorOnly_,
        bool overlap_
    ) public givenPendingBuckets {
        _grantRecoveryCaller(caller_, operatorOnly_, overlap_);
        _expectPendingRejected(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_InvalidRescueDestination.selector,
                address(0)
            ),
            caller_,
            address(_token),
            _keeper,
            address(0),
            1
        );
    }

    // Scenarios: BLCU-PENDING-RESCUE-I04.
    function test_givenCoreDestination_whenRecovered_reverts(
        address caller_,
        bool operatorOnly_,
        bool overlap_
    ) public givenPendingBuckets {
        _grantRecoveryCaller(caller_, operatorOnly_, overlap_);
        _expectPendingRejected(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_InvalidRescueDestination.selector,
                address(_core)
            ),
            caller_,
            address(_token),
            _keeper,
            address(_core),
            1
        );
    }

    // Scenarios: BLCU-PENDING-RESCUE-I05.
    function test_givenSelfDestination_whenRecovered_reverts(
        address caller_,
        bool operatorOnly_,
        bool overlap_
    ) public givenPendingBuckets {
        _grantRecoveryCaller(caller_, operatorOnly_, overlap_);
        _expectPendingRejected(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_InvalidRescueDestination.selector,
                address(_payout)
            ),
            caller_,
            address(_token),
            _keeper,
            address(_payout),
            1
        );
    }

    // Scenarios: BLCU-PENDING-RESCUE-I06.
    function test_givenControllerDestination_whenRecovered_reverts(
        address caller_,
        bool operatorOnly_,
        bool overlap_
    ) public givenPendingBuckets {
        _grantRecoveryCaller(caller_, operatorOnly_, overlap_);
        _expectPendingRejected(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_InvalidRescueDestination.selector,
                _payout.configOperator()
            ),
            caller_,
            address(_token),
            _keeper,
            _payout.configOperator(),
            1
        );
    }

    // Scenarios: BLCU-PENDING-RESCUE-I07.
    function test_givenKernelDestination_whenRecovered_reverts(
        address caller_,
        bool operatorOnly_,
        bool overlap_
    ) public givenPendingBuckets {
        _grantRecoveryCaller(caller_, operatorOnly_, overlap_);
        _expectPendingRejected(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_InvalidRescueDestination.selector,
                address(_kernel)
            ),
            caller_,
            address(_token),
            _keeper,
            address(_kernel),
            1
        );
    }

    // Scenarios: BLCU-PENDING-RESCUE-I08.
    function test_givenTokenDestination_whenRecovered_reverts(
        address caller_,
        bool operatorOnly_,
        bool overlap_
    ) public givenPendingBuckets {
        _grantRecoveryCaller(caller_, operatorOnly_, overlap_);
        _expectPendingRejected(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_InvalidRescueDestination.selector,
                address(_token)
            ),
            caller_,
            address(_token),
            _keeper,
            address(_token),
            1
        );
    }

    // Scenarios: BLCU-PENDING-RESCUE-I09.
    function test_whenRecipientZero_reverts(
        address caller_,
        bool operatorOnly_,
        bool overlap_
    ) public givenPendingBuckets {
        _grantRecoveryCaller(caller_, operatorOnly_, overlap_);
        _expectPendingRejected(
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_ZeroAddress.selector),
            caller_,
            address(_token),
            address(0),
            _destination,
            1
        );
    }

    // Scenarios: BLCU-PENDING-RESCUE-N07, BLCU-PENDING-RESCUE-N03.
    function test_givenKeeperOnly_whenRedirected_thenExactAllocation(
        uint256 k_,
        uint256 q_,
        address caller_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        k_ = bound(k_, 1, type(uint256).max);
        q_ = bound(q_, 1, k_);
        _grantRecoveryCaller(caller_, operatorOnly_, overlap_);
        RescueAllocation memory allocation = RescueAllocation({
            keeper: _keeper,
            recipient: _keeper,
            destination: _destination,
            fee: 0,
            seized: 0,
            reward: k_,
            quantity: q_,
            rewardDebit: q_,
            feeDebit: 0,
            seizedDebit: 0
        });
        _assertAllocation(allocation, caller_);
    }

    // Scenarios: BLCU-PENDING-RESCUE-N07, BLCU-PENDING-RESCUE-N03.
    function test_givenKeeperOnly_whenQuantityAtIntervalSeeds_thenExactAllocation() public {
        uint256 checkpoint = vm.snapshotState();
        uint256[4] memory quantities = [uint256(1), 2, 6, 7];
        for (uint256 i; i < quantities.length; ++i) {
            test_givenKeeperOnly_whenRedirected_thenExactAllocation(
                7,
                quantities[i],
                address(0xabc1),
                false,
                false
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-PENDING-RESCUE-N08, BLCU-PENDING-RESCUE-N03.
    function test_givenFeeOnly_whenRedirected_thenExactAllocation(
        uint256 f_,
        uint256 q_,
        address caller_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        f_ = bound(f_, 1, type(uint256).max);
        q_ = bound(q_, 1, f_);
        _useDistributor();
        _grantRecoveryCaller(caller_, operatorOnly_, overlap_);
        RescueAllocation memory allocation = RescueAllocation({
            keeper: address(_distributor),
            recipient: address(_distributor),
            destination: _destination,
            fee: f_,
            seized: 0,
            reward: 0,
            quantity: q_,
            rewardDebit: 0,
            feeDebit: q_,
            seizedDebit: 0
        });
        _assertAllocation(allocation, caller_);
    }

    // Scenarios: BLCU-PENDING-RESCUE-N08.
    function test_givenFeeOnly_whenQuantityAtIntervalSeeds_thenExactAllocation() public {
        uint256 checkpoint = vm.snapshotState();
        uint256[4] memory quantities = [uint256(1), 2, 10, 11];
        for (uint256 i; i < quantities.length; ++i) {
            test_givenFeeOnly_whenRedirected_thenExactAllocation(
                11,
                quantities[i],
                address(0xabc1),
                false,
                false
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-PENDING-RESCUE-N09, BLCU-PENDING-RESCUE-N03.
    function test_givenSeizureOnly_whenRedirected_thenExactAllocation(
        uint256 s_,
        uint256 q_,
        address caller_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        s_ = bound(s_, 1, type(uint256).max);
        q_ = bound(q_, 1, s_);
        _grantRecoveryCaller(caller_, operatorOnly_, overlap_);
        RescueAllocation memory allocation = RescueAllocation({
            keeper: _treasury(),
            recipient: _treasury(),
            destination: _destination,
            fee: 0,
            seized: s_,
            reward: 0,
            quantity: q_,
            rewardDebit: 0,
            feeDebit: 0,
            seizedDebit: q_
        });
        _assertAllocation(allocation, caller_);
    }

    // Scenarios: BLCU-PENDING-RESCUE-N09.
    function test_givenSeizureOnly_whenQuantityAtIntervalSeeds_thenExactAllocation() public {
        uint256 checkpoint = vm.snapshotState();
        uint256[4] memory quantities = [uint256(1), 2, 12, 13];
        for (uint256 i; i < quantities.length; ++i) {
            test_givenSeizureOnly_whenRedirected_thenExactAllocation(
                13,
                quantities[i],
                address(0xabc1),
                false,
                false
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-PENDING-RESCUE-N10, BLCU-PENDING-RESCUE-N03.
    function test_givenKeeperAndFeeBeforeRewardDrained_whenRedirected_thenExactAllocation(
        uint256 k_,
        uint256 f_,
        uint256 q_,
        address caller_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        k_ = bound(k_, 1, type(uint256).max - 1);
        f_ = bound(f_, 1, type(uint256).max - k_);
        q_ = bound(q_, 1, k_);
        _useDistributor();
        _grantRecoveryCaller(caller_, operatorOnly_, overlap_);
        RescueAllocation memory allocation = RescueAllocation({
            keeper: address(_distributor),
            recipient: address(_distributor),
            destination: _destination,
            fee: f_,
            seized: 0,
            reward: k_,
            quantity: q_,
            rewardDebit: q_,
            feeDebit: 0,
            seizedDebit: 0
        });
        _assertAllocation(allocation, caller_);
    }

    // Scenarios: BLCU-PENDING-RESCUE-N10.
    function test_givenKeeperAndFeeBeforeRewardDrained_whenQuantityAtIntervalSeeds_thenExactAllocation()
        public
    {
        uint256 checkpoint = vm.snapshotState();
        uint256[4] memory quantities = [uint256(1), 2, 6, 7];
        for (uint256 i; i < quantities.length; ++i) {
            test_givenKeeperAndFeeBeforeRewardDrained_whenRedirected_thenExactAllocation(
                7,
                11,
                quantities[i],
                address(0xabc1),
                false,
                false
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-PENDING-RESCUE-N11, BLCU-PENDING-RESCUE-N03.
    function test_givenKeeperAndFeeAfterRewardDrained_whenRedirected_thenExactAllocation(
        uint256 k_,
        uint256 f_,
        uint256 q_,
        address caller_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        k_ = bound(k_, 1, type(uint256).max - 1);
        f_ = bound(f_, 1, type(uint256).max - k_);
        q_ = bound(q_, k_ + 1, k_ + f_);
        _useDistributor();
        _grantRecoveryCaller(caller_, operatorOnly_, overlap_);
        RescueAllocation memory allocation = RescueAllocation({
            keeper: address(_distributor),
            recipient: address(_distributor),
            destination: _destination,
            fee: f_,
            seized: 0,
            reward: k_,
            quantity: q_,
            rewardDebit: k_,
            feeDebit: q_ - k_,
            seizedDebit: 0
        });
        _assertAllocation(allocation, caller_);
    }

    // Scenarios: BLCU-PENDING-RESCUE-N11.
    function test_givenKeeperAndFeeAfterRewardDrained_whenQuantityAtIntervalSeeds_thenExactAllocation()
        public
    {
        uint256 checkpoint = vm.snapshotState();
        uint256[4] memory quantities = [uint256(8), 9, 17, 18];
        for (uint256 i; i < quantities.length; ++i) {
            test_givenKeeperAndFeeAfterRewardDrained_whenRedirected_thenExactAllocation(
                7,
                11,
                quantities[i],
                address(0xabc1),
                false,
                false
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-PENDING-RESCUE-N12, BLCU-PENDING-RESCUE-N03.
    function test_givenKeeperAndSeizureBeforeRewardDrained_whenRedirected_thenExactAllocation(
        uint256 k_,
        uint256 s_,
        uint256 q_,
        address caller_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        k_ = bound(k_, 1, type(uint256).max - 1);
        s_ = bound(s_, 1, type(uint256).max - k_);
        q_ = bound(q_, 1, k_);
        _useDistributor();
        _grantRecoveryCaller(caller_, operatorOnly_, overlap_);
        RescueAllocation memory allocation = RescueAllocation({
            keeper: _treasury(),
            recipient: _treasury(),
            destination: _destination,
            fee: 0,
            seized: s_,
            reward: k_,
            quantity: q_,
            rewardDebit: q_,
            feeDebit: 0,
            seizedDebit: 0
        });
        _assertAllocation(allocation, caller_);
    }

    // Scenarios: BLCU-PENDING-RESCUE-N12.
    function test_givenKeeperAndSeizureBeforeRewardDrained_whenQuantityAtIntervalSeeds_thenExactAllocation()
        public
    {
        uint256 checkpoint = vm.snapshotState();
        uint256[4] memory quantities = [uint256(1), 2, 6, 7];
        for (uint256 i; i < quantities.length; ++i) {
            test_givenKeeperAndSeizureBeforeRewardDrained_whenRedirected_thenExactAllocation(
                7,
                13,
                quantities[i],
                address(0xabc1),
                false,
                false
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-PENDING-RESCUE-N13, BLCU-PENDING-RESCUE-N03.
    function test_givenKeeperAndSeizureAfterRewardDrained_whenRedirected_thenExactAllocation(
        uint256 k_,
        uint256 s_,
        uint256 q_,
        address caller_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        k_ = bound(k_, 1, type(uint256).max - 1);
        s_ = bound(s_, 1, type(uint256).max - k_);
        q_ = bound(q_, k_ + 1, k_ + s_);
        _useDistributor();
        _grantRecoveryCaller(caller_, operatorOnly_, overlap_);
        RescueAllocation memory allocation = RescueAllocation({
            keeper: _treasury(),
            recipient: _treasury(),
            destination: _destination,
            fee: 0,
            seized: s_,
            reward: k_,
            quantity: q_,
            rewardDebit: k_,
            feeDebit: 0,
            seizedDebit: q_ - k_
        });
        _assertAllocation(allocation, caller_);
    }

    // Scenarios: BLCU-PENDING-RESCUE-N13.
    function test_givenKeeperAndSeizureAfterRewardDrained_whenQuantityAtIntervalSeeds_thenExactAllocation()
        public
    {
        uint256 checkpoint = vm.snapshotState();
        uint256[4] memory quantities = [uint256(8), 9, 19, 20];
        for (uint256 i; i < quantities.length; ++i) {
            test_givenKeeperAndSeizureAfterRewardDrained_whenRedirected_thenExactAllocation(
                7,
                13,
                quantities[i],
                address(0xabc1),
                false,
                false
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-PENDING-RESCUE-N14, BLCU-PENDING-RESCUE-N03.
    function test_givenFeeAndSeizureBeforeFeeDrained_whenRedirected_thenExactAllocation(
        uint256 f_,
        uint256 s_,
        uint256 q_,
        address caller_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        f_ = bound(f_, 1, type(uint256).max - 1);
        s_ = bound(s_, 1, type(uint256).max - f_);
        q_ = bound(q_, 1, f_);
        _grantRecoveryCaller(caller_, operatorOnly_, overlap_);
        RescueAllocation memory allocation = RescueAllocation({
            keeper: _treasury(),
            recipient: _treasury(),
            destination: _destination,
            fee: f_,
            seized: s_,
            reward: 0,
            quantity: q_,
            rewardDebit: 0,
            feeDebit: q_,
            seizedDebit: 0
        });
        _assertAllocation(allocation, caller_);
    }

    // Scenarios: BLCU-PENDING-RESCUE-N14.
    function test_givenFeeAndSeizureBeforeFeeDrained_whenQuantityAtIntervalSeeds_thenExactAllocation()
        public
    {
        uint256 checkpoint = vm.snapshotState();
        uint256[4] memory quantities = [uint256(1), 2, 10, 11];
        for (uint256 i; i < quantities.length; ++i) {
            test_givenFeeAndSeizureBeforeFeeDrained_whenRedirected_thenExactAllocation(
                11,
                13,
                quantities[i],
                address(0xabc1),
                false,
                false
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-PENDING-RESCUE-N15, BLCU-PENDING-RESCUE-N03.
    function test_givenFeeAndSeizureAfterFeeDrained_whenRedirected_thenExactAllocation(
        uint256 f_,
        uint256 s_,
        uint256 q_,
        address caller_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        f_ = bound(f_, 1, type(uint256).max - 1);
        s_ = bound(s_, 1, type(uint256).max - f_);
        q_ = bound(q_, f_ + 1, f_ + s_);
        _grantRecoveryCaller(caller_, operatorOnly_, overlap_);
        RescueAllocation memory allocation = RescueAllocation({
            keeper: _treasury(),
            recipient: _treasury(),
            destination: _destination,
            fee: f_,
            seized: s_,
            reward: 0,
            quantity: q_,
            rewardDebit: 0,
            feeDebit: f_,
            seizedDebit: q_ - f_
        });
        _assertAllocation(allocation, caller_);
    }

    // Scenarios: BLCU-PENDING-RESCUE-N15.
    function test_givenFeeAndSeizureAfterFeeDrained_whenQuantityAtIntervalSeeds_thenExactAllocation()
        public
    {
        uint256 checkpoint = vm.snapshotState();
        uint256[4] memory quantities = [uint256(12), 13, 23, 24];
        for (uint256 i; i < quantities.length; ++i) {
            test_givenFeeAndSeizureAfterFeeDrained_whenRedirected_thenExactAllocation(
                11,
                13,
                quantities[i],
                address(0xabc1),
                false,
                false
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-PENDING-RESCUE-N16, BLCU-PENDING-RESCUE-N03.
    function test_givenAllBucketsWithinReward_whenRedirected_thenExactAllocation(
        uint256 k_,
        uint256 f_,
        uint256 s_,
        uint256 q_,
        address caller_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        k_ = bound(k_, 1, type(uint256).max - 2);
        f_ = bound(f_, 1, type(uint256).max - k_ - 1);
        s_ = bound(s_, 1, type(uint256).max - k_ - f_);
        q_ = bound(q_, 1, k_);
        _grantRecoveryCaller(caller_, operatorOnly_, overlap_);
        RescueAllocation memory allocation = RescueAllocation({
            keeper: _treasury(),
            recipient: _treasury(),
            destination: _destination,
            fee: f_,
            seized: s_,
            reward: k_,
            quantity: q_,
            rewardDebit: q_,
            feeDebit: 0,
            seizedDebit: 0
        });
        _assertAllocation(allocation, caller_);
    }

    // Scenarios: BLCU-PENDING-RESCUE-N16.
    function test_givenAllBucketsWithinReward_whenQuantityAtIntervalSeeds_thenExactAllocation()
        public
    {
        uint256 checkpoint = vm.snapshotState();
        uint256[4] memory quantities = [uint256(1), 2, 6, 7];
        for (uint256 i; i < quantities.length; ++i) {
            test_givenAllBucketsWithinReward_whenRedirected_thenExactAllocation(
                7,
                11,
                13,
                quantities[i],
                address(0xabc1),
                false,
                false
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-PENDING-RESCUE-N17, BLCU-PENDING-RESCUE-N03.
    function test_givenAllBucketsWithinFee_whenRedirected_thenExactAllocation(
        uint256 k_,
        uint256 f_,
        uint256 s_,
        uint256 q_,
        address caller_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        k_ = bound(k_, 1, type(uint256).max - 2);
        f_ = bound(f_, 1, type(uint256).max - k_ - 1);
        s_ = bound(s_, 1, type(uint256).max - k_ - f_);
        q_ = bound(q_, k_ + 1, k_ + f_);
        _grantRecoveryCaller(caller_, operatorOnly_, overlap_);
        RescueAllocation memory allocation = RescueAllocation({
            keeper: _treasury(),
            recipient: _treasury(),
            destination: _destination,
            fee: f_,
            seized: s_,
            reward: k_,
            quantity: q_,
            rewardDebit: k_,
            feeDebit: q_ - k_,
            seizedDebit: 0
        });
        _assertAllocation(allocation, caller_);
    }

    // Scenarios: BLCU-PENDING-RESCUE-N17.
    function test_givenAllBucketsWithinFee_whenQuantityAtIntervalSeeds_thenExactAllocation()
        public
    {
        uint256 checkpoint = vm.snapshotState();
        uint256[4] memory quantities = [uint256(8), 9, 17, 18];
        for (uint256 i; i < quantities.length; ++i) {
            test_givenAllBucketsWithinFee_whenRedirected_thenExactAllocation(
                7,
                11,
                13,
                quantities[i],
                address(0xabc1),
                false,
                false
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-PENDING-RESCUE-N18, BLCU-PENDING-RESCUE-N03.
    function test_givenAllBucketsWithinSeizure_whenRedirected_thenExactAllocation(
        uint256 k_,
        uint256 f_,
        uint256 s_,
        uint256 q_,
        address caller_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        k_ = bound(k_, 1, type(uint256).max - 2);
        f_ = bound(f_, 1, type(uint256).max - k_ - 1);
        s_ = bound(s_, 1, type(uint256).max - k_ - f_);
        q_ = bound(q_, k_ + f_ + 1, k_ + f_ + s_);
        _grantRecoveryCaller(caller_, operatorOnly_, overlap_);
        RescueAllocation memory allocation = RescueAllocation({
            keeper: _treasury(),
            recipient: _treasury(),
            destination: _destination,
            fee: f_,
            seized: s_,
            reward: k_,
            quantity: q_,
            rewardDebit: k_,
            feeDebit: f_,
            seizedDebit: q_ - k_ - f_
        });
        _assertAllocation(allocation, caller_);
    }

    // Scenarios: BLCU-PENDING-RESCUE-N18.
    function test_givenAllBucketsWithinSeizure_whenQuantityAtIntervalSeeds_thenExactAllocation()
        public
    {
        uint256 checkpoint = vm.snapshotState();
        uint256[4] memory quantities = [uint256(19), 20, 30, 31];
        for (uint256 i; i < quantities.length; ++i) {
            test_givenAllBucketsWithinSeizure_whenRedirected_thenExactAllocation(
                7,
                11,
                13,
                quantities[i],
                address(0xabc1),
                false,
                false
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-PENDING-RESCUE-P01.
    function test_whenDestinationIsOriginalRecipient_thenOwnershipPreserved(
        uint256 quantity_,
        address caller_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        quantity_ = bound(quantity_, 1, 30);
        _grantRecoveryCaller(caller_, operatorOnly_, overlap_);
        _assertAllocation(
            RescueAllocation({
                keeper: _keeper,
                recipient: _keeper,
                destination: _keeper,
                fee: 0,
                seized: 0,
                reward: 30,
                quantity: quantity_,
                rewardDebit: quantity_,
                feeDebit: 0,
                seizedDebit: 0
            }),
            caller_
        );
    }

    // Scenarios: BLCU-PENDING-RESCUE-P02.
    function test_whenDestinationIsDistinctWithExistingBalance_thenOnlyBalanceIncreases(
        address destination_,
        address caller_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        _grantRecoveryCaller(caller_, operatorOnly_, overlap_);
        vm.assume(
            destination_ != address(0) &&
                destination_ != address(_token) &&
                destination_ != address(_payout) &&
                destination_ != address(_core) &&
                destination_ != address(_kernel) &&
                destination_ != _payout.configOperator() &&
                destination_ != _keeper &&
                destination_ != address(_otherPayout)
        );
        _token.mint(destination_, 5);
        _assertAllocation(
            RescueAllocation({
                keeper: _keeper,
                recipient: _keeper,
                destination: destination_,
                fee: 0,
                seized: 0,
                reward: 30,
                quantity: 7,
                rewardDebit: 7,
                feeDebit: 0,
                seizedDebit: 0
            }),
            caller_
        );
        assertEq(
            _subject.keeperReward(address(_token), destination_),
            0,
            "Destination receives no new claim"
        );
    }

    // Scenarios: BLCU-PENDING-RESCUE-P02.
    function test_whenDestinationIsContract_thenExistingBalancePreserved() public {
        test_whenDestinationIsDistinctWithExistingBalance_thenOnlyBalanceIncreases(
            address(_asset),
            address(0xabc1),
            false,
            false
        );
    }

    // Scenarios: BLCU-PENDING-RESCUE-P03, BLCU-PENDING-RESCUE-P04, BLCU-PENDING-RESCUE-P07.
    function test_givenThreeKeepersAndTwoTokens_whenPartialKeeperRescued_thenIsolation(
        uint256 quantity_,
        address caller_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        quantity_ = bound(quantity_, 1, 29);
        _grantRecoveryCaller(caller_, operatorOnly_, overlap_);
        _assertIsolatedRedirect(quantity_, caller_);
    }

    // Scenarios: BLCU-PENDING-RESCUE-P03, BLCU-PENDING-RESCUE-P05, BLCU-PENDING-RESCUE-P07.
    function test_givenOtherObligations_whenKeeperFullyRescued_thenOnlyItsIndexRemoved(
        address caller_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        _grantRecoveryCaller(caller_, operatorOnly_, overlap_);
        _assertIsolatedRedirect(30, caller_);
    }

    function _assertIsolatedRedirect(uint256 quantity_, address caller_) internal {
        _seedBuckets(10, 20, 30, _keeper);
        _deferSeizure(_token, _secondKeeper, 7, 0);
        _deferSeizure(_token, _thirdKeeper, 9, 0);
        _deferFee(_otherToken, 11);
        _token.mint(address(_payout), 17);
        _token.mint(_secondKeeper, 5);
        bytes32 other = _bucketDigest(address(_otherToken));
        _token.setTransferReverts(_secondKeeper, false);
        vm.prank(caller_);
        assertEq(
            _payout.previewRescuePendingPayout(address(_token), _keeper, _secondKeeper, quantity_),
            30,
            "Only original keeper's full entitlement quoted"
        );
        vm.prank(caller_);
        _payout.rescuePendingPayout(address(_token), _keeper, _secondKeeper, quantity_);
        _assertBuckets(address(_token), _keeper, 10, 20, 30 - quantity_, 76 - quantity_);
        assertEq(
            _subject.keeperReward(address(_token), _secondKeeper),
            7,
            "Destination's old claim unchanged"
        );
        assertEq(_subject.keeperReward(address(_token), _thirdKeeper), 9, "Third keeper isolated");
        assertTrue(
            _subject.hasPendingKeeper(address(_token), _secondKeeper),
            "Destination remains indexed for its own old claim"
        );
        assertTrue(
            _subject.hasPendingKeeper(address(_token), _thirdKeeper),
            "Third keeper remains indexed"
        );
        assertEq(
            _token.balanceOf(_secondKeeper),
            5 + quantity_,
            "Destination delta is the exact debit"
        );
        assertEq(
            _token.balanceOf(address(_payout)),
            93 - quantity_,
            "Donation 17 remains above backing"
        );
        assertEq(_bucketDigest(address(_otherToken)), other, "Other token untouched");
    }

    // Scenarios: BLCU-PENDING-RESCUE-L01.
    function test_givenPayoutActive_whenPendingRescued_thenRetiredClaimsAvailable(
        address caller_,
        bool operatorOnly_,
        bool overlap_,
        bool enabled_,
        bool coreActive_,
        bool coreEnabled_
    ) public givenPendingBuckets {
        _grantRecoveryCaller(caller_, operatorOnly_, overlap_);
        _core.setPayout(address(_otherPayout));
        _setState(_payout, true, enabled_);
        _setState(_core, coreActive_, coreEnabled_);
        vm.prank(caller_);
        assertEq(
            _payout.previewRescuePendingPayout(address(_token), _keeper, _destination, 1),
            30,
            "Retired entitlement quoted"
        );
        vm.prank(caller_);
        _payout.rescuePendingPayout(address(_token), _keeper, _destination, 1);
        _assertBuckets(address(_token), _keeper, 10, 20, 29, 59);
        assertEq(_token.balanceOf(_destination), 1, "Active paused recovery remains available");
    }

    // Scenarios: BLCU-PENDING-RESCUE-N03, BLCU-PENDING-RESCUE-P06.
    function test_whenMaximumEntitlementFullyRescued_thenMaximumDebitAndCompleteCleanup() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenKeeperOnly_whenRedirected_thenExactAllocation(
            type(uint256).max,
            type(uint256).max,
            address(0xabc1),
            false,
            false
        );
        _restore(checkpoint);
        test_givenFeeOnly_whenRedirected_thenExactAllocation(
            type(uint256).max,
            type(uint256).max,
            address(0xabc2),
            true,
            false
        );
        _restore(checkpoint);
        test_givenSeizureOnly_whenRedirected_thenExactAllocation(
            type(uint256).max,
            type(uint256).max,
            address(0xabc3),
            false,
            true
        );
        _restore(checkpoint);
        test_givenAllBucketsWithinSeizure_whenRedirected_thenExactAllocation(
            type(uint256).max - 2,
            1,
            1,
            type(uint256).max,
            address(0xabc1),
            false,
            false
        );
    }

    // Scenarios: BLCU-PENDING-RESCUE-N02.
    function test_whenExcessAtIntervalEndpoints_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        test_whenAmountExceedsEntitlement_reverts(31, address(0xabc1), false, false);
        _restore(checkpoint);
        test_whenAmountExceedsEntitlement_reverts(type(uint256).max, address(0xabc2), true, false);
    }

    // Scenarios: BLCU-PENDING-RESCUE-N01.
    function test_givenEachRecoveryRole_whenAmountZero_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        RecoveryCaller[3] memory callers = _recoveryCallers();
        for (uint256 i; i < callers.length; ++i) {
            test_whenAmountZero_reverts(
                callers[i].account,
                callers[i].operatorOnly,
                callers[i].overlap
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-PENDING-RESCUE-N02.
    function test_givenEachRecoveryRole_whenAmountExceedsEntitlement_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        RecoveryCaller[3] memory callers = _recoveryCallers();
        for (uint256 i; i < callers.length; ++i) {
            test_whenAmountExceedsEntitlement_reverts(
                5,
                callers[i].account,
                callers[i].operatorOnly,
                callers[i].overlap
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-PENDING-RESCUE-D01.
    function test_givenTransferReverts_givenEachRecoveryRole_whenRedirected_thenCompleteRollback()
        public
    {
        uint256 checkpoint = vm.snapshotState();
        RecoveryCaller[3] memory callers = _recoveryCallers();
        for (uint256 i; i < callers.length; ++i) {
            test_givenTransferReverts_whenRedirected_thenCompleteRollback(
                callers[i].account,
                callers[i].operatorOnly,
                callers[i].overlap
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-PENDING-RESCUE-D02.
    function test_givenTransferReturnsFalse_givenEachRecoveryRole_whenRedirected_thenCompleteRollback()
        public
    {
        uint256 checkpoint = vm.snapshotState();
        RecoveryCaller[3] memory callers = _recoveryCallers();
        for (uint256 i; i < callers.length; ++i) {
            test_givenTransferReturnsFalse_whenRedirected_thenCompleteRollback(
                callers[i].account,
                callers[i].operatorOnly,
                callers[i].overlap
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-PENDING-RESCUE-I01.
    function test_givenZeroToken_givenEachRecoveryRole_whenRecovered_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        RecoveryCaller[3] memory callers = _recoveryCallers();
        for (uint256 i; i < callers.length; ++i) {
            test_givenZeroToken_whenRecovered_reverts(
                callers[i].account,
                callers[i].operatorOnly,
                callers[i].overlap
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-PENDING-RESCUE-I02.
    function test_givenEoaToken_givenEachRecoveryRole_whenRecovered_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        RecoveryCaller[3] memory callers = _recoveryCallers();
        for (uint256 i; i < callers.length; ++i) {
            test_givenEoaToken_whenRecovered_reverts(
                callers[i].account,
                callers[i].operatorOnly,
                callers[i].overlap
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-PENDING-RESCUE-I03.
    function test_givenZeroDestination_givenEachRecoveryRole_whenRecovered_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        RecoveryCaller[3] memory callers = _recoveryCallers();
        for (uint256 i; i < callers.length; ++i) {
            test_givenZeroDestination_whenRecovered_reverts(
                callers[i].account,
                callers[i].operatorOnly,
                callers[i].overlap
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-PENDING-RESCUE-I04.
    function test_givenCoreDestination_givenEachRecoveryRole_whenRecovered_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        RecoveryCaller[3] memory callers = _recoveryCallers();
        for (uint256 i; i < callers.length; ++i) {
            test_givenCoreDestination_whenRecovered_reverts(
                callers[i].account,
                callers[i].operatorOnly,
                callers[i].overlap
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-PENDING-RESCUE-I05.
    function test_givenSelfDestination_givenEachRecoveryRole_whenRecovered_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        RecoveryCaller[3] memory callers = _recoveryCallers();
        for (uint256 i; i < callers.length; ++i) {
            test_givenSelfDestination_whenRecovered_reverts(
                callers[i].account,
                callers[i].operatorOnly,
                callers[i].overlap
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-PENDING-RESCUE-I06.
    function test_givenControllerDestination_givenEachRecoveryRole_whenRecovered_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        RecoveryCaller[3] memory callers = _recoveryCallers();
        for (uint256 i; i < callers.length; ++i) {
            test_givenControllerDestination_whenRecovered_reverts(
                callers[i].account,
                callers[i].operatorOnly,
                callers[i].overlap
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-PENDING-RESCUE-I07.
    function test_givenKernelDestination_givenEachRecoveryRole_whenRecovered_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        RecoveryCaller[3] memory callers = _recoveryCallers();
        for (uint256 i; i < callers.length; ++i) {
            test_givenKernelDestination_whenRecovered_reverts(
                callers[i].account,
                callers[i].operatorOnly,
                callers[i].overlap
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-PENDING-RESCUE-I08.
    function test_givenTokenDestination_givenEachRecoveryRole_whenRecovered_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        RecoveryCaller[3] memory callers = _recoveryCallers();
        for (uint256 i; i < callers.length; ++i) {
            test_givenTokenDestination_whenRecovered_reverts(
                callers[i].account,
                callers[i].operatorOnly,
                callers[i].overlap
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-PENDING-RESCUE-I09.
    function test_givenEachRecoveryRole_whenRecipientZero_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        RecoveryCaller[3] memory callers = _recoveryCallers();
        for (uint256 i; i < callers.length; ++i) {
            test_whenRecipientZero_reverts(
                callers[i].account,
                callers[i].operatorOnly,
                callers[i].overlap
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-PENDING-RESCUE-N07.
    function test_givenKeeperOnly_givenEachRecoveryRole_whenRedirected_thenExactAllocation()
        public
    {
        uint256 checkpoint = vm.snapshotState();
        RecoveryCaller[3] memory callers = _recoveryCallers();
        for (uint256 i; i < callers.length; ++i) {
            test_givenKeeperOnly_whenRedirected_thenExactAllocation(
                7,
                5,
                callers[i].account,
                callers[i].operatorOnly,
                callers[i].overlap
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-PENDING-RESCUE-N08.
    function test_givenFeeOnly_givenEachRecoveryRole_whenRedirected_thenExactAllocation() public {
        uint256 checkpoint = vm.snapshotState();
        RecoveryCaller[3] memory callers = _recoveryCallers();
        for (uint256 i; i < callers.length; ++i) {
            test_givenFeeOnly_whenRedirected_thenExactAllocation(
                11,
                5,
                callers[i].account,
                callers[i].operatorOnly,
                callers[i].overlap
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-PENDING-RESCUE-N09.
    function test_givenSeizureOnly_givenEachRecoveryRole_whenRedirected_thenExactAllocation()
        public
    {
        uint256 checkpoint = vm.snapshotState();
        RecoveryCaller[3] memory callers = _recoveryCallers();
        for (uint256 i; i < callers.length; ++i) {
            test_givenSeizureOnly_whenRedirected_thenExactAllocation(
                13,
                5,
                callers[i].account,
                callers[i].operatorOnly,
                callers[i].overlap
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-PENDING-RESCUE-N10.
    function test_givenKeeperAndFeeBeforeRewardDrained_givenEachRecoveryRole_whenRedirected_thenExactAllocation()
        public
    {
        uint256 checkpoint = vm.snapshotState();
        RecoveryCaller[3] memory callers = _recoveryCallers();
        for (uint256 i; i < callers.length; ++i) {
            test_givenKeeperAndFeeBeforeRewardDrained_whenRedirected_thenExactAllocation(
                7,
                11,
                5,
                callers[i].account,
                callers[i].operatorOnly,
                callers[i].overlap
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-PENDING-RESCUE-N11.
    function test_givenKeeperAndFeeAfterRewardDrained_givenEachRecoveryRole_whenRedirected_thenExactAllocation()
        public
    {
        uint256 checkpoint = vm.snapshotState();
        RecoveryCaller[3] memory callers = _recoveryCallers();
        for (uint256 i; i < callers.length; ++i) {
            test_givenKeeperAndFeeAfterRewardDrained_whenRedirected_thenExactAllocation(
                7,
                11,
                5,
                callers[i].account,
                callers[i].operatorOnly,
                callers[i].overlap
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-PENDING-RESCUE-N12.
    function test_givenKeeperAndSeizureBeforeRewardDrained_givenEachRecoveryRole_whenRedirected_thenExactAllocation()
        public
    {
        uint256 checkpoint = vm.snapshotState();
        RecoveryCaller[3] memory callers = _recoveryCallers();
        for (uint256 i; i < callers.length; ++i) {
            test_givenKeeperAndSeizureBeforeRewardDrained_whenRedirected_thenExactAllocation(
                7,
                13,
                5,
                callers[i].account,
                callers[i].operatorOnly,
                callers[i].overlap
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-PENDING-RESCUE-N13.
    function test_givenKeeperAndSeizureAfterRewardDrained_givenEachRecoveryRole_whenRedirected_thenExactAllocation()
        public
    {
        uint256 checkpoint = vm.snapshotState();
        RecoveryCaller[3] memory callers = _recoveryCallers();
        for (uint256 i; i < callers.length; ++i) {
            test_givenKeeperAndSeizureAfterRewardDrained_whenRedirected_thenExactAllocation(
                7,
                13,
                5,
                callers[i].account,
                callers[i].operatorOnly,
                callers[i].overlap
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-PENDING-RESCUE-N14.
    function test_givenFeeAndSeizureBeforeFeeDrained_givenEachRecoveryRole_whenRedirected_thenExactAllocation()
        public
    {
        uint256 checkpoint = vm.snapshotState();
        RecoveryCaller[3] memory callers = _recoveryCallers();
        for (uint256 i; i < callers.length; ++i) {
            test_givenFeeAndSeizureBeforeFeeDrained_whenRedirected_thenExactAllocation(
                11,
                13,
                5,
                callers[i].account,
                callers[i].operatorOnly,
                callers[i].overlap
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-PENDING-RESCUE-N15.
    function test_givenFeeAndSeizureAfterFeeDrained_givenEachRecoveryRole_whenRedirected_thenExactAllocation()
        public
    {
        uint256 checkpoint = vm.snapshotState();
        RecoveryCaller[3] memory callers = _recoveryCallers();
        for (uint256 i; i < callers.length; ++i) {
            test_givenFeeAndSeizureAfterFeeDrained_whenRedirected_thenExactAllocation(
                11,
                13,
                5,
                callers[i].account,
                callers[i].operatorOnly,
                callers[i].overlap
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-PENDING-RESCUE-N16.
    function test_givenAllBucketsWithinReward_givenEachRecoveryRole_whenRedirected_thenExactAllocation()
        public
    {
        uint256 checkpoint = vm.snapshotState();
        RecoveryCaller[3] memory callers = _recoveryCallers();
        for (uint256 i; i < callers.length; ++i) {
            test_givenAllBucketsWithinReward_whenRedirected_thenExactAllocation(
                7,
                11,
                13,
                5,
                callers[i].account,
                callers[i].operatorOnly,
                callers[i].overlap
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-PENDING-RESCUE-N17.
    function test_givenAllBucketsWithinFee_givenEachRecoveryRole_whenRedirected_thenExactAllocation()
        public
    {
        uint256 checkpoint = vm.snapshotState();
        RecoveryCaller[3] memory callers = _recoveryCallers();
        for (uint256 i; i < callers.length; ++i) {
            test_givenAllBucketsWithinFee_whenRedirected_thenExactAllocation(
                7,
                11,
                13,
                5,
                callers[i].account,
                callers[i].operatorOnly,
                callers[i].overlap
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-PENDING-RESCUE-N18.
    function test_givenAllBucketsWithinSeizure_givenEachRecoveryRole_whenRedirected_thenExactAllocation()
        public
    {
        uint256 checkpoint = vm.snapshotState();
        RecoveryCaller[3] memory callers = _recoveryCallers();
        for (uint256 i; i < callers.length; ++i) {
            test_givenAllBucketsWithinSeizure_whenRedirected_thenExactAllocation(
                7,
                11,
                13,
                5,
                callers[i].account,
                callers[i].operatorOnly,
                callers[i].overlap
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-PENDING-RESCUE-P01.
    function test_givenEachRecoveryRole_whenDestinationIsOriginalRecipient_thenOwnershipPreserved()
        public
    {
        uint256 checkpoint = vm.snapshotState();
        RecoveryCaller[3] memory callers = _recoveryCallers();
        for (uint256 i; i < callers.length; ++i) {
            test_whenDestinationIsOriginalRecipient_thenOwnershipPreserved(
                5,
                callers[i].account,
                callers[i].operatorOnly,
                callers[i].overlap
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-PENDING-RESCUE-P02.
    function test_givenEachRecoveryRole_whenDestinationIsDistinctWithExistingBalance_thenOnlyBalanceIncreases()
        public
    {
        uint256 checkpoint = vm.snapshotState();
        RecoveryCaller[3] memory callers = _recoveryCallers();
        for (uint256 i; i < callers.length; ++i) {
            test_whenDestinationIsDistinctWithExistingBalance_thenOnlyBalanceIncreases(
                address(_asset),
                callers[i].account,
                callers[i].operatorOnly,
                callers[i].overlap
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-PENDING-RESCUE-P03, BLCU-PENDING-RESCUE-P04, BLCU-PENDING-RESCUE-P07.
    function test_givenThreeKeepersAndTwoTokens_givenEachRecoveryRole_whenPartialKeeperRescued_thenIsolation()
        public
    {
        uint256 checkpoint = vm.snapshotState();
        RecoveryCaller[3] memory callers = _recoveryCallers();
        for (uint256 i; i < callers.length; ++i) {
            test_givenThreeKeepersAndTwoTokens_whenPartialKeeperRescued_thenIsolation(
                5,
                callers[i].account,
                callers[i].operatorOnly,
                callers[i].overlap
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-PENDING-RESCUE-P03, BLCU-PENDING-RESCUE-P05, BLCU-PENDING-RESCUE-P07.
    function test_givenOtherObligations_givenEachRecoveryRole_whenKeeperFullyRescued_thenOnlyItsIndexRemoved()
        public
    {
        uint256 checkpoint = vm.snapshotState();
        RecoveryCaller[3] memory callers = _recoveryCallers();
        for (uint256 i; i < callers.length; ++i) {
            test_givenOtherObligations_whenKeeperFullyRescued_thenOnlyItsIndexRemoved(
                callers[i].account,
                callers[i].operatorOnly,
                callers[i].overlap
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-PENDING-RESCUE-L01.
    function test_givenPayoutActive_givenEachRecoveryRole_whenPendingRescued_thenRetiredClaimsAvailable()
        public
    {
        uint256 checkpoint = vm.snapshotState();
        RecoveryCaller[3] memory callers = _recoveryCallers();
        for (uint256 i; i < callers.length; ++i) {
            test_givenPayoutActive_whenPendingRescued_thenRetiredClaimsAvailable(
                callers[i].account,
                callers[i].operatorOnly,
                callers[i].overlap,
                true,
                true,
                true
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-PENDING-RESCUE-L01.
    function test_givenPayoutActive_whenEveryCoreAndEnabledState_thenRecoveryAvailable() public {
        uint256 checkpoint = vm.snapshotState();

        for (uint256 enabled; enabled < 2; ++enabled) {
            for (uint256 coreActive; coreActive < 2; ++coreActive) {
                for (uint256 coreEnabled; coreEnabled < 2; ++coreEnabled) {
                    test_givenPayoutActive_whenPendingRescued_thenRetiredClaimsAvailable(
                        address(0xabc1),
                        false,
                        false,
                        enabled != 0,
                        coreActive != 0,
                        coreEnabled != 0
                    );
                    _restore(checkpoint);
                }
            }
        }
    }

    function _assertDistinctKeeperRedirect(uint256 fee_, uint256 seized_) internal {
        _useDistributor();
        _assertAllocation(
            RescueAllocation({
                keeper: _keeper,
                recipient: _keeper,
                destination: _destination,
                fee: fee_,
                seized: seized_,
                reward: 30,
                quantity: 30,
                rewardDebit: 30,
                feeDebit: 0,
                seizedDebit: 0
            }),
            address(this)
        );
    }

    function _allocationEntitlement(
        RescueAllocation memory a_
    ) internal view returns (uint256 amount) {
        if (a_.recipient == a_.keeper) amount += a_.reward;
        if (a_.recipient == _feeRecipient()) amount += a_.fee;
        if (a_.recipient == _treasury()) amount += a_.seized;
    }

    function test_givenDistinctKeeper_givenKeeper_whenFullEntitlementRedirected_thenOnlyEligibleBucketsDebit()
        public
    {
        _assertDistinctKeeperRedirect(0, 0);
    }

    // Scenarios: BLCU-PENDING-RESCUE-N02.
    function test_givenDistinctKeeper_givenFee_whenNoEligibleEntitlement_reverts() public {
        _useDistributor();
        _seedBuckets(10, 0, 0, _keeper);
        _expectPendingRejected(
            abi.encodeWithSelector(
                IBurnerLoansPayout.BurnerLoans_InsufficientPendingPayout.selector,
                address(_token),
                uint256(1),
                uint256(0)
            ),
            address(this),
            address(_token),
            _keeper,
            _destination,
            1
        );
    }

    // Scenarios: BLCU-PENDING-RESCUE-N02.
    function test_givenDistinctKeeper_givenSeizure_whenNoEligibleEntitlement_reverts() public {
        _useDistributor();
        _seedBuckets(0, 20, 0, _keeper);
        _expectPendingRejected(
            abi.encodeWithSelector(
                IBurnerLoansPayout.BurnerLoans_InsufficientPendingPayout.selector,
                address(_token),
                uint256(1),
                uint256(0)
            ),
            address(this),
            address(_token),
            _keeper,
            _destination,
            1
        );
    }

    function test_givenDistinctKeeper_givenKeeperFee_whenFullEntitlementRedirected_thenOnlyEligibleBucketsDebit()
        public
    {
        _assertDistinctKeeperRedirect(10, 0);
    }

    function test_givenDistinctKeeper_givenKeeperSeizure_whenFullEntitlementRedirected_thenOnlyEligibleBucketsDebit()
        public
    {
        _assertDistinctKeeperRedirect(0, 20);
    }

    // Scenarios: BLCU-PENDING-RESCUE-N02.
    function test_givenDistinctKeeper_givenFeeSeizure_whenNoEligibleEntitlement_reverts() public {
        _useDistributor();
        _seedBuckets(10, 20, 0, _keeper);
        _expectPendingRejected(
            abi.encodeWithSelector(
                IBurnerLoansPayout.BurnerLoans_InsufficientPendingPayout.selector,
                address(_token),
                uint256(1),
                uint256(0)
            ),
            address(this),
            address(_token),
            _keeper,
            _destination,
            1
        );
    }

    function test_givenDistinctKeeper_givenAllBuckets_whenFullEntitlementRedirected_thenOnlyEligibleBucketsDebit()
        public
    {
        _assertDistinctKeeperRedirect(10, 20);
    }

    function test_givenKeeperEqualsFee_givenKeeper_whenFullEntitlementRedirected_thenOnlyEligibleBucketsDebit()
        public
    {
        _useDistributor();
        _assertAllocation(
            RescueAllocation({
                keeper: address(_distributor),
                recipient: address(_distributor),
                destination: _destination,
                fee: 0,
                seized: 0,
                reward: 30,
                quantity: 30,
                rewardDebit: 30,
                feeDebit: 0,
                seizedDebit: 0
            }),
            address(this)
        );
    }

    function test_givenKeeperEqualsFee_givenFee_whenFullEntitlementRedirected_thenOnlyEligibleBucketsDebit()
        public
    {
        _useDistributor();
        _assertAllocation(
            RescueAllocation({
                keeper: address(_distributor),
                recipient: address(_distributor),
                destination: _destination,
                fee: 10,
                seized: 0,
                reward: 0,
                quantity: 10,
                rewardDebit: 0,
                feeDebit: 10,
                seizedDebit: 0
            }),
            address(this)
        );
    }

    // Scenarios: BLCU-PENDING-RESCUE-N02.
    function test_givenKeeperEqualsFee_givenSeizure_whenNoEligibleEntitlement_reverts() public {
        _useDistributor();
        _seedBuckets(0, 20, 0, address(_distributor));
        _expectPendingRejected(
            abi.encodeWithSelector(
                IBurnerLoansPayout.BurnerLoans_InsufficientPendingPayout.selector,
                address(_token),
                uint256(1),
                uint256(0)
            ),
            address(this),
            address(_token),
            address(_distributor),
            _destination,
            1
        );
    }

    function test_givenKeeperEqualsFee_givenKeeperFee_whenFullEntitlementRedirected_thenOnlyEligibleBucketsDebit()
        public
    {
        _useDistributor();
        _assertAllocation(
            RescueAllocation({
                keeper: address(_distributor),
                recipient: address(_distributor),
                destination: _destination,
                fee: 10,
                seized: 0,
                reward: 30,
                quantity: 40,
                rewardDebit: 30,
                feeDebit: 10,
                seizedDebit: 0
            }),
            address(this)
        );
    }

    function test_givenKeeperEqualsFee_givenKeeperSeizure_whenFullEntitlementRedirected_thenOnlyEligibleBucketsDebit()
        public
    {
        _useDistributor();
        _assertAllocation(
            RescueAllocation({
                keeper: address(_distributor),
                recipient: address(_distributor),
                destination: _destination,
                fee: 0,
                seized: 20,
                reward: 30,
                quantity: 30,
                rewardDebit: 30,
                feeDebit: 0,
                seizedDebit: 0
            }),
            address(this)
        );
    }

    function test_givenKeeperEqualsFee_givenFeeSeizure_whenFullEntitlementRedirected_thenOnlyEligibleBucketsDebit()
        public
    {
        _useDistributor();
        _assertAllocation(
            RescueAllocation({
                keeper: address(_distributor),
                recipient: address(_distributor),
                destination: _destination,
                fee: 10,
                seized: 20,
                reward: 0,
                quantity: 10,
                rewardDebit: 0,
                feeDebit: 10,
                seizedDebit: 0
            }),
            address(this)
        );
    }

    function test_givenKeeperEqualsFee_givenAllBuckets_whenFullEntitlementRedirected_thenOnlyEligibleBucketsDebit()
        public
    {
        _useDistributor();
        _assertAllocation(
            RescueAllocation({
                keeper: address(_distributor),
                recipient: address(_distributor),
                destination: _destination,
                fee: 10,
                seized: 20,
                reward: 30,
                quantity: 40,
                rewardDebit: 30,
                feeDebit: 10,
                seizedDebit: 0
            }),
            address(this)
        );
    }

    function test_givenKeeperEqualsTreasury_givenKeeper_whenFullEntitlementRedirected_thenOnlyEligibleBucketsDebit()
        public
    {
        _useDistributor();
        _assertAllocation(
            RescueAllocation({
                keeper: _treasury(),
                recipient: _treasury(),
                destination: _destination,
                fee: 0,
                seized: 0,
                reward: 30,
                quantity: 30,
                rewardDebit: 30,
                feeDebit: 0,
                seizedDebit: 0
            }),
            address(this)
        );
    }

    // Scenarios: BLCU-PENDING-RESCUE-N02.
    function test_givenKeeperEqualsTreasury_givenFee_whenNoEligibleEntitlement_reverts() public {
        _useDistributor();
        _seedBuckets(10, 0, 0, _treasury());
        _expectPendingRejected(
            abi.encodeWithSelector(
                IBurnerLoansPayout.BurnerLoans_InsufficientPendingPayout.selector,
                address(_token),
                uint256(1),
                uint256(0)
            ),
            address(this),
            address(_token),
            _treasury(),
            _destination,
            1
        );
    }

    function test_givenKeeperEqualsTreasury_givenSeizure_whenFullEntitlementRedirected_thenOnlyEligibleBucketsDebit()
        public
    {
        _useDistributor();
        _assertAllocation(
            RescueAllocation({
                keeper: _treasury(),
                recipient: _treasury(),
                destination: _destination,
                fee: 0,
                seized: 20,
                reward: 0,
                quantity: 20,
                rewardDebit: 0,
                feeDebit: 0,
                seizedDebit: 20
            }),
            address(this)
        );
    }

    function test_givenKeeperEqualsTreasury_givenKeeperFee_whenFullEntitlementRedirected_thenOnlyEligibleBucketsDebit()
        public
    {
        _useDistributor();
        _assertAllocation(
            RescueAllocation({
                keeper: _treasury(),
                recipient: _treasury(),
                destination: _destination,
                fee: 10,
                seized: 0,
                reward: 30,
                quantity: 30,
                rewardDebit: 30,
                feeDebit: 0,
                seizedDebit: 0
            }),
            address(this)
        );
    }

    function test_givenKeeperEqualsTreasury_givenKeeperSeizure_whenFullEntitlementRedirected_thenOnlyEligibleBucketsDebit()
        public
    {
        _useDistributor();
        _assertAllocation(
            RescueAllocation({
                keeper: _treasury(),
                recipient: _treasury(),
                destination: _destination,
                fee: 0,
                seized: 20,
                reward: 30,
                quantity: 50,
                rewardDebit: 30,
                feeDebit: 0,
                seizedDebit: 20
            }),
            address(this)
        );
    }

    function test_givenKeeperEqualsTreasury_givenFeeSeizure_whenFullEntitlementRedirected_thenOnlyEligibleBucketsDebit()
        public
    {
        _useDistributor();
        _assertAllocation(
            RescueAllocation({
                keeper: _treasury(),
                recipient: _treasury(),
                destination: _destination,
                fee: 10,
                seized: 20,
                reward: 0,
                quantity: 20,
                rewardDebit: 0,
                feeDebit: 0,
                seizedDebit: 20
            }),
            address(this)
        );
    }

    function test_givenKeeperEqualsTreasury_givenAllBuckets_whenFullEntitlementRedirected_thenOnlyEligibleBucketsDebit()
        public
    {
        _useDistributor();
        _assertAllocation(
            RescueAllocation({
                keeper: _treasury(),
                recipient: _treasury(),
                destination: _destination,
                fee: 10,
                seized: 20,
                reward: 30,
                quantity: 50,
                rewardDebit: 30,
                feeDebit: 0,
                seizedDebit: 20
            }),
            address(this)
        );
    }

    // Scenarios: BLCU-PENDING-RESCUE-N02.
    function test_givenProtocolRoutesOverlap_givenKeeper_whenNoEligibleEntitlement_reverts()
        public
    {
        _seedBuckets(0, 0, 30, _keeper);
        _expectPendingRejected(
            abi.encodeWithSelector(
                IBurnerLoansPayout.BurnerLoans_InsufficientPendingPayout.selector,
                address(_token),
                uint256(1),
                uint256(0)
            ),
            address(this),
            address(_token),
            _treasury(),
            _destination,
            1
        );
    }

    function test_givenProtocolRoutesOverlap_givenFee_whenFullEntitlementRedirected_thenOnlyEligibleBucketsDebit()
        public
    {
        _assertAllocation(
            RescueAllocation({
                keeper: _keeper,
                recipient: _treasury(),
                destination: _destination,
                fee: 10,
                seized: 0,
                reward: 0,
                quantity: 10,
                rewardDebit: 0,
                feeDebit: 10,
                seizedDebit: 0
            }),
            address(this)
        );
    }

    function test_givenProtocolRoutesOverlap_givenSeizure_whenFullEntitlementRedirected_thenOnlyEligibleBucketsDebit()
        public
    {
        _assertAllocation(
            RescueAllocation({
                keeper: _keeper,
                recipient: _treasury(),
                destination: _destination,
                fee: 0,
                seized: 20,
                reward: 0,
                quantity: 20,
                rewardDebit: 0,
                feeDebit: 0,
                seizedDebit: 20
            }),
            address(this)
        );
    }

    function test_givenProtocolRoutesOverlap_givenKeeperFee_whenFullEntitlementRedirected_thenOnlyEligibleBucketsDebit()
        public
    {
        _assertAllocation(
            RescueAllocation({
                keeper: _keeper,
                recipient: _treasury(),
                destination: _destination,
                fee: 10,
                seized: 0,
                reward: 30,
                quantity: 10,
                rewardDebit: 0,
                feeDebit: 10,
                seizedDebit: 0
            }),
            address(this)
        );
    }

    function test_givenProtocolRoutesOverlap_givenKeeperSeizure_whenFullEntitlementRedirected_thenOnlyEligibleBucketsDebit()
        public
    {
        _assertAllocation(
            RescueAllocation({
                keeper: _keeper,
                recipient: _treasury(),
                destination: _destination,
                fee: 0,
                seized: 20,
                reward: 30,
                quantity: 20,
                rewardDebit: 0,
                feeDebit: 0,
                seizedDebit: 20
            }),
            address(this)
        );
    }

    function test_givenProtocolRoutesOverlap_givenFeeSeizure_whenFullEntitlementRedirected_thenOnlyEligibleBucketsDebit()
        public
    {
        _assertAllocation(
            RescueAllocation({
                keeper: _keeper,
                recipient: _treasury(),
                destination: _destination,
                fee: 10,
                seized: 20,
                reward: 0,
                quantity: 30,
                rewardDebit: 0,
                feeDebit: 10,
                seizedDebit: 20
            }),
            address(this)
        );
    }

    function test_givenProtocolRoutesOverlap_givenAllBuckets_whenFullEntitlementRedirected_thenOnlyEligibleBucketsDebit()
        public
    {
        _assertAllocation(
            RescueAllocation({
                keeper: _keeper,
                recipient: _treasury(),
                destination: _destination,
                fee: 10,
                seized: 20,
                reward: 30,
                quantity: 30,
                rewardDebit: 0,
                feeDebit: 10,
                seizedDebit: 20
            }),
            address(this)
        );
    }

    function test_givenAllRecipientsOverlap_givenKeeper_whenFullEntitlementRedirected_thenOnlyEligibleBucketsDebit()
        public
    {
        _assertAllocation(
            RescueAllocation({
                keeper: _treasury(),
                recipient: _treasury(),
                destination: _destination,
                fee: 0,
                seized: 0,
                reward: 30,
                quantity: 30,
                rewardDebit: 30,
                feeDebit: 0,
                seizedDebit: 0
            }),
            address(this)
        );
    }

    function test_givenAllRecipientsOverlap_givenFee_whenFullEntitlementRedirected_thenOnlyEligibleBucketsDebit()
        public
    {
        _assertAllocation(
            RescueAllocation({
                keeper: _treasury(),
                recipient: _treasury(),
                destination: _destination,
                fee: 10,
                seized: 0,
                reward: 0,
                quantity: 10,
                rewardDebit: 0,
                feeDebit: 10,
                seizedDebit: 0
            }),
            address(this)
        );
    }

    function test_givenAllRecipientsOverlap_givenSeizure_whenFullEntitlementRedirected_thenOnlyEligibleBucketsDebit()
        public
    {
        _assertAllocation(
            RescueAllocation({
                keeper: _treasury(),
                recipient: _treasury(),
                destination: _destination,
                fee: 0,
                seized: 20,
                reward: 0,
                quantity: 20,
                rewardDebit: 0,
                feeDebit: 0,
                seizedDebit: 20
            }),
            address(this)
        );
    }

    function test_givenAllRecipientsOverlap_givenKeeperFee_whenFullEntitlementRedirected_thenOnlyEligibleBucketsDebit()
        public
    {
        _assertAllocation(
            RescueAllocation({
                keeper: _treasury(),
                recipient: _treasury(),
                destination: _destination,
                fee: 10,
                seized: 0,
                reward: 30,
                quantity: 40,
                rewardDebit: 30,
                feeDebit: 10,
                seizedDebit: 0
            }),
            address(this)
        );
    }

    function test_givenAllRecipientsOverlap_givenKeeperSeizure_whenFullEntitlementRedirected_thenOnlyEligibleBucketsDebit()
        public
    {
        _assertAllocation(
            RescueAllocation({
                keeper: _treasury(),
                recipient: _treasury(),
                destination: _destination,
                fee: 0,
                seized: 20,
                reward: 30,
                quantity: 50,
                rewardDebit: 30,
                feeDebit: 0,
                seizedDebit: 20
            }),
            address(this)
        );
    }

    function test_givenAllRecipientsOverlap_givenFeeSeizure_whenFullEntitlementRedirected_thenOnlyEligibleBucketsDebit()
        public
    {
        _assertAllocation(
            RescueAllocation({
                keeper: _treasury(),
                recipient: _treasury(),
                destination: _destination,
                fee: 10,
                seized: 20,
                reward: 0,
                quantity: 30,
                rewardDebit: 0,
                feeDebit: 10,
                seizedDebit: 20
            }),
            address(this)
        );
    }

    function test_givenAllRecipientsOverlap_givenAllBuckets_whenFullEntitlementRedirected_thenOnlyEligibleBucketsDebit()
        public
    {
        _assertAllocation(
            RescueAllocation({
                keeper: _treasury(),
                recipient: _treasury(),
                destination: _destination,
                fee: 10,
                seized: 20,
                reward: 30,
                quantity: 60,
                rewardDebit: 30,
                feeDebit: 10,
                seizedDebit: 20
            }),
            address(this)
        );
    }

    // Scenarios: BLCU-PENDING-RESCUE-N02.
    function test_givenVariableEntitlement_whenAmountTooLarge_thenExactError(
        uint256 available_,
        uint256 amount_,
        address caller_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        available_ = bound(available_, 0, type(uint256).max - 1);
        amount_ = bound(amount_, available_ + 1, type(uint256).max);
        _grantRecoveryCaller(caller_, operatorOnly_, overlap_);
        _seedBuckets(0, 0, available_, _keeper);
        _expectPendingRejected(
            abi.encodeWithSelector(
                IBurnerLoansPayout.BurnerLoans_InsufficientPendingPayout.selector,
                address(_token),
                amount_,
                available_
            ),
            caller_,
            address(_token),
            _keeper,
            _destination,
            amount_
        );
    }

    // Scenarios: BLCU-PENDING-RESCUE-L02.
    function test_givenPayoutInactive_whenCalled_reverts(
        address caller_,
        bool operatorOnly_,
        bool overlap_,
        bool enabled_
    ) public givenPendingBuckets {
        _grantRecoveryCaller(caller_, operatorOnly_, overlap_);

        _setState(_payout, false, enabled_);
        bytes32 state = _ledgerDigest();
        _expectInactivePayout();
        vm.prank(caller_);
        _payout.previewRescuePendingPayout(address(_token), _keeper, _destination, 1);
        _expectInactivePayout();
        vm.prank(caller_);
        _payout.rescuePendingPayout(address(_token), _keeper, _destination, 1);
        assertEq(_ledgerDigest(), state, "Inactive Payout preserves balances and obligations");
    }

    // Scenarios: BLCU-PENDING-RESCUE-L04.
    function test_givenPayoutInactiveAndBrokenRoles_whenUnauthorizedCallerActs_thenActivityWins(
        address caller_,
        bool enabled_
    ) public givenPendingBuckets {
        _deactivatePayoutWithBrokenRoles(caller_, enabled_);
        bytes32 state = _ledgerDigest();
        _expectInactivePayout();
        vm.prank(caller_);
        _payout.rescuePendingPayout(address(_token), _keeper, _destination, 1);
        assertEq(_ledgerDigest(), state, "Inactivity rejects before authority or mutation");
    }
}

// forge-lint: disable-end(calls-loop, literal-instead-of-constant, reentrancy-no-eth, unused-return)
