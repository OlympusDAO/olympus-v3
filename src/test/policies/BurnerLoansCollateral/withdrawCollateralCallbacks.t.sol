// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IBurnerLoansCollateral} from "src/policies/interfaces/burnerloans/IBurnerLoansCollateral.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Libraries
import {IERC20 as OZERC20} from "@openzeppelin-5.7.0/token/ERC20/IERC20.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansCollateralTokenCallbackTest} from "./fixtures/BurnerLoansCollateralTokenCallbackTest.sol";
import {ReentrancyGuard} from "@openzeppelin-5.7.0/utils/ReentrancyGuard.sol";
import {MockERC7575Vault} from "src/test/mocks/MockERC7575Vault.sol";
import {ReentrantFeeToken} from "src/test/mocks/ReentrantFeeToken.sol";

// Fixed boundary values, bound-checked casts and unused revert-path returns are intentional.
// Fixture/seed loops call real dependencies; sequential setup calls are completed before reuse.
// forge-lint: disable-start(literal-instead-of-constant,unsafe-typecast,unused-return,calls-loop,reentrancy-no-eth)

contract BurnerLoansCollateralWithdrawCollateralCallbacksTest is
    BurnerLoansCollateralTokenCallbackTest
{
    // Scenarios: BLCOL-WITHDRAW-C05.
    function test_givenUnderlyingDeliveryCallback_whenActionReentryCaught() public {
        _prepareDirectToken();
        _quoteWithdrawal();
        _armNestedWithdrawal(address(_depositManager));
        _assertWithdrawalCaught();
    }

    // Scenarios: BLCOL-WITHDRAW-C05.
    function test_givenUnderlyingDeliveryCallback_whenCoreReentryCaught() public {
        _prepareDirectToken();
        _quoteWithdrawal();
        _armCoreConfiguration(address(_depositManager));
        _assertWithdrawalCaught();
    }

    // Scenarios: BLCOL-WITHDRAW-C06.
    function test_givenUnderlyingDeliveryCallback_whenActionReentryPropagated() public {
        _prepareDirectToken();
        _quoteWithdrawal();
        _armNestedWithdrawal(address(_depositManager));
        _token.setBubbleCallbackFailure(true);
        _assertWithdrawalRejected();
    }

    // Scenarios: BLCOL-WITHDRAW-C06.
    function test_givenUnderlyingDeliveryCallback_whenCoreReentryPropagated() public {
        _prepareDirectToken();
        _quoteWithdrawal();
        _armCoreConfiguration(address(_depositManager));
        _token.setBubbleCallbackFailure(true);
        _assertWithdrawalRejected();
    }

    // Scenarios: BLCOL-WITHDRAW-C05.
    function test_givenVaultRedemptionCallback_whenActionReentryCaught() public {
        _prepareVaultToken();
        _quoteWithdrawal();
        _armNestedWithdrawal(address(_vault));
        _assertWithdrawalCaught();
    }

    // Scenarios: BLCOL-WITHDRAW-C05.
    function test_givenVaultRedemptionCallback_whenCoreReentryCaught() public {
        _prepareVaultToken();
        _quoteWithdrawal();
        _armCoreConfiguration(address(_vault));
        _assertWithdrawalCaught();
    }

    // Scenarios: BLCOL-WITHDRAW-C06.
    function test_givenVaultRedemptionCallback_whenActionReentryPropagated() public {
        _prepareVaultToken();
        _quoteWithdrawal();
        _armNestedWithdrawal(address(_vault));
        _token.setBubbleCallbackFailure(true);
        _assertWithdrawalRejected();
    }

    // Scenarios: BLCOL-WITHDRAW-C06.
    function test_givenVaultRedemptionCallback_whenCoreReentryPropagated() public {
        _prepareVaultToken();
        _quoteWithdrawal();
        _armCoreConfiguration(address(_vault));
        _token.setBubbleCallbackFailure(true);
        _assertWithdrawalRejected();
    }

    function _quoteWithdrawal() internal {
        bytes32 beforeState = _accountingDigest(address(_token));
        vm.prank(_borrower);
        IBurnerLoansCollateral.WithdrawPreview memory quote = _collateral.previewWithdrawCollateral(
            address(_token),
            1e18,
            _borrower,
            _recipient
        );
        _assertWithdrawal(quote, address(_token), 1e18, 9e18, type(uint256).max);
        assertEq(_accountingDigest(address(_token)), beforeState, "Quote preserves all accounting");
    }

    // Scenarios: BLCOL-WITHDRAW-AUTH-C01.
    function test_givenDelegatedWithdrawal_whenAccountCancelsDuringDelivery_reverts() public {
        _assertWithdrawalAuthorizationMutationRollback(false);
    }

    // Scenarios: BLCOL-WITHDRAW-AUTH-C02.
    function test_givenDelegatedWithdrawal_whenIdenticalPermissionsReacceptedDuringDelivery_reverts()
        public
    {
        _assertWithdrawalAuthorizationMutationRollback(true);
    }

    function _assertWithdrawalAuthorizationMutationRollback(bool replace_) internal {
        _prepareDirectToken();
        _depositAsset(_token, 10e18, address(_token));
        _approveOperatorForAsset(address(_token), _recipient, type(uint48).max, address(_token));
        IOperatorAuth.Grant memory replacement = _operatorGrantForAsset(
            address(_token),
            _recipient,
            type(uint48).max,
            address(_token)
        );
        bytes memory callback = replace_
            ? abi.encodeCall(_auth.approveGrant, (replacement))
            : abi.encodeCall(_auth.cancelGrant, (_recipient));
        _token.setCallbackFrom(address(_depositManager), address(_auth), callback);
        bytes32 beforeAccounting = _accountingDigest(address(_token));
        uint256 beforeEpoch = _auth.pairEpochs(address(_token), _recipient);
        uint256 beforeRecipient = _token.balanceOf(_recipient);
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidContext.selector);
        vm.prank(_recipient);
        _collateral.withdrawCollateral(address(_token), 1e18, address(_token), _recipient);
        assertEq(
            _accountingDigest(address(_token)),
            beforeAccounting,
            "Completion failure restores all accounting"
        );
        assertEq(_token.balanceOf(_recipient), beforeRecipient, "Delivered underlying rolled back");
        assertEq(
            _auth.pairEpochs(address(_token), _recipient),
            beforeEpoch,
            "Callback replacement or cancellation rolled back"
        );
        assertEq(
            _lens.getPosition(address(_token), address(_token)).depositedCollateral,
            10e18,
            "Account collateral fully restored"
        );
        assertTrue(_token.callbackEnabled(), "Callback state rolled back");
    }

    function _assertWithdrawalCaught() internal {
        uint256 beforeWallet = _token.balanceOf(_recipient);
        vm.prank(_borrower);
        IBurnerLoansCollateral.WithdrawPreview memory actual = _collateral.withdrawCollateral(
            address(_token),
            1e18,
            _borrower,
            _recipient
        );
        _assertWithdrawal(actual, address(_token), 1e18, 9e18, type(uint256).max);
        assertEq(_token.balanceOf(_recipient), beforeWallet + 1e18, "One recipient delivery");
        assertEq(
            _depositManager.getOperatorLiabilities(IERC20(address(_token)), address(_core)),
            9e18 + 17,
            "One liability debit with unrelated borrower preserved"
        );
        assertEq(_core.gracePeriod(), 7 days, "Nested configuration is rejected");
        _assertGuardCaught();
    }

    function _assertWithdrawalRejected() internal {
        bytes32 beforeState = _accountingDigest(address(_token));
        vm.expectRevert(ReentrantFeeToken.CallbackFailed.selector);
        vm.prank(_borrower);
        _collateral.withdrawCollateral(address(_token), 1e18, _borrower, _recipient);
        assertEq(
            _accountingDigest(address(_token)),
            beforeState,
            "Mandatory withdrawal callback fully rolls back"
        );
        assertTrue(_token.callbackEnabled(), "Callback arming restored after rollback");
    }

    // Scenarios: BLCOL-WITHDRAW-C05.
    function test_givenShareDeliveryCallback_whenActionReentryCaught() public {
        ReentrantFeeToken shares = _prepareExternalShares();
        vm.prank(_borrower);
        _approveOperatorForAsset(_borrower, address(shares), type(uint48).max, address(_token));
        shares.setCallbackFrom(
            address(_depositManager),
            address(_collateral),
            abi.encodeCall(
                _collateral.withdrawCollateral,
                (address(_token), uint128(1), _borrower, address(shares))
            )
        );
        _assertShareWithdrawalCaught(shares);
    }

    // Scenarios: BLCOL-WITHDRAW-C06.
    function test_givenShareDeliveryCallback_whenActionReentryPropagated() public {
        ReentrantFeeToken shares = _prepareExternalShares();
        vm.prank(_borrower);
        _approveOperatorForAsset(_borrower, address(shares), type(uint48).max, address(_token));
        shares.setCallbackFrom(
            address(_depositManager),
            address(_collateral),
            abi.encodeCall(
                _collateral.withdrawCollateral,
                (address(_token), uint128(1), _borrower, address(shares))
            )
        );
        shares.setBubbleCallbackFailure(true);
        _assertShareWithdrawalRejected(shares);
    }

    // Scenarios: BLCOL-WITHDRAW-C05.
    function test_givenShareDeliveryCallback_whenCoreReentryCaught() public {
        ReentrantFeeToken shares = _prepareExternalShares();
        _rolesAdmin.grantRole(ADMIN_ROLE, address(shares));
        shares.setCallbackFrom(
            address(_depositManager),
            address(_core),
            abi.encodeCall(_core.setGracePeriod, (uint32(1)))
        );
        _assertShareWithdrawalCaught(shares);
    }

    // Scenarios: BLCOL-WITHDRAW-C06.
    function test_givenShareDeliveryCallback_whenCoreReentryPropagated() public {
        ReentrantFeeToken shares = _prepareExternalShares();
        _rolesAdmin.grantRole(ADMIN_ROLE, address(shares));
        shares.setCallbackFrom(
            address(_depositManager),
            address(_core),
            abi.encodeCall(_core.setGracePeriod, (uint32(1)))
        );
        shares.setBubbleCallbackFailure(true);
        _assertShareWithdrawalRejected(shares);
    }

    function _assertShareWithdrawalCaught(ReentrantFeeToken shares_) internal {
        vm.prank(_borrower);
        IBurnerLoansCollateral.WithdrawPreview memory result = _collateral.withdrawCollateral(
            address(_token),
            1e18,
            _borrower,
            _recipient
        );
        _assertWithdrawal(result, address(shares_), 1e18, 9e18, type(uint256).max);
        assertEq(shares_.balanceOf(_recipient), 1e18, "One native share delivery");
        assertEq(
            shares_.callbackRevertData(),
            abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector),
            "Share callback reaches Core guard"
        );
        assertEq(
            _lens.getPosition(address(_token), _OTHER_BORROWER).depositedCollateral,
            17,
            "Unrelated position preserved"
        );
    }

    function _assertShareWithdrawalRejected(ReentrantFeeToken shares_) internal {
        bytes32 beforeState = _accountingDigest(address(_token));
        uint256 beforeShares = shares_.balanceOf(address(_depositManager));
        vm.expectRevert(ReentrantFeeToken.CallbackFailed.selector);
        vm.prank(_borrower);
        _collateral.withdrawCollateral(address(_token), 1e18, _borrower, _recipient);
        assertEq(
            _accountingDigest(address(_token)),
            beforeState,
            "Share callback restores accounting"
        );
        assertEq(shares_.balanceOf(_recipient), 0, "No failed share delivery");
        assertEq(
            shares_.balanceOf(address(_depositManager)),
            beforeShares,
            "Share custody restored"
        );
    }

    function _prepareExternalShares() internal returns (ReentrantFeeToken shares) {
        _token = new ReentrantFeeToken();
        shares = new ReentrantFeeToken();
        MockERC7575Vault vault = new MockERC7575Vault(OZERC20(address(_token)), true);
        vault.setReportedShare(address(shares));
        _admitVault(_token, address(vault), true);
        _fundCallbackParticipants();
        bytes32 beforeState = _accountingDigest(address(_token));
        vm.prank(_borrower);
        IBurnerLoansCollateral.WithdrawPreview memory quote = _collateral.previewWithdrawCollateral(
            address(_token),
            1e18,
            _borrower,
            _recipient
        );
        _assertWithdrawal(quote, address(shares), 1e18, 9e18, type(uint256).max);
        assertEq(
            _accountingDigest(address(_token)),
            beforeState,
            "Share quote leaves balances unchanged"
        );
    }
}

// forge-lint: disable-end(literal-instead-of-constant,unsafe-typecast,unused-return,calls-loop,reentrancy-no-eth)
