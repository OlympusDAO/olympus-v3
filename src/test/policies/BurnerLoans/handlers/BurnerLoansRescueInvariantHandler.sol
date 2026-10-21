// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansRescue} from "src/policies/interfaces/IBurnerLoansRescue.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Contracts
import {Test} from "@forge-std-1.16.2/Test.sol";
import {BurnerLoansConfig} from "src/policies/BurnerLoansConfig.sol";
import {MockRevertingTransferToken} from "src/test/mocks/MockRevertingTransferToken.sol";
import {BurnerLoansHarness} from "src/test/policies/BurnerLoans/fixtures/BurnerLoansHarness.sol";

// Base-unit fixtures deliberately bound receipts and inspect a small fixed actor set.
// forge-lint: disable-start(calls-loop,literal-instead-of-constant,unused-return)
/// @dev Exercises production payout-library bookkeeping through the existing facility harness.
///      Independent ghost buckets never read the facility reserve to decide their expected value.
contract BurnerLoansRescueInvariantHandler is Test {
    error InvalidActor();
    BurnerLoansHarness internal _facility;
    BurnerLoansConfig internal _config;
    MockRevertingTransferToken internal _asset;
    address internal _admin;
    address internal _treasury;
    address internal _destination;
    address[2] internal _keepers;
    mapping(address => bool) internal _blocked;
    uint256 internal _fees;
    uint256 internal _seized;
    uint256[2] internal _rewards;
    uint256 internal _minted;

    constructor(
        BurnerLoansHarness facility_,
        BurnerLoansConfig config_,
        MockRevertingTransferToken asset_,
        address admin_,
        address treasury_
    ) {
        if (admin_ == address(0) || treasury_ == address(0)) revert InvalidActor();
        _facility = facility_;
        _config = config_;
        _asset = asset_;
        _admin = admin_;
        _treasury = treasury_;
        _destination = makeAddr("invariant rescue destination");
        _keepers[0] = makeAddr("invariant first keeper");
        _keepers[1] = makeAddr("invariant second keeper");
        assertTrue(
            asset_.approve(address(facility_), type(uint256).max),
            "invariant fee approval succeeds"
        );
    }

    function collectFee(uint96 amount_) external {
        uint256 amount = bound(amount_, 1, 1e12);
        _asset.mint(address(this), amount);
        _minted += amount;
        _fees = _blocked[_treasury] ? _fees + amount : 0;
        _facility.recordPendingFeeForTest(address(_asset), address(this), _treasury, amount);
    }

    function queueSeizure(uint96 amount_) external {
        uint256 amount = bound(amount_, 1, 1e12);
        _asset.mint(address(_facility), amount);
        _minted += amount;
        _seized = _blocked[_treasury] ? _seized + amount : 0;
        _facility.recordPendingSeizedCollateralForTest(address(_asset), _treasury, amount);
    }

    function queueKeeperReward(uint8 keeperIndex_, uint96 amount_) external {
        uint256 index = keeperIndex_ % 2;
        uint256 amount = bound(amount_, 1, 1e12);
        _asset.mint(address(_facility), amount);
        _minted += amount;
        _rewards[index] = _blocked[_keepers[index]] ? _rewards[index] + amount : 0;
        _facility.recordPendingSeizureRewardForTest(address(_asset), _keepers[index], amount);
    }

    function receiveSurplus(uint96 amount_) external {
        uint256 amount = bound(amount_, 1, 1e12);
        _asset.mint(address(_facility), amount);
        _minted += amount;
    }

    function setTransferFailure(uint8 recipientIndex_, bool blocked_) external {
        address recipient = _recipient(recipientIndex_);
        _asset.setTransferReverts(recipient, blocked_);
        _blocked[recipient] = blocked_;
    }

    function retry(uint8 recipientIndex_) external {
        address recipient = _recipient(recipientIndex_);
        _facility.transferPendingPayout(address(_asset), recipient);
        if (_blocked[recipient]) return;
        if (recipient == _treasury) {
            _fees = 0;
            _seized = 0;
        } else if (recipient == _keepers[0]) _rewards[0] = 0;
        else if (recipient == _keepers[1]) _rewards[1] = 0;
    }

    function rescueSurplus() external {
        if (_blocked[_destination]) return;
        uint256 expected = _asset.balanceOf(address(_facility)) - _pending();
        uint256 beforeBalance = _asset.balanceOf(_destination);
        vm.prank(_admin);
        _config.rescue(address(_asset), _destination);
        assertEq(
            _asset.balanceOf(_destination) - beforeBalance,
            expected,
            "surplus excludes all ghost liabilities"
        );
    }

    function rescueTreasuryPayout(uint256 amount_) external {
        uint256 available = _fees + _seized;
        if (available == 0 || _blocked[_destination]) return;
        uint256 amount = bound(amount_, 1, available);
        uint256 feePaid = amount < _fees ? amount : _fees;
        _fees -= feePaid;
        _seized -= amount - feePaid;
        vm.prank(_admin);
        _config.rescuePendingPayout(address(_asset), _treasury, _destination, amount);
    }

    function rescueByRecipient(uint8 keeperIndex_, uint256 amount_) external {
        uint256 index = keeperIndex_ % 2;
        uint256 available = _rewards[index];
        if (available == 0 || _blocked[_destination]) return;
        uint256 amount = bound(amount_, 1, available);
        _rewards[index] -= amount;
        vm.prank(_admin);
        _config.rescuePendingPayout(address(_asset), _keepers[index], _destination, amount);
    }

    // Rejected calls are interleaved with accrual/retry/rescue actions; ghost accounting
    // is never advanced on failure. The next invariant check proves rollback of each bucket.
    function rejectUnauthorizedRescue(address caller_) external {
        if (caller_ == address(_config) || caller_ == _admin) return;
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        _facility.rescuePendingPayout(address(_asset), _treasury, _destination, 1);
    }

    function rejectExcessRescue(uint256 amount_) external {
        uint256 available = _fees + _seized;
        uint256 amount = bound(amount_, available + 1, type(uint256).max);
        bytes memory failure = abi.encodeWithSelector(
            IBurnerLoansRescue.BurnerLoans_InsufficientPendingPayout.selector,
            address(_asset),
            amount,
            available
        );
        vm.expectRevert(failure);
        _facility.previewRescuePendingPayout(address(_asset), _treasury, _destination, amount);
        vm.expectRevert(failure);
        vm.prank(address(_config));
        _facility.rescuePendingPayout(address(_asset), _treasury, _destination, amount);
    }

    function rejectBlockedRescue(uint8 recipientIndex_, uint256 amount_) external {
        address recipient = _recipient(recipientIndex_);
        uint256 available = _facility.pendingPayout(address(_asset), recipient);
        if (available == 0) return;
        uint256 amount = bound(amount_, 1, available);
        bool wasBlocked = _blocked[_destination];
        _asset.setTransferReverts(_destination, true);
        vm.expectRevert(
            abi.encodeWithSelector(
                MockRevertingTransferToken.TransferReverted.selector,
                _destination
            )
        );
        vm.prank(address(_config));
        _facility.rescuePendingPayout(address(_asset), recipient, _destination, amount);
        _asset.setTransferReverts(_destination, wasBlocked);
    }

    function assertAccounting() external view {
        assertEq(
            _facility.pendingFeeForTest(address(_asset)),
            _fees,
            "fee bucket matches independent model"
        );
        assertEq(
            _facility.pendingSeizureForTest(address(_asset)),
            _seized,
            "seizure bucket matches independent model"
        );
        for (uint256 i; i < _keepers.length; ++i) {
            assertEq(
                _facility.pendingSeizureRewardForTest(address(_asset), _keepers[i]),
                _rewards[i],
                "keeper reward bucket matches independent model"
            );
        }
        uint256 pending = _pending();
        uint256 custody = _asset.balanceOf(address(_facility));
        assertEq(
            _facility.totalPendingForTest(address(_asset)),
            pending,
            "aggregate equals independent sum of every bucket"
        );
        assertGe(custody, pending, "custody backs every pending obligation");
        assertEq(
            _facility.pendingPayout(address(_asset), _treasury),
            _fees + _seized,
            "Treasury follows both role buckets"
        );
        assertEq(
            _facility.pendingPayout(address(_asset), _keepers[0]),
            _rewards[0],
            "first keeper retains own entitlement"
        );
        assertEq(
            _facility.pendingPayout(address(_asset), _keepers[1]),
            _rewards[1],
            "second keeper retains own entitlement"
        );
        assertEq(
            _facility.getPendingPayoutTokens().length,
            pending == 0 ? 0 : 1,
            "token index matches aggregate reserve"
        );
        address[] memory recipients = _facility.getPendingPayoutRecipients(address(_asset));
        uint256 expectedCount = (_fees + _seized == 0 ? 0 : 1) +
            (_rewards[0] == 0 ? 0 : 1) +
            (_rewards[1] == 0 ? 0 : 1);
        assertEq(
            recipients.length,
            expectedCount,
            "recipient index includes every nonempty bucket"
        );
        uint256 listed;
        for (uint256 i; i < recipients.length; ++i) {
            listed += _facility.pendingPayout(address(_asset), recipients[i]);
            for (uint256 j; j < i; ++j)
                assertTrue(recipients[i] != recipients[j], "recipient index has no duplicates");
        }
        assertEq(listed, pending, "enumerated liabilities equal reserve");
        for (uint256 i; i < recipients.length; ++i) {
            uint256 available = _facility.pendingPayout(address(_asset), recipients[i]);
            assertEq(
                _facility.previewRescuePendingPayout(
                    address(_asset),
                    recipients[i],
                    _destination,
                    1
                ),
                available,
                "pending preview matches outstanding entitlement"
            );
        }
        assertEq(
            _facility.previewRescue(address(_asset), _destination),
            custody - pending,
            "surplus preview excludes independent reserve"
        );
        uint256 accounted = custody +
            _asset.balanceOf(address(this)) +
            _asset.balanceOf(_treasury) +
            _asset.balanceOf(_destination) +
            _asset.balanceOf(_keepers[0]) +
            _asset.balanceOf(_keepers[1]);
        assertEq(accounted, _minted, "every minted unit remains in custody or a destination");
    }

    function _pending() internal view returns (uint256) {
        return _fees + _seized + _rewards[0] + _rewards[1];
    }

    function _recipient(uint8 index_) internal view returns (address) {
        if (index_ % 4 == 0) return _treasury;
        if (index_ % 4 == 1) return _keepers[0];
        if (index_ % 4 == 2) return _keepers[1];
        return _destination;
    }
}
// forge-lint: disable-end(calls-loop,literal-instead-of-constant,unused-return)
