// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "@openzeppelin-5.7.0/token/ERC20/IERC20.sol";

// Contracts
import {Test} from "@forge-std-1.16.2/Test.sol";
import {ERC20Mock} from "@openzeppelin-5.7.0/mocks/token/ERC20Mock.sol";
import {MockERC20ConfiguredReturnData} from "src/test/libraries/fixtures/MockERC20ConfiguredReturnData.sol";
import {MockERC20NoReturn} from "src/test/libraries/fixtures/MockERC20NoReturn.sol";
import {MockERC20RevertingAfterTransfer} from "src/test/libraries/fixtures/MockERC20RevertingAfterTransfer.sol";
import {SafeERC20Harness} from "src/test/libraries/fixtures/SafeERC20Harness.sol";

contract SafeERC20TrySafeTransferTest is Test {
    uint256 internal constant _INITIAL_BALANCE = 100;
    uint256 internal constant _TRANSFER_AMOUNT = 40;

    ERC20Mock internal _token;
    SafeERC20Harness internal _helper;
    address internal _recipient;

    function setUp() public {
        _token = new ERC20Mock();
        _helper = new SafeERC20Harness();
        vm.label(address(_token), "ERC20Mock");
        vm.label(address(_helper), "SafeERC20Harness");
        _recipient = makeAddr("recipient");
        _token.mint(address(_helper), _INITIAL_BALANCE);
    }

    // Scenarios: TRY-P01.
    function test_whenStandardTokenAmountIsFunded(address caller_, uint256 amount_) public {
        amount_ = bound(amount_, 0, _INITIAL_BALANCE);

        vm.prank(caller_);
        bool success = _helper.trySafeTransfer(_token, _recipient, amount_);

        assertTrue(success, "successful token transfer returns true");
        assertEq(_token.balanceOf(_recipient), amount_, "recipient receives the tokens");
        assertEq(
            _token.balanceOf(address(_helper)),
            _INITIAL_BALANCE - amount_,
            "helper balance decreases once"
        );
    }

    // Scenarios: TRY-P01.
    function test_whenAmountIsZero_succeedsWithoutMovingTokens(address caller_) public {
        vm.prank(caller_);
        bool success = _helper.trySafeTransfer(_token, _recipient, 0);

        assertTrue(success, "zero transfer is accepted by the token");
        assertEq(_token.balanceOf(_recipient), 0, "recipient balance stays zero");
        assertEq(
            _token.balanceOf(address(_helper)),
            _INITIAL_BALANCE,
            "helper balance stays unchanged"
        );
    }

    // Scenarios: TRY-P01.
    function test_whenAmountIsOne_transfersOne(address caller_) public {
        vm.prank(caller_);
        bool success = _helper.trySafeTransfer(_token, _recipient, 1);

        assertTrue(success, "one-token transfer returns true");
        assertEq(_token.balanceOf(_recipient), 1, "recipient receives one token");
        assertEq(
            _token.balanceOf(address(_helper)),
            _INITIAL_BALANCE - 1,
            "helper sends one token"
        );
    }

    // Scenarios: TRY-N01.
    function test_whenAmountIsMaximum_transfersMaximum(address caller_) public {
        ERC20Mock maxToken = new ERC20Mock();
        maxToken.mint(address(_helper), type(uint256).max);

        vm.prank(caller_);
        bool success = _helper.trySafeTransfer(maxToken, _recipient, type(uint256).max);

        assertTrue(success, "maximum amount is accepted");
        assertEq(maxToken.balanceOf(_recipient), type(uint256).max, "recipient receives maximum");
        assertEq(maxToken.balanceOf(address(_helper)), 0, "helper sends maximum once");
    }

    // Scenarios: TRY-I01.
    function test_whenTokenIsZeroAddress_returnsFalse(address caller_) public {
        vm.prank(caller_);
        bool success = _helper.trySafeTransfer(IERC20(address(0)), _recipient, _TRANSFER_AMOUNT);

        assertFalse(success, "zero-address token is rejected without reverting");
    }

    // Scenarios: TRY-I01.
    function test_whenTokenIsNonzeroAddressWithoutCode_returnsFalse(address caller_) public {
        address token = makeAddr("tokenWithoutCode");

        vm.prank(caller_);
        bool success = _helper.trySafeTransfer(IERC20(token), _recipient, _TRANSFER_AMOUNT);

        assertFalse(success, "EOA token is rejected without reverting");
    }

    // Scenarios: TRY-I02.
    function test_whenRecipientIsZeroAddress_returnsFalseAndRetainsBalances(
        address caller_
    ) public {
        vm.prank(caller_);
        bool success = _helper.trySafeTransfer(_token, address(0), _TRANSFER_AMOUNT);

        assertFalse(success, "zero recipient rejection is caught");
        assertEq(
            _token.balanceOf(address(_helper)),
            _INITIAL_BALANCE,
            "helper balance is retained"
        );
        assertEq(_token.balanceOf(address(0)), 0, "zero address receives no tokens");
    }

    // Scenarios: TRY-T01.
    function test_whenTokenReturnsNoDataAfterTransfer_acceptsTransfer(
        address caller_,
        uint256 amount_
    ) public {
        amount_ = bound(amount_, 0, _INITIAL_BALANCE);
        MockERC20NoReturn noReturnToken = new MockERC20NoReturn();
        noReturnToken.mint(address(_helper), _INITIAL_BALANCE);

        vm.prank(caller_);
        bool success = _helper.trySafeTransfer(noReturnToken, _recipient, amount_);

        assertTrue(success, "empty return data is accepted");
        assertEq(noReturnToken.balanceOf(_recipient), amount_, "recipient receives the tokens");
        assertEq(
            noReturnToken.balanceOf(address(_helper)),
            _INITIAL_BALANCE - amount_,
            "helper balance decreases once"
        );
    }

    // Scenarios: TRY-T02.
    function test_whenTokenReturnsShortData_returnsFalseButKeepsTokenEffects(
        address caller_,
        uint256 returnLength_
    ) public {
        returnLength_ = bound(returnLength_, 1, 31);
        bytes memory returnData = new bytes(returnLength_);
        returnData[returnLength_ - 1] = 0x01;
        MockERC20ConfiguredReturnData malformedToken = new MockERC20ConfiguredReturnData(
            returnData
        );
        malformedToken.mint(address(_helper), _INITIAL_BALANCE);

        vm.prank(caller_);
        bool success = _helper.trySafeTransfer(malformedToken, _recipient, _TRANSFER_AMOUNT);

        assertFalse(success, "short return data is rejected without reverting");
        _assertCompletedTransfer(malformedToken, _TRANSFER_AMOUNT);
    }

    // Scenarios: TRY-T02.
    function test_whenTokenReturnsNoncanonicalWord_returnsFalseButKeepsTokenEffects(
        address caller_,
        uint256 returnWord_
    ) public {
        vm.assume(returnWord_ != 1);
        MockERC20ConfiguredReturnData malformedToken = new MockERC20ConfiguredReturnData(
            abi.encode(returnWord_)
        );
        malformedToken.mint(address(_helper), _INITIAL_BALANCE);

        vm.prank(caller_);
        bool success = _helper.trySafeTransfer(malformedToken, _recipient, _TRANSFER_AMOUNT);

        assertFalse(success, "noncanonical return word is rejected without reverting");
        _assertCompletedTransfer(malformedToken, _TRANSFER_AMOUNT);
    }

    // Scenarios: TRY-T04.
    function test_whenTokenReturnsFalse_returnsFalseAndRetainsBalances(address caller_) public {
        vm.mockCall(
            address(_token),
            abi.encodeCall(IERC20.transfer, (_recipient, _TRANSFER_AMOUNT)),
            abi.encode(false)
        );

        vm.prank(caller_);
        bool success = _helper.trySafeTransfer(_token, _recipient, _TRANSFER_AMOUNT);

        assertFalse(success, "false return is rejected without reverting");
        assertEq(
            _token.balanceOf(address(_helper)),
            _INITIAL_BALANCE,
            "helper balance is retained"
        );
        assertEq(_token.balanceOf(_recipient), 0, "recipient receives no tokens");
    }

    // Scenarios: TRY-T06.
    function test_whenTokenReturnsTrueWithExtraData_acceptsTransfer(
        address caller_,
        uint256 extraWord_
    ) public {
        MockERC20ConfiguredReturnData extraDataToken = new MockERC20ConfiguredReturnData(
            abi.encode(uint256(1), extraWord_)
        );
        extraDataToken.mint(address(_helper), _INITIAL_BALANCE);

        vm.prank(caller_);
        bool success = _helper.trySafeTransfer(extraDataToken, _recipient, _TRANSFER_AMOUNT);

        assertTrue(success, "canonical first word is accepted despite extra data");
        _assertCompletedTransfer(extraDataToken, _TRANSFER_AMOUNT);
    }

    // Scenarios: TRY-T07.
    function test_whenTokenReturnsTrueWithoutTransfer_returnsTrueWithUnchangedBalances(
        address caller_
    ) public {
        vm.mockCall(
            address(_token),
            abi.encodeCall(IERC20.transfer, (_recipient, _TRANSFER_AMOUNT)),
            abi.encode(true)
        );

        vm.prank(caller_);
        bool success = _helper.trySafeTransfer(_token, _recipient, _TRANSFER_AMOUNT);

        assertTrue(success, "canonical true is accepted without balance verification");
        assertEq(
            _token.balanceOf(address(_helper)),
            _INITIAL_BALANCE,
            "helper balance stays unchanged"
        );
        assertEq(_token.balanceOf(_recipient), 0, "recipient receives no tokens");
    }

    // Scenarios: TRY-T03.
    function test_whenAmountExceedsAvailableBalance_returnsFalseAndRetainsBalances(
        address caller_,
        uint256 amount_
    ) public {
        amount_ = bound(amount_, _INITIAL_BALANCE + 1, type(uint256).max);

        vm.prank(caller_);
        bool success = _helper.trySafeTransfer(_token, _recipient, amount_);

        assertFalse(success, "insufficient-balance revert is caught");
        assertEq(
            _token.balanceOf(address(_helper)),
            _INITIAL_BALANCE,
            "helper balance is retained"
        );
        assertEq(_token.balanceOf(_recipient), 0, "recipient receives no tokens");
    }

    // Scenarios: TRY-T05.
    function test_whenTokenRevertsAfterTransfer_returnsFalseAndRollsBack(address caller_) public {
        MockERC20RevertingAfterTransfer revertingToken = new MockERC20RevertingAfterTransfer();
        revertingToken.mint(address(_helper), _INITIAL_BALANCE);

        vm.prank(caller_);
        bool success = _helper.trySafeTransfer(revertingToken, _recipient, _TRANSFER_AMOUNT);

        assertFalse(success, "reverted transfer is reported as failure");
        assertEq(
            revertingToken.balanceOf(address(_helper)),
            _INITIAL_BALANCE,
            "helper balance is rolled back"
        );
        assertEq(revertingToken.balanceOf(_recipient), 0, "recipient balance is rolled back");
    }

    function _assertCompletedTransfer(IERC20 token_, uint256 amount_) internal view {
        assertEq(token_.balanceOf(_recipient), amount_, "recipient receives the tokens");
        assertEq(
            token_.balanceOf(address(_helper)),
            _INITIAL_BALANCE - amount_,
            "helper balance decreases once"
        );
    }
}
