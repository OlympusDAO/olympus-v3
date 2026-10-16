// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "@openzeppelin-5.7.0/token/ERC20/IERC20.sol";
import {IBurnerLoansRescue} from "src/policies/interfaces/IBurnerLoansRescue.sol";

// Contracts
import {Actions, Policy} from "src/Kernel.sol";
import {RevenueDistributor} from "src/policies/RevenueDistributor.sol";
import {ReentrantPayoutToken} from "src/test/mocks/ReentrantPayoutToken.sol";
import {BurnerLoansTest} from "src/test/policies/BurnerLoans/BurnerLoansTest.sol";
import {BurnerLoansHarness} from "src/test/policies/BurnerLoans/fixtures/BurnerLoansHarness.sol";

// forge-lint: disable-start(multi-contract-file,literal-instead-of-constant,calls-loop,unused-return)

contract RescuePendingToken is ReentrantPayoutToken {
    uint256 public transferCalls;

    /// @notice Count committed transfers while retaining callback-token behavior.
    /// @dev Counts transfer attempts through the callback token. A failed transfer also rolls
    /// back the counter, so successful rescues can assert exactly one committed transfer.
    /// @param recipient_ Token recipient.
    /// @param amount_ Amount in token base units.
    /// @return Standard ERC-20 transfer result.
    function transfer(address recipient_, uint256 amount_) public override returns (bool) {
        ++transferCalls;
        return super.transfer(recipient_, amount_);
    }

    uint256 public observedEntitlement;
    uint256 public observedPreview;
    bytes public observedFailure;
    bytes32 public observedState;

    /// @notice Record accounting visible during an outer rescue transfer.
    /// @dev Callback that records post-debit entitlement, preview result/error and accounting
    /// state after the outer token transfer. It never performs another transfer.
    /// @param facility_ Facility whose payout state is observed.
    /// @param recipient_ Original payout recipient selected by the outer rescue.
    /// @param destination_ Outer rescue destination.
    function observe(
        BurnerLoansHarness facility_,
        address recipient_,
        address destination_
    ) external {
        observedEntitlement = facility_.pendingPayout(address(this), recipient_);
        try
            facility_.previewRescuePendingPayout(address(this), recipient_, destination_, 1)
        returns (uint256 available) {
            observedPreview = available;
        } catch (bytes memory failure) {
            observedFailure = failure;
        }
        observedState = observation(facility_, recipient_, destination_);
    }

    /// @notice Fingerprint the accounting visible to a read callback.
    /// @dev Fingerprints buckets, custody and indexes visible to the read callback; comparing
    /// this with the final state proves the callback observed completed outer accounting.
    /// @param facility_ Facility to inspect.
    /// @param recipient_ Recipient whose keeper reward is included.
    /// @param destination_ Destination whose token balance is included.
    /// @return Hash of the observed accounting and token balances.
    function observation(
        BurnerLoansHarness facility_,
        address recipient_,
        address destination_
    ) public view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    facility_.pendingFeeForTest(address(this)),
                    facility_.pendingSeizureForTest(address(this)),
                    facility_.pendingSeizureRewardForTest(address(this), recipient_),
                    facility_.totalPendingForTest(address(this)),
                    balanceOf(address(facility_)),
                    balanceOf(destination_),
                    facility_.getPendingPayoutTokens(),
                    facility_.getPendingPayoutRecipients(address(this))
                )
            );
    }
}

/// @dev Pending-rescue-only setup. Amounts are exact base units; role setup, debt recording,
/// lifecycle and requests are separate. Expected payments are supplied by each scenario test.
abstract contract BurnerLoansRescuePendingTestBase is BurnerLoansTest {
    uint256 internal constant _REWARD = 10;
    uint256 internal constant _FEE = 20;
    uint256 internal constant _SEIZURE = 30;
    uint256 internal constant _TOTAL_FIXED_PENDING = _REWARD + _FEE + _SEIZURE;
    uint256 internal constant _DESTINATION_PRE_BALANCE = 7;
    uint256 internal constant _MAX = type(uint256).max;
    // Bit flags describe globally populated buckets, regardless of the selected recipient.
    // reward = 1, fee = 2, seizure = 4; OR flags to combine (3 = reward + fee, 7 = all).
    uint8 internal constant _REWARD_BUCKET = 1;
    uint8 internal constant _FEE_BUCKET = 2;
    uint8 internal constant _SEIZURE_BUCKET = 4;
    uint8 internal constant _ALL_BUCKETS = 7;

    enum RoleLayout {
        Distinct,
        KeeperIsFeeRecipient,
        KeeperIsTreasury,
        FeeRecipientIsTreasury,
        AllRolesOverlap
    }

    // Only recorded obligations and their owners. No selectors, request or lifecycle state.
    struct Ledger {
        RescuePendingToken token;
        address feeRecipient;
        address treasury;
        address[] keepers;
        uint256[] rewards;
        uint256 fee;
        uint256 seizure;
    }
    struct Request {
        address token;
        address recipient;
        address destination;
        uint256 amount;
    }

    RevenueDistributor internal _distributor;
    address[] internal _pendingTokens;

    function setUp() public virtual override {
        super.setUp();
        // One real distributor per test; role cases reuse it and the existing Treasury.
        vm.startPrank(admin);
        _distributor = new RevenueDistributor(kernel);
        kernel.executeAction(Actions.ActivatePolicy, address(_distributor));
        _distributor.enable("");
        burnerLoans.setRevenueDistributor(address(_distributor));
        vm.stopPrank();
    }

    /// @notice	Configure fee routing and return the keeper identity for a role layout.
    /// @dev	Use a fixed keeper unless the layout overlaps it with the fee recipient or Treasury.
    /// @dev	The rescue recipient is chosen separately; the returned keeper need not be selected.
    ///
    /// @param	layout_	Identity relationships between keeper, fee recipient and Treasury.
    /// @return	address	Keeper satisfying the configured layout.
    function _configurePayoutRoles(RoleLayout layout_) internal returns (address) {
        bool toDistributor = layout_ != RoleLayout.FeeRecipientIsTreasury &&
            layout_ != RoleLayout.AllRolesOverlap;
        vm.prank(address(burnerLoansConfig));
        burnerLoans.setSendFeesToDistributor(toDistributor);
        address feePayoutRecipient = toDistributor ? address(_distributor) : address(trsry);
        if (layout_ == RoleLayout.KeeperIsFeeRecipient) return feePayoutRecipient;
        if (layout_ == RoleLayout.KeeperIsTreasury || layout_ == RoleLayout.AllRolesOverlap)
            return address(trsry);
        return makeAddr("keeper");
    }

    /// @notice	Create a token, record exact pending debts and return their expected ledger.
    /// @dev	Uses production bookkeeping exposed by the harness; quantities are never bounded.
    /// @dev	Compute selected eligibility separately with _expectedRecipientPayout.
    /// @dev	Blocking recipients during accrual forces payouts to remain pending. Transfers
    /// @dev	are unblocked before returning, and facility custody equals total recorded debt.
    ///
    /// @param	keeper_		Owner of the reward; may also be the configured fee recipient or Treasury.
    /// @param	reward_		Keeper reward in token base units; zero leaves this bucket empty.
    /// @param	fee_		Debt to the configured fee recipient in token base units.
    /// @param	seizure_	Debt to Treasury in token base units.
    /// @return	l			Expected global debts and their owners, plus the newly created token.
    function _createPendingPayoutLedger(
        address keeper_,
        uint256 reward_,
        uint256 fee_,
        uint256 seizure_
    ) internal returns (Ledger memory l) {
        l.token = new RescuePendingToken();
        _pendingTokens.push(address(l.token));
        assertNotEq(keeper_, address(l.token), "fixed keeper differs from the token");
        l.feeRecipient = burnerLoans.sendFeesToDistributor()
            ? address(_distributor)
            : address(trsry);
        l.treasury = address(trsry);
        l.keepers = new address[](1);
        l.rewards = new uint256[](1);
        l.keepers[0] = keeper_;
        l.rewards[0] = reward_;
        l.fee = fee_;
        l.seizure = seizure_;
        l.token.setTransferBlocked(keeper_, true);
        l.token.setTransferBlocked(l.feeRecipient, true);
        l.token.setTransferBlocked(l.treasury, true);
        l.token.mint(address(burnerLoans), reward_ + seizure_);
        l.token.mint(alice, fee_);
        vm.prank(alice);
        assertTrue(l.token.approve(address(burnerLoans), fee_), "approve exact fee custody");
        burnerLoans.recordPendingFeeForTest(address(l.token), alice, l.feeRecipient, fee_);
        burnerLoans.recordPendingSeizedCollateralForTest(address(l.token), l.treasury, seizure_);
        burnerLoans.recordPendingSeizureRewardForTest(address(l.token), keeper_, reward_);
        l.token.setTransferBlocked(keeper_, false);
        l.token.setTransferBlocked(l.feeRecipient, false);
        l.token.setTransferBlocked(l.treasury, false);
        _assertPendingPayoutLedger(l);
    }

    /// @dev	Record another keeper's exact reward and return the expanded expected ledger.
    function _addPendingKeeperReward(
        Ledger memory l,
        address keeper_,
        uint256 reward_
    ) internal returns (Ledger memory) {
        assertTrue(
            _isPermittedDestination(keeper_, address(l.token)),
            "additional keeper is a valid fixture address"
        );
        for (uint256 i; i < l.keepers.length; ++i)
            assertNotEq(keeper_, l.keepers[i], "additional keeper is distinct");
        uint256 length = l.keepers.length;
        address[] memory keepers = new address[](length + 1);
        uint256[] memory rewards = new uint256[](length + 1);
        for (uint256 i; i < length; ++i) {
            keepers[i] = l.keepers[i];
            rewards[i] = l.rewards[i];
        }
        keepers[length] = keeper_;
        rewards[length] = reward_;
        l.keepers = keepers;
        l.rewards = rewards;
        l.token.mint(address(burnerLoans), reward_);
        l.token.setTransferBlocked(keeper_, true);
        burnerLoans.recordPendingSeizureRewardForTest(address(l.token), keeper_, reward_);
        l.token.setTransferBlocked(keeper_, false);
        _assertPendingPayoutLedger(l);
        return l;
    }

    /// @notice	Check whether an address is an allowed rescue destination.
    ///
    /// @param	destination_	Candidate transfer destination.
    /// @param	token_			Token being rescued; its own address cannot be the destination.
    /// @return	bool			True unless destination is zero, token, facility, Configurator or Kernel.
    function _isPermittedDestination(
        address destination_,
        address token_
    ) internal view returns (bool) {
        return
            destination_ != address(0) &&
            destination_ != token_ &&
            destination_ != address(burnerLoans) &&
            destination_ != address(burnerLoansConfig) &&
            destination_ != address(kernel);
    }

    /// @notice	Calculate the selected recipient's expected payout from the fixture ledger.
    /// @dev	Sum its keeper reward, fees when it is the fee recipient, and seizure when it is
    /// @dev	Treasury. Shared identities combine buckets; obligations to other addresses are excluded.
    /// @dev	This oracle uses only expected debts, never the contract's getter or preview.
    ///
    /// @param	l			Expected global debts and role identities.
    /// @param	recipient_	Original payout recipient whose entitlement is being checked.
    /// @return	amount		Total eligible pending payout in token base units; zero if none is owed.
    function _expectedRecipientPayout(
        Ledger memory l,
        address recipient_
    ) internal pure returns (uint256 amount) {
        for (uint256 i; i < l.keepers.length; ++i)
            if (l.keepers[i] == recipient_) amount += l.rewards[i];
        if (recipient_ == l.feeRecipient) amount += l.fee;
        if (recipient_ == l.treasury) amount += l.seizure;
    }

    /// @dev	Sum all expected debts for this token, including every keeper, regardless of recipient.
    function _totalPendingDebt(Ledger memory l) internal pure returns (uint256 amount) {
        amount = l.fee + l.seizure;
        for (uint256 i; i < l.rewards.length; ++i) amount += l.rewards[i];
    }

    /// @dev	Build rescue inputs for this ledger's token without changing the fixture.
    function _createRescueRequest(
        Ledger memory l,
        address recipient_,
        address destination_,
        uint256 amount_
    ) internal pure returns (Request memory) {
        return
            Request({
                token: address(l.token),
                recipient: recipient_,
                destination: destination_,
                amount: amount_
            });
    }

    /// @dev	Disable only the facility when requested; leave Kernel policy membership unchanged.
    function _disableFacilityIf(bool disabled_) internal {
        _disableBurnerLoansIf(disabled_);
    }

    /// @dev	Restore a snapshot so the next case starts with the same independent fixture.
    function _restoreSnapshot(uint256 snapshot_) internal {
        assertTrue(vm.revertToState(snapshot_), "restore independent fixture case");
    }

    /// @dev	Preview has no caller restrictions, including the zero caller. Its expected error
    /// is supplied separately because execution may fail at authorization or transfer.
    function _assertRescuePreview(
        Ledger memory l,
        Request memory request_,
        address caller_,
        bytes memory failure_
    ) internal {
        bytes32 beforeState = _payoutStateHash(l, request_.destination);
        vm.recordLogs();
        if (failure_.length != 0) vm.expectRevert(failure_);
        vm.prank(caller_);
        uint256 available = burnerLoans.previewRescuePendingPayout(
            request_.token,
            request_.recipient,
            request_.destination,
            request_.amount
        );
        if (failure_.length == 0)
            assertEq(
                available,
                _expectedRecipientPayout(l, request_.recipient),
                "preview equals independent entitlement"
            );
        assertEq(vm.getRecordedLogs().length, 0, "preview emits no events");
        assertEq(
            _payoutStateHash(l, request_.destination),
            beforeState,
            "preview preserves observed state"
        );
    }

    /// @dev	Check the preview independently, then exact execution error and complete state rollback.
    function _assertRescueReverts(
        Ledger memory l,
        Request memory request_,
        address caller_,
        bytes memory previewFailure_,
        bytes memory executionFailure_
    ) internal {
        _assertRescuePreview(l, request_, caller_, previewFailure_);
        bytes32 beforeState = _payoutStateHash(l, request_.destination);
        vm.expectRevert(executionFailure_);
        vm.prank(caller_);
        burnerLoans.rescuePendingPayout(
            request_.token,
            request_.recipient,
            request_.destination,
            request_.amount
        );
        assertEq(
            _payoutStateHash(l, request_.destination),
            beforeState,
            "rollback preserves ledger, balances, indexes, configuration and callback state"
        );
        _assertPendingPayoutLedger(l);
    }

    /// @dev	The test supplies expected reward/fee/seizure payments. This helper never chooses
    /// a debit order. Clone expected obligations here so callers can safely reuse their ledger.
    /// @dev	paid_ is [reward, fee, seizure] in base units. Check previews, bucket/custody debits,
    /// @dev	destination credit, events and indexes against these independently supplied payments.
    function _assertRescueSucceeds(
        Ledger memory l,
        address recipient_,
        address destination_,
        uint256 amount_,
        uint256[3] memory paid_
    ) internal {
        _assertRescueSucceedsAs(
            l,
            recipient_,
            destination_,
            amount_,
            paid_,
            address(burnerLoansConfig)
        );
    }

    /// @dev Apply the same complete payout assertions to the explicitly selected permitted caller.
    function _assertRescueSucceedsAs(
        Ledger memory l,
        address recipient_,
        address destination_,
        uint256 amount_,
        uint256[3] memory paid_,
        address caller_
    ) internal {
        assertTrue(
            _isPermittedDestination(destination_, address(l.token)),
            "success case has a permitted destination"
        );
        assertEq(
            paid_[0] + paid_[1] + paid_[2],
            amount_,
            "explicit payments sum to requested amount"
        );
        _assertRescuePreview(
            l,
            _createRescueRequest(l, recipient_, destination_, amount_),
            alice,
            ""
        );
        uint256 custody = l.token.balanceOf(address(burnerLoans));
        uint256 destinationBalance = l.token.balanceOf(destination_);
        uint256 transfers = l.token.transferCalls();
        if (paid_[0] != 0) {
            vm.expectEmit(true, true, true, true, address(burnerLoans));
            emit IBurnerLoansRescue.PendingSeizureRewardRescued(
                address(l.token),
                recipient_,
                destination_,
                paid_[0]
            );
        }
        if (paid_[1] != 0) {
            vm.expectEmit(true, true, false, true, address(burnerLoans));
            emit IBurnerLoansRescue.PendingFeeRescued(address(l.token), destination_, paid_[1]);
        }
        if (paid_[2] != 0) {
            vm.expectEmit(true, true, false, true, address(burnerLoans));
            emit IBurnerLoansRescue.PendingSeizureRescued(address(l.token), destination_, paid_[2]);
        }
        vm.expectEmit(true, true, false, true, address(l.token));
        emit IERC20.Transfer(address(burnerLoans), destination_, amount_);
        vm.recordLogs();
        vm.prank(caller_);
        burnerLoans.rescuePendingPayout(address(l.token), recipient_, destination_, amount_);
        assertEq(
            vm.getRecordedLogs().length,
            1 + (paid_[0] != 0 ? 1 : 0) + (paid_[1] != 0 ? 1 : 0) + (paid_[2] != 0 ? 1 : 0),
            "exact event count omits zero debit events"
        );
        assertEq(l.token.transferCalls(), transfers + 1, "exactly one committed transfer");
        assertEq(l.token.balanceOf(address(burnerLoans)), custody - amount_, "exact custody debit");
        assertEq(
            l.token.balanceOf(destination_),
            destinationBalance + amount_,
            "exact destination credit"
        );
        Ledger memory afterLedger = abi.decode(abi.encode(l), (Ledger));
        for (uint256 i; i < afterLedger.keepers.length; ++i)
            if (afterLedger.keepers[i] == recipient_) afterLedger.rewards[i] -= paid_[0];
        afterLedger.fee -= paid_[1];
        afterLedger.seizure -= paid_[2];
        _assertPendingPayoutLedger(afterLedger);
        uint256 remaining = _expectedRecipientPayout(afterLedger, recipient_);
        bytes memory failure = remaining == 0
            ? _insufficientPayoutError(address(l.token), 1, 0)
            : bytes("");
        _assertRescuePreview(
            afterLedger,
            _createRescueRequest(
                afterLedger,
                recipient_,
                destination_,
                remaining == 0 ? 1 : remaining
            ),
            alice,
            failure
        );
    }

    /// @dev	Encode the exact insufficient-payout error, including requested and available amounts.
    function _insufficientPayoutError(
        address token_,
        uint256 amount_,
        uint256 available_
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                IBurnerLoansRescue.BurnerLoans_InsufficientPendingPayout.selector,
                token_,
                amount_,
                available_
            );
    }

    /// @dev	Hash debts, balances, indexes, configuration and callback state to detect rollback failures.
    function _payoutStateHash(
        Ledger memory m,
        address destination_
    ) internal view returns (bytes32) {
        bytes memory keeperState;
        for (uint256 i; i < m.keepers.length; ++i)
            keeperState = abi.encode(
                keeperState,
                m.keepers[i],
                burnerLoans.pendingSeizureRewardForTest(address(m.token), m.keepers[i]),
                burnerLoans.pendingKeeperMemberForTest(address(m.token), m.keepers[i]),
                m.token.balanceOf(m.keepers[i])
            );
        bytes32 ledger = keccak256(
            abi.encode(
                keeperState,
                burnerLoans.pendingFeeForTest(address(m.token)),
                burnerLoans.pendingSeizureForTest(address(m.token)),
                burnerLoans.totalPendingForTest(address(m.token)),
                burnerLoans.getPendingPayoutTokens(),
                burnerLoans.getPendingPayoutRecipients(address(m.token))
            )
        );
        bytes32 balances = keccak256(
            abi.encode(
                m.token.balanceOf(address(burnerLoans)),
                m.token.balanceOf(destination_),
                m.token.balanceOf(m.feeRecipient),
                m.token.balanceOf(m.treasury),
                m.token.balanceOf(alice),
                m.token.totalSupply(),
                m.token.allowance(alice, address(burnerLoans))
            )
        );
        bytes32 configuration = _configurationHash();
        bytes32 callback = _callbackStateHash(m.token);
        return keccak256(abi.encode(ledger, balances, configuration, callback));
    }

    /// @dev	Hash transfer count and callback outcomes/observations, which must also roll back.
    function _callbackStateHash(RescuePendingToken token_) internal view returns (bytes32) {
        bytes32 outcome = keccak256(
            abi.encode(
                token_.transferCalls(),
                token_.callbackEnabled(),
                token_.callbackSucceeded(),
                token_.callbackRevertData(),
                token_.callbackRevertSelector(),
                token_.bubbleCallbackFailure()
            )
        );
        bytes32 observation = keccak256(
            abi.encode(
                token_.observedEntitlement(),
                token_.observedPreview(),
                token_.observedFailure(),
                token_.observedState()
            )
        );
        return keccak256(abi.encode(outcome, observation));
    }

    /// @notice	Fingerprint configuration, authority and lifecycle state.
    /// @dev	Shared by rollback checks and successful callback checks after arming the token.
    /// @return	Hash	of the facility configuration, Config operator and Kernel membership.
    function _configurationHash() internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    burnerLoans.priceCacheMaxAge(),
                    burnerLoans.revenueDistributor(),
                    burnerLoans.sendFeesToDistributor(),
                    burnerLoans.isEnabled(),
                    burnerLoansConfig.configOperator(),
                    kernel.isPolicyActive(Policy(address(burnerLoans)))
                )
            );
    }

    /// @dev	Compare each authoritative bucket and aggregate to the expected ledger, then check
    ///      getters and exact recipient/token membership, including overlapping role identities.
    function _assertPendingPayoutLedger(Ledger memory m) internal view {
        assertEq(
            burnerLoans.pendingFeeForTest(address(m.token)),
            m.fee,
            "authoritative fee equals independent model"
        );
        assertEq(
            burnerLoans.pendingSeizureForTest(address(m.token)),
            m.seizure,
            "authoritative seizure equals independent model"
        );
        assertEq(
            burnerLoans.totalPendingForTest(address(m.token)),
            _totalPendingDebt(m),
            "aggregate equals independent sum of all buckets"
        );
        address[] memory candidates = new address[](m.keepers.length + 2);
        for (uint256 i; i < m.keepers.length; ++i) {
            candidates[i] = m.keepers[i];
            assertEq(
                burnerLoans.pendingSeizureRewardForTest(address(m.token), m.keepers[i]),
                m.rewards[i],
                "each keeper reward equals independent model"
            );
            // A shared fee/Treasury identity can remain in the public union after its reward drains.
            // Check the keeper set directly so that remaining role debt cannot hide a stale entry.
            assertEq(
                burnerLoans.pendingKeeperMemberForTest(address(m.token), m.keepers[i]),
                m.rewards[i] != 0,
                "raw keeper index follows reward debt only"
            );
        }
        candidates[m.keepers.length] = m.feeRecipient;
        candidates[m.keepers.length + 1] = m.treasury;
        address[] memory recipients = burnerLoans.getPendingPayoutRecipients(address(m.token));
        uint256 expectedCount;
        for (uint256 i; i < candidates.length; ++i) {
            bool duplicate;
            for (uint256 j; j < i; ++j) if (candidates[j] == candidates[i]) duplicate = true;
            if (duplicate) continue;
            uint256 expected = _expectedRecipientPayout(m, candidates[i]);
            assertEq(
                burnerLoans.pendingPayout(address(m.token), candidates[i]),
                expected,
                "getter matches independent current-role entitlement"
            );
            uint256 occurrences;
            for (uint256 j; j < recipients.length; ++j)
                if (recipients[j] == candidates[i]) ++occurrences;
            assertEq(
                occurrences,
                expected == 0 ? 0 : 1,
                "recipient index exactly represents each nonempty entitlement"
            );
            if (expected != 0) ++expectedCount;
        }
        assertEq(
            recipients.length,
            expectedCount,
            "recipient index has no unknown or duplicate entries"
        );
        _assertPendingTokenIndex();
    }

    // A fully drained token disappears even if surplus remains in custody. Other tokens stay.
    /// @notice	Check exact pending-token index membership.
    /// @dev	Requires each known token exactly once iff its aggregate debt is nonzero,
    /// with no unknown entries. Surplus does not keep a drained token indexed.
    function _assertPendingTokenIndex() internal view {
        address[] memory tokens = burnerLoans.getPendingPayoutTokens();
        uint256 expectedTokens;
        for (uint256 i; i < _pendingTokens.length; ++i) {
            uint256 occurrences;
            for (uint256 j; j < tokens.length; ++j)
                if (tokens[j] == _pendingTokens[i]) ++occurrences;
            bool pending = burnerLoans.totalPendingForTest(_pendingTokens[i]) != 0;
            assertEq(occurrences, pending ? 1 : 0, "token index exactly represents pending tokens");
            if (pending) ++expectedTokens;
        }
        assertEq(tokens.length, expectedTokens, "token index has no unknown or duplicate entries");
    }
}
// forge-lint: disable-end(multi-contract-file,literal-instead-of-constant,calls-loop,unused-return)
