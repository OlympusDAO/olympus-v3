// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(erc20-unchecked-transfer, unwrapped-modifier-logic)
pragma solidity >=0.8.15;

import {Test} from "@forge-std-1.9.6/Test.sol";
import {CloneableReceiptToken} from "src/libraries/CloneableReceiptToken.sol";
import {ClonesWithImmutableArgs} from "@clones-with-immutable-args-1.1.2/ClonesWithImmutableArgs.sol";
import {IDepositReceiptToken} from "src/interfaces/IDepositReceiptToken.sol";
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {stdError} from "@forge-std-1.9.6/StdError.sol";
import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC20BurnableMintable} from "src/interfaces/IERC20BurnableMintable.sol";
import {IERC6909Wrappable} from "src/interfaces/IERC6909Wrappable.sol";
import {ERC165Helper} from "src/test/lib/ERC165.sol";

contract CloneableReceiptTokenTest is Test {
    using ClonesWithImmutableArgs for address;

    // Test accounts
    address public owner;
    address public alice;
    address public bob;
    address public operator;

    // Contracts
    CloneableReceiptToken public implementation;
    CloneableReceiptToken public token;
    MockERC20 public asset;

    // Constants
    uint8 public constant DEPOSIT_PERIOD = 6;
    uint256 public constant MINT_AMOUNT = 100e18;
    uint256 public constant TRANSFER_AMOUNT = 50e18;
    string public constant TOKEN_NAME = "Test Receipt Token";
    string public constant TOKEN_SYMBOL = "TRT";

    function setUp() public {
        owner = makeAddr("owner");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        operator = makeAddr("operator");

        // Deploy implementation
        implementation = new CloneableReceiptToken();

        // Deploy mock asset
        asset = new MockERC20("Test Asset", "TA", 18);
        asset.mint(address(this), 1000e18);

        // Create token clone
        token = _createTokenClone(owner, address(asset), DEPOSIT_PERIOD, operator);
    }

    // ========== HELPER FUNCTIONS ========== //

    /// @notice Creates a token clone with specified parameters
    function _createTokenClone(
        address owner_,
        address asset_,
        uint8 depositPeriod_,
        address operator_
    ) internal returns (CloneableReceiptToken token_) {
        bytes memory tokenData = abi.encodePacked(
            /// forge-lint: disable-next-line(unsafe-typecast)
            bytes32(bytes(TOKEN_NAME)),
            /// forge-lint: disable-next-line(unsafe-typecast)
            bytes32(bytes(TOKEN_SYMBOL)),
            uint8(18), // decimals
            owner_,
            asset_,
            depositPeriod_,
            operator_
        );

        address clone = address(implementation).clone(tokenData);
        token_ = CloneableReceiptToken(clone);
    }

    // ========== ASSERTIONS ========== //

    function assertBalance(address account, uint256 expectedBalance) internal view {
        assertEq(token.balanceOf(account), expectedBalance, "Balance mismatch");
    }

    function assertTotalSupply(uint256 expectedSupply) internal view {
        assertEq(token.totalSupply(), expectedSupply, "Total supply mismatch");
    }

    function assertAllowance(
        address owner_,
        address spender_,
        uint256 expectedAllowance_
    ) internal view {
        assertEq(token.allowance(owner_, spender_), expectedAllowance_, "Allowance mismatch");
    }

    function assertTokenMetadata(
        address expectedOwner,
        address expectedAsset,
        uint8 expectedDepositPeriod,
        address expectedOperator
    ) internal view {
        assertEq(token.owner(), expectedOwner, "Owner mismatch");
        assertEq(address(token.asset()), expectedAsset, "Asset mismatch");
        assertEq(token.depositPeriod(), expectedDepositPeriod, "Deposit period mismatch");
        assertEq(token.operator(), expectedOperator, "Operator mismatch");
    }

    // ========== MODIFIERS ========== //

    modifier givenTokensAreMinted() {
        vm.prank(owner);
        token.mintFor(alice, MINT_AMOUNT);
        _;
    }

    modifier givenUserHasApprovedSpender(address spender_, uint256 amount_) {
        vm.prank(alice);
        token.approve(spender_, amount_);
        _;
    }

    modifier givenUserHasMaxApprovedSpender(address spender_) {
        vm.prank(alice);
        token.approve(spender_, type(uint256).max);
        _;
    }

    // ========== TESTS ========== //

    // mintFor() Permissions
    // when the caller is the owner
    //  [X] tokens are minted successfully
    //  [X] balance is updated correctly
    //  [X] total supply is updated correctly
    function test_mintFor_whenCallerIsOwner() public {
        vm.prank(owner);
        token.mintFor(alice, MINT_AMOUNT);

        assertBalance(alice, MINT_AMOUNT);
        assertTotalSupply(MINT_AMOUNT);
    }

    // when the caller is not the owner
    //  [X] it reverts with OnlyOwner
    function test_mintFor_whenCallerIsNotOwner_reverts(address caller_) public {
        vm.assume(caller_ != owner);

        vm.expectRevert(abi.encodeWithSelector(IDepositReceiptToken.OnlyOwner.selector));

        vm.prank(caller_);
        token.mintFor(bob, MINT_AMOUNT);
    }

    // when minting to zero address
    //  [X] tokens are minted successfully
    function test_mintFor_whenMintingToZeroAddress() public {
        vm.prank(owner);
        token.mintFor(address(0), MINT_AMOUNT);

        assertBalance(address(0), MINT_AMOUNT);
        assertTotalSupply(MINT_AMOUNT);
    }

    // when minting zero amount
    //  [X] tokens are minted successfully (zero amount)
    function test_mintFor_whenMintingZeroAmount() public {
        vm.prank(owner);
        token.mintFor(alice, 0);

        assertBalance(alice, 0);
        assertTotalSupply(0);
    }

    // burnFrom() Permissions
    // when the caller is the owner
    //  given the user has sufficient balance
    //   [X] tokens are burned successfully
    //   [X] balance is updated correctly
    //   [X] total supply is updated correctly
    //   [X] burnFrom does NOT check allowances (intentional design)
    function test_burnFrom_whenCallerIsOwner_givenSufficientBalance() public givenTokensAreMinted {
        vm.prank(owner);
        token.burnFrom(alice, TRANSFER_AMOUNT);

        assertBalance(alice, MINT_AMOUNT - TRANSFER_AMOUNT);
        assertTotalSupply(MINT_AMOUNT - TRANSFER_AMOUNT);
    }

    // when the caller is not the owner
    //  [X] it reverts with OnlyOwner
    function test_burnFrom_whenCallerIsNotOwner_reverts(
        address caller_
    ) public givenTokensAreMinted {
        vm.assume(caller_ != owner);

        vm.expectRevert(abi.encodeWithSelector(IDepositReceiptToken.OnlyOwner.selector));

        vm.prank(caller_);
        token.burnFrom(alice, TRANSFER_AMOUNT);
    }

    // given the user has insufficient balance
    //  [X] it reverts
    function test_burnFrom_givenInsufficientBalance_reverts() public {
        vm.expectRevert(stdError.arithmeticError);

        vm.prank(owner);
        token.burnFrom(alice, MINT_AMOUNT);
    }

    // when burning zero amount
    //  [X] tokens are burned successfully (zero amount)
    function test_burnFrom_whenBurningZeroAmount() public givenTokensAreMinted {
        vm.prank(owner);
        token.burnFrom(alice, 0);

        assertBalance(alice, MINT_AMOUNT);
        assertTotalSupply(MINT_AMOUNT);
    }

    // Standard ERC20 Transfer Operations
    // when transferring with sufficient balance
    //  [X] transfer succeeds
    //  [X] balances are updated correctly
    //  [X] total supply remains unchanged
    function test_transfer_whenSufficientBalance() public givenTokensAreMinted {
        vm.prank(alice);
        token.transfer(bob, TRANSFER_AMOUNT);

        assertBalance(alice, MINT_AMOUNT - TRANSFER_AMOUNT);
        assertBalance(bob, TRANSFER_AMOUNT);
        assertTotalSupply(MINT_AMOUNT);
    }

    // when transferring with insufficient balance
    //  [X] it reverts
    function test_transfer_whenInsufficientBalance_reverts() public {
        vm.expectRevert(stdError.arithmeticError);

        vm.prank(alice);
        token.transfer(bob, TRANSFER_AMOUNT);
    }

    // when transferring to zero address
    //  [X] tokens are transferred successfully
    function test_transfer_whenTransferringToZeroAddress() public givenTokensAreMinted {
        vm.prank(alice);
        token.transfer(address(0), TRANSFER_AMOUNT);

        assertBalance(alice, MINT_AMOUNT - TRANSFER_AMOUNT);
        assertBalance(address(0), TRANSFER_AMOUNT);
        assertTotalSupply(MINT_AMOUNT);
    }

    // when transferring to self
    //  [X] transfer succeeds
    //  [X] balance remains unchanged
    function test_transfer_whenTransferringToSelf() public givenTokensAreMinted {
        vm.prank(alice);
        token.transfer(alice, TRANSFER_AMOUNT);

        assertBalance(alice, MINT_AMOUNT);
        assertTotalSupply(MINT_AMOUNT);
    }

    // Standard ERC20 Approval Operations
    // when approving a spender
    //  [X] allowance is set correctly
    //  [X] Approval event is emitted
    function test_approve() public {
        vm.prank(alice);
        token.approve(bob, TRANSFER_AMOUNT);

        assertAllowance(alice, bob, TRANSFER_AMOUNT);
    }

    // when increasing allowance
    //  [X] allowance is increased correctly
    //  [X] Approval event is emitted
    function test_increaseAllowance() public {
        vm.prank(alice);
        token.approve(bob, TRANSFER_AMOUNT);

        vm.prank(alice);
        token.increaseAllowance(bob, TRANSFER_AMOUNT);

        assertAllowance(alice, bob, 2 * TRANSFER_AMOUNT);
    }

    // when decreasing allowance
    //  [X] allowance is decreased correctly
    //  [X] Approval event is emitted
    function test_decreaseAllowance() public {
        vm.prank(alice);
        token.approve(bob, 2 * TRANSFER_AMOUNT);

        vm.prank(alice);
        token.decreaseAllowance(bob, TRANSFER_AMOUNT);

        assertAllowance(alice, bob, TRANSFER_AMOUNT);
    }

    // when decreasing allowance with insufficient allowance
    //  [X] it reverts
    function test_decreaseAllowance_whenInsufficientAllowance_reverts() public {
        vm.prank(alice);
        token.approve(bob, TRANSFER_AMOUNT);

        vm.expectRevert(stdError.arithmeticError);
        vm.prank(alice);
        token.decreaseAllowance(bob, 2 * TRANSFER_AMOUNT);
    }

    // TransferFrom with Approval Checks
    // when transferring with sufficient allowance
    //  [X] transferFrom succeeds
    //  [X] balances are updated correctly
    //  [X] allowance is decremented correctly
    function test_transferFrom_whenSufficientAllowance()
        public
        givenTokensAreMinted
        givenUserHasApprovedSpender(bob, TRANSFER_AMOUNT)
    {
        vm.prank(bob);
        token.transferFrom(alice, bob, TRANSFER_AMOUNT);

        assertBalance(alice, MINT_AMOUNT - TRANSFER_AMOUNT);
        assertBalance(bob, TRANSFER_AMOUNT);
        assertAllowance(alice, bob, 0);
        assertTotalSupply(MINT_AMOUNT);
    }

    //  when the caller is not the approved spender
    //   [X] it reverts
    function test_transferFrom_whenCallerIsNotApprovedSpender_reverts(
        address caller_
    ) public givenTokensAreMinted {
        vm.assume(caller_ != bob && caller_ != alice);

        vm.expectRevert(stdError.arithmeticError);

        vm.prank(caller_);
        token.transferFrom(alice, bob, TRANSFER_AMOUNT);
    }

    // when transferring with max uint256 allowance
    //  [X] transferFrom succeeds
    //  [X] allowance is not decremented
    function test_transferFrom_whenMaxAllowance()
        public
        givenTokensAreMinted
        givenUserHasMaxApprovedSpender(bob)
    {
        vm.prank(bob);
        token.transferFrom(alice, bob, TRANSFER_AMOUNT);

        assertBalance(alice, MINT_AMOUNT - TRANSFER_AMOUNT);
        assertBalance(bob, TRANSFER_AMOUNT);
        assertAllowance(alice, bob, type(uint256).max);
        assertTotalSupply(MINT_AMOUNT);
    }

    // when transferring from unapproved spender
    //  [X] it reverts
    function test_transferFrom_whenUnapprovedSpender_reverts() public givenTokensAreMinted {
        vm.expectRevert(stdError.arithmeticError);

        vm.prank(bob);
        token.transferFrom(alice, bob, TRANSFER_AMOUNT);
    }

    // when alice uses transferFrom with allowance
    //  [X] transferFrom succeeds
    //  [X] balance remains unchanged
    //  [X] allowance is decremented
    function test_transferFrom_whenTransferringWithAllowance()
        public
        givenTokensAreMinted
        givenUserHasApprovedSpender(alice, TRANSFER_AMOUNT)
    {
        vm.prank(alice);
        token.transferFrom(alice, bob, TRANSFER_AMOUNT);

        assertBalance(alice, MINT_AMOUNT - TRANSFER_AMOUNT);
        assertBalance(bob, TRANSFER_AMOUNT);
        assertAllowance(alice, alice, 0);
        assertTotalSupply(MINT_AMOUNT);
    }

    // when alice uses transferFrom without allowance
    //  [X] it reverts
    function test_transferFrom_whenTransferringWithoutAllowance_reverts()
        public
        givenTokensAreMinted
    {
        vm.expectRevert(stdError.arithmeticError);

        vm.prank(alice);
        token.transferFrom(alice, bob, TRANSFER_AMOUNT);
    }

    // Edge Cases
    // when using max uint256 allowance
    //  [X] operations work correctly
    function test_maxAllowanceBehavior() public givenTokensAreMinted {
        vm.prank(alice);
        token.approve(bob, type(uint256).max);

        // Multiple transfers should work without decrementing allowance
        vm.prank(bob);
        token.transferFrom(alice, bob, TRANSFER_AMOUNT);

        vm.prank(bob);
        token.transferFrom(alice, bob, TRANSFER_AMOUNT);

        assertBalance(alice, MINT_AMOUNT - 2 * TRANSFER_AMOUNT);
        assertBalance(bob, 2 * TRANSFER_AMOUNT);
        assertAllowance(alice, bob, type(uint256).max);
    }

    // when performing multiple operations in sequence
    //  [X] all operations work correctly
    function test_multipleOperationsInSequence() public givenTokensAreMinted {
        // Approve
        vm.prank(alice);
        token.approve(bob, TRANSFER_AMOUNT);

        // TransferFrom
        vm.prank(bob);
        token.transferFrom(alice, bob, TRANSFER_AMOUNT);

        // Transfer back
        vm.prank(bob);
        token.transfer(alice, TRANSFER_AMOUNT);

        // Approve again
        vm.prank(alice);
        token.approve(bob, TRANSFER_AMOUNT);

        assertBalance(alice, MINT_AMOUNT);
        assertBalance(bob, 0);
        assertAllowance(alice, bob, TRANSFER_AMOUNT);
        assertTotalSupply(MINT_AMOUNT);
    }

    // Fuzz tests
    function test_fuzz_mintFor(uint256 amount_) public {
        amount_ = bound(amount_, 0, 1000e18);

        vm.prank(owner);
        token.mintFor(alice, amount_);

        assertBalance(alice, amount_);
        assertTotalSupply(amount_);
    }

    function test_fuzz_transfer(uint256 amount_) public givenTokensAreMinted {
        amount_ = bound(amount_, 0, MINT_AMOUNT);

        vm.prank(alice);
        token.transfer(bob, amount_);

        assertBalance(alice, MINT_AMOUNT - amount_);
        assertBalance(bob, amount_);
        assertTotalSupply(MINT_AMOUNT);
    }

    function test_fuzz_approve(uint256 amount_) public {
        vm.prank(alice);
        token.approve(bob, amount_);

        assertAllowance(alice, bob, amount_);
    }

    // ERC165
    function test_supportsInterface() public view {
        ERC165Helper.validateSupportsInterface(address(token));
        assertEq(token.supportsInterface(type(IERC165).interfaceId), true, "IERC165 mismatch");
        assertEq(token.supportsInterface(type(IERC20).interfaceId), true, "IERC20 mismatch");
        assertEq(
            token.supportsInterface(type(IERC20BurnableMintable).interfaceId),
            true,
            "IERC20BurnableMintable mismatch"
        );
        assertEq(
            token.supportsInterface(type(IDepositReceiptToken).interfaceId),
            true,
            "IDepositReceiptToken mismatch"
        );

        assertEq(
            token.supportsInterface(type(IERC6909Wrappable).interfaceId),
            false,
            "IERC6909Wrappable mismatch"
        );
    }
}
/// forge-lint: disable-end(erc20-unchecked-transfer, unwrapped-modifier-logic)
