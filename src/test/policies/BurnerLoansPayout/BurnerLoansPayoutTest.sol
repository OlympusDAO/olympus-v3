// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Finite seed and invariant loops intentionally call real contracts.
// Literal amounts and endpoints are independent expected test values.
// Tests read state after calls to assert exact effects and rollback.
// forge-lint: disable-start(calls-loop, literal-instead-of-constant, reentrancy-no-eth)

// Interfaces
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansPayout} from "src/policies/interfaces/burnerloans/IBurnerLoansPayout.sol";

// Libraries
import {StdStorage, stdStorage} from "forge-std/StdStorage.sol";
import {ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansPayoutHarness} from "./fixtures/BurnerLoansPayoutHarness.sol";
import {Actions, Policy, toKeycode} from "src/Kernel.sol";
import {RevenueDistributor} from "src/policies/RevenueDistributor.sol";
import {BurnerLoansPayout} from "src/policies/burnerloans/BurnerLoansPayout.sol";
import {MockRevertingTransferToken} from "src/test/mocks/MockRevertingTransferToken.sol";
import {BurnerLoansModularTest} from "src/test/policies/BurnerLoansCore/fixtures/BurnerLoansModularTest.sol";

abstract contract BurnerLoansPayoutTest is BurnerLoansModularTest {
    using stdStorage for StdStorage;

    struct RecoveryCaller {
        address account;
        bool operatorOnly;
        bool overlap;
    }

    BurnerLoansPayoutHarness internal _subject;
    BurnerLoansPayout internal _otherPayout;
    MockRevertingTransferToken internal _token;
    MockRevertingTransferToken internal _otherToken;
    RevenueDistributor internal _distributor;
    address internal _keeper = address(0x1000);
    address internal _secondKeeper = address(0x1001);
    address internal _thirdKeeper = address(0x1002);
    address internal _destination = address(0x2000);
    address internal _controller = address(0xC0FFEE);

    function setUp() public virtual override {
        super.setUp();
        _otherPayout = _payout;
        _subject = new BurnerLoansPayoutHarness(_kernel, address(_core));
        _payout = _subject;
        _kernel.executeAction(Actions.ActivatePolicy, address(_payout));
        _payout.enable("");
        _core.setPayout(address(_payout));
        _payout.setConfigOperator(_controller);
        _token = new MockRevertingTransferToken(6);
        _otherToken = new MockRevertingTransferToken(6);
    }

    modifier givenPendingBuckets() {
        _seedBuckets(10, 20, 30, _keeper);
        _;
    }

    function _treasury() internal view returns (address) {
        return address(_kernel.getModuleForKeycode(toKeycode("TRSRY")));
    }

    function _deactivatePayoutWithBrokenRoles(address caller_, bool enabled_) internal {
        vm.assume(caller_ != address(_core));
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE) && caller_ != _payout.configOperator());
        _setState(_payout, false, enabled_);
        vm.mockCallRevert(address(_roles), bytes(""), hex"deadbeef");
    }

    function _expectInactivePayout() internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_payout)
            )
        );
    }

    function _feeRecipient() internal view returns (address) {
        return _payout.sendFeesToDistributor() ? _payout.revenueDistributor() : _treasury();
    }

    function _installDistributor() internal returns (RevenueDistributor distributor) {
        distributor = new RevenueDistributor(_kernel);
        _kernel.executeAction(Actions.ActivatePolicy, address(distributor));
        distributor.enable("");
    }

    function _bindDistributor() internal {
        _distributor = _installDistributor();
        _payout.setRevenueDistributor(address(_distributor));
    }

    function _useDistributor() internal {
        _bindDistributor();
        _payout.setSendFeesToDistributor(true);
    }

    function _creditFee(MockRevertingTransferToken token_, uint256 amount_) internal {
        token_.mint(address(_payout), amount_);
        vm.prank(address(_core));
        _payout.creditFee(address(token_), amount_);
    }

    function _deferFee(MockRevertingTransferToken token_, uint256 amount_) internal {
        token_.setTransferReverts(_feeRecipient(), true);
        _creditFee(token_, amount_);
    }

    function _creditSeizure(
        MockRevertingTransferToken token_,
        address keeper_,
        uint256 reward_,
        uint256 seizure_
    ) internal {
        token_.mint(address(_payout), reward_ + seizure_);
        vm.prank(address(_core));
        _payout.creditSeizure(address(token_), keeper_, reward_, seizure_);
    }

    function _deferSeizure(
        MockRevertingTransferToken token_,
        address keeper_,
        uint256 reward_,
        uint256 seizure_
    ) internal {
        token_.setTransferReverts(keeper_, true);
        token_.setTransferReverts(_treasury(), true);
        _creditSeizure(token_, keeper_, reward_, seizure_);
    }

    function _seedBuckets(
        uint256 fee_,
        uint256 seized_,
        uint256 reward_,
        address keeper_
    ) internal {
        _deferFee(_token, fee_);
        _deferSeizure(_token, keeper_, reward_, seized_);
    }

    function _setState(Policy policy_, bool active_, bool enabled_) internal {
        if (!enabled_) IEnabler(address(policy_)).disable("");
        if (!active_) _kernel.executeAction(Actions.DeactivatePolicy, address(policy_));
    }

    function _grantPauseCaller(address caller_, bool emergency_, bool overlap_) internal {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(emergency_ ? EMERGENCY_ROLE : ADMIN_ROLE, caller_);
        if (overlap_) _rolesAdmin.grantRole(emergency_ ? ADMIN_ROLE : EMERGENCY_ROLE, caller_);
    }

    function _recoveryCallers() internal pure returns (RecoveryCaller[3] memory) {
        return [
            RecoveryCaller({account: address(0xabc1), operatorOnly: false, overlap: false}), // ADMIN only
            RecoveryCaller({account: address(0xabc2), operatorOnly: true, overlap: false}), // configOperator only
            RecoveryCaller({account: address(0xabc3), operatorOnly: false, overlap: true}) // both
        ];
    }

    function _grantRecoveryCaller(address caller_, bool operatorOnly_, bool overlap_) internal {
        vm.assume(
            caller_ != address(0) &&
                caller_ != address(this) &&
                caller_ != _controller &&
                caller_ != _destination &&
                caller_ != _keeper &&
                caller_ != _secondKeeper &&
                caller_ != _thirdKeeper &&
                caller_ != _treasury() &&
                caller_ != address(_distributor)
        );
        if (operatorOnly_ || overlap_) _payout.setConfigOperator(caller_);
        if (!operatorOnly_ || overlap_) _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
    }

    function _ledgerDigest() internal view returns (bytes32) {
        return keccak256(abi.encode(_unrelatedDigest(), _payout.getPendingPayoutTokens()));
    }

    function _unrelatedDigest() internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    _bucketDigest(address(_token)),
                    _bucketDigest(address(_otherToken)),
                    _balanceDigest(),
                    _retiredDigest()
                )
            );
    }

    function _bucketDigest(address token_) internal view returns (bytes32) {
        (uint256 fee, uint256 seized, uint256 total) = _payout.payoutReserves(token_);
        return
            keccak256(
                abi.encode(
                    fee,
                    seized,
                    total,
                    _subject.keeperReward(token_, _keeper),
                    _subject.keeperReward(token_, _secondKeeper),
                    _subject.keeperReward(token_, _thirdKeeper),
                    _subject.keeperReward(token_, _treasury()),
                    _subject.keeperReward(token_, address(_distributor)),
                    _payout.getPendingKeepers(token_),
                    _subject.hasPendingToken(token_)
                )
            );
    }

    function _balanceDigest() internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    _token.balanceOf(address(_payout)),
                    _token.balanceOf(_destination),
                    _token.balanceOf(_treasury()),
                    _token.balanceOf(_keeper),
                    _token.balanceOf(_secondKeeper),
                    _token.balanceOf(address(_distributor)),
                    _token.totalSupply(),
                    _otherToken.balanceOf(address(_payout)),
                    _otherToken.totalSupply()
                )
            );
    }

    function _retiredDigest() internal view returns (bytes32) {
        (uint256 fee, uint256 seized, uint256 total) = _otherPayout.payoutReserves(address(_token));
        return
            keccak256(
                abi.encode(
                    fee,
                    seized,
                    total,
                    _token.balanceOf(address(_otherPayout)),
                    _otherPayout.getPendingPayoutTokens()
                )
            );
    }

    function _assertBuckets(
        address token_,
        address keeper_,
        uint256 fee_,
        uint256 seized_,
        uint256 reward_,
        uint256 total_
    ) internal view {
        (uint256 fee, uint256 seized, uint256 total) = _payout.payoutReserves(token_);
        assertEq(fee, fee_, "Raw fee reserve");
        assertEq(seized, seized_, "Raw seized-collateral reserve");
        assertEq(total, total_, "Aggregate reserve");
        assertEq(_subject.keeperReward(token_, keeper_), reward_, "Raw original-keeper reward");
        assertEq(
            _subject.hasPendingToken(token_),
            total_ != 0,
            "Stored token-set membership agrees with liabilities"
        );
        assertEq(
            _subject.hasPendingKeeper(token_, keeper_),
            reward_ != 0,
            "Stored keeper-set membership agrees with reward"
        );
    }

    function _expectPayoutTransferred(
        address recipient_,
        IBurnerLoansPayout.PayoutKind kind_,
        uint256 amount_
    ) internal {
        vm.expectEmit(address(_payout));
        emit IBurnerLoansPayout.PayoutTransferred(address(_token), recipient_, kind_, amount_);
    }

    function _expectPayoutDeferred(
        address recipient_,
        IBurnerLoansPayout.PayoutKind kind_,
        uint256 amount_
    ) internal {
        vm.expectEmit(address(_payout));
        emit IBurnerLoansPayout.PayoutDeferred(address(_token), recipient_, kind_, amount_);
    }

    function _invalidDistributorError(address candidate_) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                IBurnerLoansPayout.BurnerLoans_InvalidRevenueDistributor.selector,
                candidate_
            );
    }

    function _flagSlot(string memory getter_) internal returns (uint256) {
        return stdstore.target(address(_payout)).sig(getter_).enable_packed_slots().find();
    }

    function _assertNoWriteToFlag(uint256 slot_) internal view {
        // This assertion needs written slots only; reads are deliberately discarded.
        // forge-lint: disable-next-line(unused-return)
        (, bytes32[] memory writes) = vm.accesses(address(_payout));
        for (uint256 i; i < writes.length; ++i)
            assertTrue(
                writes[i] != bytes32(slot_),
                "No setter write to the packed routing flags; guard writes are independent"
            );
    }

    function _restore(uint256 snapshot_) internal {
        assertTrue(vm.revertToState(snapshot_), "Restore independent test fixture");
        vm.clearMockedCalls();
    }
}

// forge-lint: disable-end(calls-loop, literal-instead-of-constant, reentrancy-no-eth)
