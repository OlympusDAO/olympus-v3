// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.34;

// Interfaces
import {IERC20} from "@openzeppelin-5.7.0/token/ERC20/IERC20.sol";
import {IBurnerLoansComposites as IExecutor} from "src/periphery/interfaces/IBurnerLoansComposites.sol";

// Libraries
import {SafeERC20} from "@openzeppelin-5.7.0/token/ERC20/utils/SafeERC20.sol";

// Contracts
import {Ownable} from "@openzeppelin-5.7.0/access/Ownable.sol";
import {ReentrancyGuardTransient} from "@openzeppelin-5.7.0/utils/ReentrancyGuardTransient.sol";
import {BurnerLoansCompositesTest} from "./fixtures/BurnerLoansCompositesTest.sol";
import {CoreCallbackToken} from "src/test/policies/BurnerLoansCore/fixtures/CoreCallbackToken.sol";

contract BurnerLoansCompositesRescueTest is BurnerLoansCompositesTest {
    // Scenarios: BLCRSC-P01.
    function test_givenBalance_whenOwnerRescues(uint256 balance_) public {
        uint256 balance = bound(balance_, 1, type(uint256).max);
        CoreCallbackToken token = new CoreCallbackToken();
        token.mint(address(_executor), balance);

        vm.expectEmit(address(_executor));
        emit IExecutor.TokenRescued(address(token), address(this), balance);
        _executor.rescue(address(token));

        assertEq(token.balanceOf(address(this)), balance, "Owner receives the full balance");
        assertEq(token.balanceOf(address(_executor)), 0, "Composites retains no rescued token");
    }

    // Scenarios: BLCRSC-P02.
    function test_givenDisabled_whenOwnerRescues() public {
        _asset.mint(address(_executor), 1);
        uint256 beforeBalance = _asset.balanceOf(address(this));
        _executor.disable("");

        _executor.rescue(address(_asset));

        assertEq(_asset.balanceOf(address(this)), beforeBalance + 1, "Owner recovers the token");
        assertFalse(_executor.isEnabled(), "Rescue leaves execution disabled");
    }

    // Scenarios: BLCRSC-P03, BLCRSC-A02.
    function test_givenNewOwner_whenRescuing() public {
        address newOwner = makeAddr("newOwner");
        _executor.transferOwnership(newOwner);
        vm.prank(newOwner);
        _executor.acceptOwnership();
        _asset.mint(address(_executor), 1);

        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this))
        );
        _executor.rescue(address(_asset));
        vm.prank(newOwner);
        _executor.rescue(address(_asset));

        assertEq(_asset.balanceOf(newOwner), 1, "Rescue pays the current owner");
    }

    // Scenarios: BLCRSC-P04.
    function test_givenEmptyBalance_whenOwnerRescues() public {
        vm.expectCall(address(_asset), abi.encodePacked(IERC20.transfer.selector), 0);
        _executor.rescue(address(_asset));
        assertEq(_asset.balanceOf(address(_executor)), 0, "Empty balance stays empty");
    }

    // Scenarios: BLCRSC-A01.
    function test_whenCallerIsNotOwner_reverts(address caller_) public {
        vm.assume(caller_ != _executor.owner());
        _asset.mint(address(_executor), 1);

        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, caller_)
        );
        vm.prank(caller_);
        _executor.rescue(address(_asset));

        assertEq(_asset.balanceOf(address(_executor)), 1, "Unauthorized call leaves funds intact");
    }

    // Scenarios: BLCRSC-I01.
    function test_whenTokenHasNoCode_reverts(address token_) public {
        vm.assume(token_.code.length == 0);
        vm.expectRevert(
            abi.encodeWithSelector(IExecutor.BurnerLoansComposites_InvalidToken.selector, token_)
        );
        _executor.rescue(token_);
    }

    // Scenarios: BLCRSC-T01.
    function test_whenTransferFails_reverts() public {
        _asset.mint(address(_executor), 1);
        vm.mockCall(
            address(_asset),
            abi.encodeCall(IERC20.transfer, (address(this), 1)),
            abi.encode(false)
        );
        vm.expectRevert(
            abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(_asset))
        );
        _executor.rescue(address(_asset));
        assertEq(_asset.balanceOf(address(_executor)), 1, "Failed transfer retains the balance");
    }

    // Scenarios: BLCRSC-C01.
    function test_whenTransferCallsOwnerDuringRescue_reverts() public {
        CoreCallbackToken token = new CoreCallbackToken();
        token.mint(address(_executor), 1);
        _asset.mint(address(_executor), 1);
        token.setCallbackFrom(
            address(_executor),
            address(this),
            abi.encodeCall(this.rescueAsset, ())
        );
        token.setBubbleCallbackFailure(true);

        vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
        _executor.rescue(address(token));

        assertEq(token.balanceOf(address(_executor)), 1, "Outer transfer rolled back");
        assertEq(_asset.balanceOf(address(_executor)), 1, "Nested transfer did not occur");
    }

    // Scenarios: BLCRSC-C02.
    function test_givenReusableGrant_whenOwnerTriesRescueDuringExecution()
        public
        givenReusableGrant
    {
        CoreCallbackToken token = new CoreCallbackToken();
        token.mint(_borrower, 1);
        _asset.mint(address(_executor), 1);
        token.setCallbackFrom(
            address(_executor),
            address(this),
            abi.encodeCall(this.rescueAsset, ())
        );
        token.setCallbackPhases(false, true);
        IExecutor.Funding[] memory funding = new IExecutor.Funding[](2);
        funding[0] = IExecutor.Funding(address(_asset), 1);
        funding[1] = IExecutor.Funding(address(token), 1);
        vm.startPrank(_borrower);
        token.approve(address(_executor), 1);

        _executor.execute(
            funding,
            _single(_deposit(1)),
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(0, 0),
            type(uint48).max
        );
        vm.stopPrank();

        assertEq(
            token.callbackRevertSelector(),
            ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector,
            "Execution lock rejects even the owner"
        );
        assertEq(_asset.balanceOf(address(_executor)), 1, "Starting balance preserved");
        assertEq(_position().depositedCollateral, 1, "Funded deposit succeeds");
        assertEq(token.balanceOf(_borrower), 1, "Unused funding returned");
    }

    function rescueAsset() external {
        _executor.rescue(address(_asset));
    }
}
