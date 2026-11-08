// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansPayout} from "src/policies/interfaces/burnerloans/IBurnerLoansPayout.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";

// Libraries
import {LoanPositions} from "src/policies/burnerloans/libraries/LoanPositions.sol";

// Contracts
import {Actions, Policy} from "src/Kernel.sol";
import {BurnerLoansModularTest} from "src/test/policies/BurnerLoansCore/fixtures/BurnerLoansModularTest.sol";

// Test vectors use fixed expected values and bounds-checked casts. Seed loops exercise real dependencies.
// Setup and expected-revert calls are checked through authoritative state assertions.
// forge-lint: disable-start(calls-loop, literal-instead-of-constant, unused-return)

abstract contract BurnerLoansDebtTest is BurnerLoansModularTest {
    uint256 internal constant _HEALTH = 2e18;

    modifier givenMockDebt() {
        _depositCollateral(2000e6);
        _mockRisk(0);
        vm.prank(_borrower);
        _debt.borrow(address(_asset), 100e9, _borrower, _borrower, 0, address(0));
        _;
    }

    function _setPolicyState(Policy subject_, bool active_, bool enabled_) internal {
        if (!enabled_) IEnabler(address(subject_)).disable("");
        if (!active_) _kernel.executeAction(Actions.DeactivatePolicy, address(subject_));
    }

    function _stateDigest(address payer_) internal view returns (bytes32) {
        return _stateDigestFor(address(_asset), payer_);
    }

    function _stateDigestFor(address asset_, address payer_) internal view returns (bytes32) {
        uint32 market = _core.marketId(asset_);
        bytes32 accounting = keccak256(
            abi.encode(
                _lens.getPosition(asset_, _borrower),
                _floan.getMarketPrincipalDue(market),
                _floan.getMarketCollateral(market),
                _floan.getPositionCount(),
                _floan.getActiveBorrowers(market),
                _inventory.activePrincipalOhm(),
                _inventory.providerClaimOhm(payer_)
            )
        );
        bytes32 balances = keccak256(
            abi.encode(
                _walletDigest(IERC20(asset_), payer_),
                _walletDigest(IERC20(address(_ohm)), payer_)
            )
        );
        return
            keccak256(
                abi.encode(accounting, balances, _payoutDigest(asset_), _custodyDigest(asset_))
            );
    }

    function _payoutDigest(address asset_) internal view returns (bytes32) {
        (uint256 fees, , uint256 seized, , uint256 total) = _payout.pendingAmounts(asset_);
        return
            keccak256(
                abi.encode(
                    fees,
                    seized,
                    total,
                    _payout.getPendingPayoutTokens(),
                    _payout.getPendingPayoutRecipients(asset_),
                    _referralReservesDigest(asset_)
                )
            );
    }

    function _custodyDigest(address asset_) internal view returns (bytes32) {
        uint256 receipt = _depositManager.getReceiptTokenId(IERC20(asset_), 1, address(_core));
        return
            keccak256(
                abi.encode(
                    _depositManager.getOperatorLiabilities(IERC20(asset_), address(_core)),
                    _depositManager.getBorrowedAmount(IERC20(asset_), address(_core)),
                    _depositManager.getReceiptTokenManager().balanceOf(address(_core), receipt),
                    _depositManager.getReceiptTokenManager().allowance(
                        address(_core),
                        address(_depositManager),
                        receipt
                    )
                )
            );
    }

    function _walletDigest(IERC20 token_, address payer_) internal view returns (bytes32) {
        bytes32 wallets = keccak256(
            abi.encode(
                token_.balanceOf(payer_),
                token_.balanceOf(_borrower),
                token_.balanceOf(_recipient),
                token_.balanceOf(address(_core)),
                token_.balanceOf(address(_inventory)),
                token_.balanceOf(address(_payout)),
                token_.balanceOf(address(_depositManager))
            )
        );
        return
            keccak256(
                abi.encode(
                    wallets,
                    token_.totalSupply(),
                    token_.allowance(payer_, address(_core)),
                    token_.allowance(_borrower, address(_core)),
                    token_.allowance(_recipient, address(_core))
                )
            );
    }

    function _authorizeOperator(address operator_, uint48 deadline_) internal {
        vm.prank(_borrower);
        _core.setAuthorization(operator_, deadline_);
    }

    function _authorizeFeePayer(bool operator_) internal returns (address payer) {
        payer = operator_ ? _recipient : _borrower;
        if (operator_) _authorizeOperator(payer, type(uint48).max);
    }

    function _fundFeePayer(address payer_, uint256 fee_) internal {
        uint256 balance = _asset.balanceOf(payer_);
        if (fee_ > balance) _asset.mint(payer_, fee_ - balance);
        vm.prank(payer_);
        assertTrue(_asset.approve(address(_core), fee_), "Payer grants the fee allowance");
    }

    function _fundRepayer(address payer_, uint256 amount_) internal {
        _ohm.mint(payer_, amount_);
        vm.prank(payer_);
        _ohm.approve(address(_core), amount_);
    }

    function _mockRiskSnapshotFailure(bytes memory reason_) internal {
        vm.mockCallRevert(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.refreshSnapshot.selector),
            reason_
        );
        vm.mockCallRevert(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.snapshot.selector),
            reason_
        );
    }

    function _depositCollateral(uint128 amount_) internal {
        _asset.mint(_borrower, amount_);
        vm.prank(_borrower);
        _collateral.depositCollateral(address(_asset), amount_, _borrower);
    }

    function _position() internal view returns (IFLOANv1.Position memory position) {
        (, , position) = LoanPositions.forCore(_core, address(_asset), _borrower);
    }

    function _mockRisk(uint256 fee_) internal {
        IBurnerLoansCore.PriceSnapshot memory snapshot = IBurnerLoansCore.PriceSnapshot(
            1e18,
            1e18,
            1e18
        );
        vm.mockCall(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.refreshSnapshot.selector),
            abi.encode(snapshot)
        );
        vm.mockCall(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.snapshot.selector),
            abi.encode(snapshot)
        );
        vm.mockCall(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.fee.selector),
            abi.encode(fee_, uint256(0))
        );
        vm.mockCall(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.validateHealth.selector),
            abi.encode(_HEALTH)
        );
        vm.mockCall(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.health.selector),
            abi.encode(_HEALTH)
        );
    }

    function _retainFee() internal {
        vm.mockCall(
            address(_payout),
            abi.encodeWithSelector(IBurnerLoansPayout.creditFee.selector),
            ""
        );
    }

    function _expectBorrowRevert(
        bytes memory reason_,
        uint128 amount_,
        address recipient_,
        uint256 maxFee_,
        address caller_
    ) internal {
        bytes32 beforeState = _stateDigest(caller_);
        vm.expectRevert(reason_);
        vm.prank(caller_);
        _debt.previewBorrow(address(_asset), amount_, _borrower, recipient_, maxFee_, address(0));
        assertEq(
            _stateDigest(caller_),
            beforeState,
            "Rejected preview preserves accounting and custody"
        );
        _expectBorrowExecutionRevert(reason_, amount_, recipient_, maxFee_, caller_);
    }

    function _expectExtendRevert(
        bytes memory reason_,
        uint16 terms_,
        uint256 maxFee_,
        address caller_
    ) internal {
        bytes32 beforeState = _stateDigest(caller_);
        vm.expectRevert(reason_);
        vm.prank(caller_);
        _debt.previewExtend(address(_asset), _borrower, terms_, maxFee_, address(0));
        assertEq(_stateDigest(caller_), beforeState, "Rejected preview preserves accounting");
        _expectExtendExecutionRevert(reason_, terms_, maxFee_, caller_);
    }

    function _expectRepayRevert(
        bytes memory reason_,
        uint128 amount_,
        address borrower_,
        address payer_
    ) internal {
        bytes32 beforeState = _stateDigest(payer_);
        vm.expectRevert(reason_);
        vm.prank(payer_);
        _debt.previewRepay(address(_asset), amount_, borrower_);
        assertEq(
            _stateDigest(payer_),
            beforeState,
            "Rejected preview preserves accounting and custody"
        );
        vm.expectRevert(reason_);
        vm.prank(payer_);
        _debt.repay(address(_asset), amount_, borrower_);
        assertEq(
            _stateDigest(payer_),
            beforeState,
            "Rejected action restores accounting, custody, indexes and allowances"
        );
    }

    function _expectBorrowExecutionRevert(
        bytes memory reason_,
        uint128 amount_,
        address recipient_,
        uint256 maxFee_,
        address caller_
    ) internal {
        bytes32 beforeState = _stateDigest(caller_);
        vm.expectRevert(reason_);
        vm.prank(caller_);
        _debt.borrow(address(_asset), amount_, _borrower, recipient_, maxFee_, address(0));
        assertEq(
            _stateDigest(caller_),
            beforeState,
            "Rejected action restores accounting, custody, indexes and allowances"
        );
    }

    function _expectExtendExecutionRevert(
        bytes memory reason_,
        uint16 terms_,
        uint256 maxFee_,
        address caller_
    ) internal {
        bytes32 beforeState = _stateDigest(caller_);
        IFLOANv1.Position memory beforePosition = _position();
        vm.expectRevert(reason_);
        vm.prank(caller_);
        _debt.extend(address(_asset), _borrower, terms_, maxFee_, address(0));
        assertEq(
            keccak256(abi.encode(_position())),
            keccak256(abi.encode(beforePosition)),
            "Failed extension preserves position"
        );
        assertEq(
            _stateDigest(caller_),
            beforeState,
            "Rejected extension restores all ledgers and allowances"
        );
    }
}

// forge-lint: disable-end(calls-loop, literal-instead-of-constant, unused-return)
