// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IBurnerLoansRescue} from "src/policies/interfaces/IBurnerLoansRescue.sol";

// Contracts
import {BurnerLoansTest} from "src/test/policies/BurnerLoans/BurnerLoansTest.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {ReentrantPayoutToken} from "src/test/mocks/ReentrantPayoutToken.sol";

/// @dev Surplus-only accounting assertions, also used when BLC or BLCT forwards the surplus call.
///      No pending-rescue test helpers are inherited. Amounts are token base units.
// Finite test fixtures call external helpers and intentionally use small quantities.
// forge-lint: disable-start(calls-loop,literal-instead-of-constant,unused-return)
abstract contract BurnerLoansSurplusRescueTestBase is BurnerLoansTest {
    error BalanceQueryFailed();
    error TransferMustNotRun();

    uint256 internal constant _REWARD_AMOUNT = 10;
    uint256 internal constant _FEE_AMOUNT = 20;
    uint256 internal constant _SEIZURE_AMOUNT = 30;
    uint256 internal constant _PENDING_RESERVE = _REWARD_AMOUNT + _FEE_AMOUNT + _SEIZURE_AMOUNT;
    uint256 internal constant _SURPLUS_AMOUNT = 5;
    uint256 internal constant _FULL_CUSTODY = _PENDING_RESERVE + _SURPLUS_AMOUNT;
    uint256 internal constant _DESTINATION_BALANCE = 7;

    uint8 internal constant _REWARD_BUCKET = 1;
    uint8 internal constant _FEE_BUCKET = 2;
    uint8 internal constant _SEIZURE_BUCKET = 4;
    uint8 internal constant _ALL_BUCKETS = 7;
    address internal _keeper;
    address internal _secondKeeper;
    address internal _thirdKeeper;
    address internal _destination;

    function setUp() public virtual override {
        super.setUp();
        _keeper = makeAddr("surplus keeper");
        _secondKeeper = makeAddr("second surplus keeper");
        _thirdKeeper = makeAddr("third surplus keeper");
        _destination = makeAddr("surplus destination");
    }

    /// @dev Creates only the chosen 10/20/30 liabilities. Bits describe recorded buckets,
    ///      not address eligibility. Custody starts at their sum, with no surplus.
    function _createFixedRescueToken(
        uint8 bucketMask_
    ) internal returns (ReentrantPayoutToken asset) {
        asset = new ReentrantPayoutToken();
        _recordRescueDebts(
            asset,
            bucketMask_ & _REWARD_BUCKET != 0 ? _REWARD_AMOUNT : 0,
            bucketMask_ & _FEE_BUCKET != 0 ? _FEE_AMOUNT : 0,
            bucketMask_ & _SEIZURE_BUCKET != 0 ? _SEIZURE_AMOUNT : 0
        );
    }

    /// @dev Exercises production deferral: fund obligations, then reject their immediate payouts.
    ///      The caller chooses quantities explicitly and funds surplus separately.
    function _recordRescueDebts(
        MockERC20 asset_,
        uint256 reward_,
        uint256 fee_,
        uint256 seizure_
    ) internal {
        asset_.mint(address(burnerLoans), reward_ + seizure_);
        address feeRecipient = burnerLoans.sendFeesToDistributor()
            ? burnerLoans.revenueDistributor()
            : address(trsry);
        vm.mockCall(
            address(asset_),
            abi.encodeWithSelector(IERC20.transfer.selector, _keeper),
            abi.encode(false)
        );
        vm.mockCall(
            address(asset_),
            abi.encodeWithSelector(IERC20.transfer.selector, feeRecipient),
            abi.encode(false)
        );
        vm.mockCall(
            address(asset_),
            abi.encodeWithSelector(IERC20.transfer.selector, address(trsry)),
            abi.encode(false)
        );
        if (fee_ != 0) {
            asset_.mint(alice, fee_);
            vm.prank(alice);
            assertTrue(
                asset_.approve(address(burnerLoans), fee_),
                "fee source approves exact obligation"
            );
            burnerLoans.recordPendingFeeForTest(address(asset_), alice, feeRecipient, fee_);
        }
        if (seizure_ != 0)
            burnerLoans.recordPendingSeizedCollateralForTest(
                address(asset_),
                address(trsry),
                seizure_
            );
        if (reward_ != 0)
            burnerLoans.recordPendingSeizureRewardForTest(address(asset_), _keeper, reward_);
        vm.clearMockedCalls();
        _assertPendingPayouts(address(asset_), _keeper, fee_, seizure_, reward_);
        assertEq(
            asset_.balanceOf(address(burnerLoans)),
            reward_ + fee_ + seizure_,
            "fixture funds the exact reserve"
        );
    }

    /// @dev Fingerprint raw buckets, all represented keepers, authoritative keeper membership,
    ///      public enumeration and configuration. Balances are checked separately per action.
    function _surplusAccountingHash(address asset_) internal view returns (bytes32) {
        bytes32 debts = keccak256(
            abi.encode(
                burnerLoans.pendingFeeForTest(asset_),
                burnerLoans.pendingSeizureForTest(asset_),
                burnerLoans.pendingSeizureRewardForTest(asset_, _keeper),
                burnerLoans.pendingSeizureRewardForTest(asset_, _secondKeeper),
                burnerLoans.pendingSeizureRewardForTest(asset_, _thirdKeeper),
                burnerLoans.totalPendingForTest(asset_)
            )
        );
        bytes32 indexes = keccak256(
            abi.encode(
                burnerLoans.pendingKeeperMemberForTest(asset_, _keeper),
                burnerLoans.pendingKeeperMemberForTest(asset_, _secondKeeper),
                burnerLoans.pendingKeeperMemberForTest(asset_, _thirdKeeper),
                burnerLoans.getPendingPayoutTokens(),
                burnerLoans.getPendingPayoutRecipients(asset_)
            )
        );
        bytes32 config = keccak256(
            abi.encode(
                burnerLoans.configurator(),
                burnerLoans.revenueDistributor(),
                burnerLoans.sendFeesToDistributor(),
                burnerLoans.sendYieldToDistributor(),
                burnerLoans.isEnabled(),
                burnerLoansConfig.facility(),
                burnerLoansConfig.configOperator(),
                burnerLoansConfig.isAssetConfigured(asset_),
                burnerLoansConfig.isEnabled()
            )
        );
        if (burnerLoansConfig.isAssetConfigured(asset_))
            config = keccak256(
                abi.encode(
                    config,
                    burnerLoansConfig.getAssetConfig(asset_),
                    burnerLoansConfig.getAssetFeeConfig(asset_)
                )
            );
        bytes32 entitlements = keccak256(
            abi.encode(
                burnerLoans.pendingPayout(asset_, _keeper),
                burnerLoans.pendingPayout(asset_, _secondKeeper),
                burnerLoans.pendingPayout(asset_, _thirdKeeper),
                burnerLoans.pendingPayout(
                    asset_,
                    burnerLoans.sendFeesToDistributor()
                        ? burnerLoans.revenueDistributor()
                        : address(trsry)
                ),
                burnerLoans.pendingPayout(asset_, address(trsry))
            )
        );
        return keccak256(abi.encode(debts, indexes, config, entitlements));
    }

    /// @dev The test supplies the independently expected surplus. Check exact payment/event
    ///      ordering and verify that a zero surplus never attempts a transfer.
    function _assertSurplusPayment(
        MockERC20 asset_,
        address destination_,
        uint256 surplus_,
        address caller_
    ) internal {
        uint256 custody = asset_.balanceOf(address(burnerLoans));
        uint256 destinationBalance = asset_.balanceOf(destination_);
        bytes32 stateBefore = _surplusAccountingHash(address(asset_));
        uint256 supply = asset_.totalSupply();
        assertEq(
            burnerLoans.previewRescue(address(asset_), destination_),
            surplus_,
            "preview equals independent surplus"
        );
        if (surplus_ != 0) {
            vm.expectEmit(true, true, false, true, address(asset_));
            emit IERC20.Transfer(address(burnerLoans), destination_, surplus_);
            vm.expectEmit(true, true, false, true, address(burnerLoans));
            emit IBurnerLoansRescue.AssetRescued(address(asset_), destination_, surplus_);
        } else
            vm.mockCallRevert(
                address(asset_),
                abi.encodeWithSelector(IERC20.transfer.selector, destination_),
                abi.encodeWithSelector(TransferMustNotRun.selector)
            );
        _expectSurplusCompletionEvents(caller_);
        vm.recordLogs();
        _executeSurplusRescue(address(asset_), destination_, caller_);
        assertEq(
            vm.getRecordedLogs().length,
            _surplusExecutionLogCount(surplus_),
            "exact transfer/rescue log count"
        );
        vm.clearMockedCalls();
        assertEq(
            asset_.balanceOf(address(burnerLoans)),
            custody - surplus_,
            "only surplus leaves custody"
        );
        assertEq(
            asset_.balanceOf(destination_),
            destinationBalance + surplus_,
            "destination receives exact surplus"
        );
        assertEq(asset_.totalSupply(), supply, "rescue does not change token supply");
        assertEq(
            _surplusAccountingHash(address(asset_)),
            stateBefore,
            "debts, indexes and configuration are unchanged"
        );
        assertEq(
            burnerLoans.previewRescue(address(asset_), destination_),
            0,
            "no surplus remains after rescue"
        );
    }

    /// @dev Wrappers override only the entry point; the accounting assertions stay identical.
    function _executeSurplusRescue(
        address asset_,
        address destination_,
        address caller_
    ) internal virtual {
        vm.prank(caller_);
        burnerLoans.rescue(asset_, destination_);
    }

    /// @dev Reject one request with exact data, preserving represented ledger/index state and custody.
    function _assertSurplusFailure(
        MockERC20 trackedAsset_,
        address requestedAsset_,
        address destination_,
        address caller_,
        bytes memory failure_
    ) internal {
        bytes32 stateBefore = _surplusAccountingHash(address(trackedAsset_));
        uint256 custody = trackedAsset_.balanceOf(address(burnerLoans));
        uint256 destinationBalance = trackedAsset_.balanceOf(destination_);
        vm.expectRevert(failure_);
        _executeSurplusRescue(requestedAsset_, destination_, caller_);
        assertEq(
            trackedAsset_.balanceOf(address(burnerLoans)),
            custody,
            "failed rescue preserves custody"
        );
        assertEq(
            trackedAsset_.balanceOf(destination_),
            destinationBalance,
            "failed rescue preserves destination balance"
        );
        assertEq(
            _surplusAccountingHash(address(trackedAsset_)),
            stateBefore,
            "failed rescue preserves raw debts, indexes and configuration"
        );
    }

    /// @dev A mocked balance failure must not prevent checking the real token state afterward.
    function _assertBalanceQueryFailure(MockERC20 asset_, address caller_) internal {
        uint256 custody = asset_.balanceOf(address(burnerLoans));
        uint256 destinationBalance = asset_.balanceOf(_destination);
        bytes32 beforeState = _surplusAccountingHash(address(asset_));
        bytes memory failure = abi.encodeWithSelector(BalanceQueryFailed.selector);
        vm.mockCallRevert(
            address(asset_),
            abi.encodeWithSelector(IERC20.balanceOf.selector, address(burnerLoans)),
            failure
        );
        vm.expectRevert(failure);
        burnerLoans.previewRescue(address(asset_), _destination);
        vm.expectRevert(failure);
        _executeSurplusRescue(address(asset_), _destination, caller_);
        vm.clearMockedCalls();
        assertEq(
            asset_.balanceOf(address(burnerLoans)),
            custody,
            "balance failure preserves actual custody"
        );
        assertEq(
            asset_.balanceOf(_destination),
            destinationBalance,
            "balance failure preserves actual destination"
        );
        assertEq(
            _surplusAccountingHash(address(asset_)),
            beforeState,
            "balance failure preserves actual raw ledger and configuration"
        );
    }

    /// @dev Use a separate funded token with three keepers to detect cross-token debt/index damage.
    function _createUnrelatedRescueDebt() internal returns (ReentrantPayoutToken other) {
        other = _createFixedRescueToken(_ALL_BUCKETS);
        other.mint(address(burnerLoans), 5);
        vm.mockCall(
            address(other),
            abi.encodeWithSelector(IERC20.transfer.selector, _secondKeeper),
            abi.encode(false)
        );
        vm.mockCall(
            address(other),
            abi.encodeWithSelector(IERC20.transfer.selector, _thirdKeeper),
            abi.encode(false)
        );
        burnerLoans.recordPendingSeizureRewardForTest(address(other), _secondKeeper, 2);
        burnerLoans.recordPendingSeizureRewardForTest(address(other), _thirdKeeper, 3);
        vm.clearMockedCalls();
        assertEq(
            burnerLoans.totalPendingForTest(address(other)),
            65,
            "unrelated three-keeper reserve is funded"
        );
    }

    /// @dev Timelock wrappers append their own two completion events.
    function _surplusExecutionLogCount(uint256 amount_) internal pure virtual returns (uint256) {
        return amount_ == 0 ? 0 : 2;
    }

    function _expectSurplusCompletionEvents(address) internal virtual {}
}
// forge-lint: disable-end(calls-loop,literal-instead-of-constant,unused-return)
