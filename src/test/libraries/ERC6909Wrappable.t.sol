// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.20;

import {Test} from "@forge-std-1.9.6/Test.sol";
import {MockERC6909Wrappable} from "../mocks/MockERC6909Wrappable.sol";
import {CloneableReceiptToken} from "src/libraries/CloneableReceiptToken.sol";
import {ERC6909} from "@openzeppelin-5.3.0/token/ERC6909/draft-ERC6909.sol";
import {IERC6909Wrappable} from "src/interfaces/IERC6909Wrappable.sol";
import {stdError} from "@forge-std-1.9.6/StdError.sol";

contract ERC6909WrappableTest is Test {
    MockERC6909Wrappable public token;
    CloneableReceiptToken public erc20Implementation;
    address public alice;
    address public bob;
    uint256 public constant TOKEN_ID = 1;
    uint256 public constant AMOUNT = 100;

    address public constant ASSET = address(0x1234567890123456789012345678901234567890);
    uint8 public constant DEPOSIT_PERIOD = 9;
    address public constant FACILITY = address(0x9876543210987654321098765432109876543210);

    function setUp() public {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        erc20Implementation = new CloneableReceiptToken();
        token = new MockERC6909Wrappable(address(erc20Implementation));

        // Set the token metadata
        bytes memory additionalMetadata = abi.encodePacked(
            address(token),
            ASSET,
            DEPOSIT_PERIOD,
            FACILITY
        );
        token.setTokenMetadata(TOKEN_ID, "Mock", "MOCK", 18, additionalMetadata);
    }

    // ========== ASSERTIONS ========== //

    // Helper functions for common checks
    function assertERC20Balance(address account, uint256 expectedBalance) internal view {
        address wrappedToken = token.getWrappedToken(TOKEN_ID);
        assertEq(
            CloneableReceiptToken(wrappedToken).balanceOf(account),
            expectedBalance,
            "ERC20 balance mismatch"
        );
    }

    function assertERC6909Balance(address account, uint256 expectedBalance) internal view {
        assertEq(token.balanceOf(account, TOKEN_ID), expectedBalance, "ERC6909 balance mismatch");
    }

    function assertERC20TotalSupply(uint256 expectedSupply) internal view {
        address wrappedToken = token.getWrappedToken(TOKEN_ID);
        assertEq(
            CloneableReceiptToken(wrappedToken).totalSupply(),
            expectedSupply,
            "ERC20 total supply mismatch"
        );
    }

    function assertERC6909TotalSupply(uint256 expectedSupply) internal view {
        assertEq(token.totalSupply(TOKEN_ID), expectedSupply, "ERC6909 total supply mismatch");
    }

    function assertWrappedTokenExists(bool shouldExist) internal view {
        address wrappedToken = token.getWrappedToken(TOKEN_ID);
        if (shouldExist) {
            assertTrue(wrappedToken != address(0), "Wrapped token should exist");
        } else {
            assertEq(wrappedToken, address(0), "Wrapped token should not exist");
        }
    }

    function assertTokens(uint256 expectedTokenId, address expectedWrappedToken) internal view {
        uint256[] memory expectedTokenIds = new uint256[](1);
        expectedTokenIds[0] = expectedTokenId;
        address[] memory expectedWrappedTokens = new address[](1);
        expectedWrappedTokens[0] = expectedWrappedToken;

        (uint256[] memory tokenIds, address[] memory wrappedTokens) = token.getWrappableTokens();
        assertEq(tokenIds.length, 1, "Token IDs length mismatch");
        assertEq(wrappedTokens.length, 1, "Wrapped tokens length mismatch");
        for (uint256 i = 0; i < tokenIds.length; i++) {
            assertEq(
                tokenIds[i],
                expectedTokenIds[i],
                string.concat("Token ID mismatch for token ", vm.toString(tokenIds[i]))
            );
            assertEq(
                wrappedTokens[i],
                expectedWrappedTokens[i],
                string.concat("Wrapped token mismatch for token ", vm.toString(tokenIds[i]))
            );
        }
    }

    // ========== MODIFIERS ========== //

    // Modifiers for common conditions
    modifier givenERC20TokenExists() {
        token.createWrappedToken(TOKEN_ID);
        _;
    }

    modifier givenRecipientHasERC20Tokens() {
        // Mint wrapped token to recipient
        token.mint(alice, TOKEN_ID, AMOUNT, true);
        _;
    }

    modifier givenRecipientHasERC6909Tokens() {
        // Mint ERC6909 token to recipient
        token.mint(alice, TOKEN_ID, AMOUNT, false);
        _;
    }

    modifier givenRecipientHasApprovedWrappedTokenSpending() {
        address wrappedToken = token.getWrappedToken(TOKEN_ID);

        vm.prank(alice);
        CloneableReceiptToken(wrappedToken).approve(address(token), AMOUNT);
        _;
    }

    modifier givenRecipientHasApprovedERC6909TokenSpending() {
        vm.prank(alice);
        token.approve(address(token), TOKEN_ID, AMOUNT);
        _;
    }

    // ========== TESTS ========== //

    // Metadata
    // [X] the name is set correctly
    // [X] the symbol is set correctly
    // [X] the decimals are set correctly
    // [X] the owner is set correctly
    // [X] the asset is set correctly
    // [X] the deposit period is set correctly

    function test_metadata() public givenERC20TokenExists {
        assertEq(token.name(TOKEN_ID), "Mock", "ERC6909 name mismatch");
        assertEq(token.symbol(TOKEN_ID), "MOCK", "ERC6909 symbol mismatch");
        assertEq(token.decimals(TOKEN_ID), 18, "ERC6909 decimals mismatch");

        CloneableReceiptToken wrappedToken = CloneableReceiptToken(token.getWrappedToken(TOKEN_ID));
        assertEq(
            wrappedToken.name(),
            string(abi.encodePacked("Mock", new bytes(28))),
            "ERC20 name mismatch"
        );
        assertEq(
            wrappedToken.symbol(),
            string(abi.encodePacked("MOCK", new bytes(28))),
            "ERC20 symbol mismatch"
        );
        assertEq(wrappedToken.decimals(), 18, "ERC20 decimals mismatch");
        assertEq(wrappedToken.owner(), address(token), "ERC20 owner mismatch");
        assertEq(address(wrappedToken.asset()), ASSET, "ERC20 asset mismatch");
        assertEq(wrappedToken.depositPeriod(), DEPOSIT_PERIOD, "ERC20 deposit period mismatch");
        assertEq(wrappedToken.operator(), FACILITY, "ERC20 facility mismatch");
    }

    // Mint
    // when the amount is 0
    //  [X] it reverts
    function test_mint_whenAmountIsZero_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC6909Wrappable.ERC6909Wrappable_ZeroAmount.selector)
        );
        token.mint(alice, TOKEN_ID, 0, false);
    }

    // when shouldWrap is true
    //  given the ERC20 token has not been created
    //   [X] it creates the ERC20 token contract
    //   [X] the ERC20 token is minted to the recipient
    //   [X] the ERC6909 token is not minted to the recipient
    //   [X] the wrappedToken address is set correctly
    function test_mint_whenShouldWrapIsTrue_givenERC20TokenHasNotBeenCreated() public {
        token.mint(alice, TOKEN_ID, AMOUNT, true);

        assertWrappedTokenExists(true);

        assertERC20Balance(alice, AMOUNT);
        assertERC20TotalSupply(AMOUNT);

        assertERC6909Balance(alice, 0);
        assertERC6909TotalSupply(0);

        assertTokens(TOKEN_ID, token.getWrappedToken(TOKEN_ID));
    }

    //  given the ERC20 token exists
    //   [X] the ERC20 token is minted to the recipient
    //   [X] the ERC20 token total supply is increased
    //   [X] the ERC6909 token is not minted to the recipient
    //   [X] the ERC6909 token total supply is unchanged
    function test_mint_whenShouldWrapIsTrue_givenERC20TokenExists() public givenERC20TokenExists {
        token.mint(bob, TOKEN_ID, AMOUNT, true);

        assertWrappedTokenExists(true);

        assertERC20Balance(bob, AMOUNT);
        assertERC20TotalSupply(AMOUNT);

        assertERC6909Balance(bob, 0);
        assertERC6909TotalSupply(0);

        assertTokens(TOKEN_ID, token.getWrappedToken(TOKEN_ID));
    }

    // when shouldWrap is false
    //  [X] the wrappedToken address is 0
    //  [X] the ERC20 token is not minted to the recipient
    //  [X] the ERC6909 token is minted to the recipient
    //  [X] the ERC20 token total supply is unchanged
    //  [X] the ERC6909 token total supply is increased
    function test_mint_whenShouldWrapIsFalse() public {
        token.mint(alice, TOKEN_ID, AMOUNT, false);

        assertWrappedTokenExists(false);

        // assertERC20Balance(alice, 0);
        // assertERC20TotalSupply(0);

        assertERC6909Balance(alice, AMOUNT);
        assertERC6909TotalSupply(AMOUNT);

        assertTokens(TOKEN_ID, address(0));
    }

    // Burn
    // when the amount is 0
    //  [X] it reverts
    function test_burn_whenAmountIsZero_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC6909Wrappable.ERC6909Wrappable_ZeroAmount.selector)
        );
        token.burn(alice, TOKEN_ID, 0, false);
    }

    // when wrapped is true
    //  given the recipient has not approved the contract to spend the ERC20 token
    //   [X] it reverts
    function test_burn_whenWrappedIsTrue_givenRecipientHasNotApproved_reverts()
        public
        givenERC20TokenExists
        givenRecipientHasERC20Tokens
    {
        vm.expectRevert(stdError.arithmeticError);
        token.burn(alice, TOKEN_ID, AMOUNT, true);
    }

    //  given the recipient has approved the contract to spend the ERC20 token
    //   given the recipient does not have sufficient ERC20 tokens
    //    [X] it reverts
    function test_burn_whenWrappedIsTrue_givenRecipientHasInsufficientERC20Tokens_reverts()
        public
        givenERC20TokenExists
        givenRecipientHasApprovedWrappedTokenSpending
    {
        vm.expectRevert(stdError.arithmeticError);
        token.burn(alice, TOKEN_ID, AMOUNT, true);
    }

    //   [X] the ERC20 token is burned from the recipient
    //   [X] the ERC6909 token is not burned from the recipient
    //   [X] the ERC20 token total supply is decreased
    //   [X] the ERC6909 token total supply is unchanged
    function test_burn_whenWrappedIsTrue_givenRecipientHasApproved()
        public
        givenERC20TokenExists
        givenRecipientHasERC20Tokens
        givenRecipientHasApprovedWrappedTokenSpending
    {
        // Burn the token
        token.burn(alice, TOKEN_ID, AMOUNT, true);

        assertERC20Balance(alice, 0);
        assertERC20TotalSupply(0);

        assertERC6909Balance(alice, 0);
        assertERC6909TotalSupply(0);
    }

    // when wrapped is false
    //  given the recipient has not approved the contract to spend the ERC6909 token
    //   [X] it reverts
    function test_burn_whenWrappedIsFalse_givenRecipientHasNotApproved_reverts()
        public
        givenERC20TokenExists
        givenRecipientHasERC6909Tokens
    {
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC6909.ERC6909InsufficientAllowance.selector,
                address(token),
                0,
                AMOUNT,
                TOKEN_ID
            )
        );
        token.burn(alice, TOKEN_ID, AMOUNT, false);
    }

    //  given the recipient has approved the contract to spend the ERC6909 token
    //   given the recipient does not have sufficient ERC6909 tokens
    //    [X] it reverts
    function test_burn_whenWrappedIsFalse_givenRecipientHasInsufficientERC6909Tokens_reverts()
        public
        givenERC20TokenExists
        givenRecipientHasApprovedERC6909TokenSpending
    {
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC6909.ERC6909InsufficientBalance.selector,
                alice,
                0,
                AMOUNT,
                TOKEN_ID
            )
        );
        token.burn(alice, TOKEN_ID, AMOUNT, false);
    }

    //   [X] the ERC20 token is not burned from the recipient
    //   [X] the ERC6909 token is burned from the recipient
    //   [X] the ERC20 token total supply is unchanged
    //   [X] the ERC6909 token total supply is decreased
    function test_burn_whenWrappedIsFalse_givenRecipientHasApproved()
        public
        givenRecipientHasERC6909Tokens
        givenRecipientHasApprovedERC6909TokenSpending
    {
        // Burn the token
        token.burn(alice, TOKEN_ID, AMOUNT, false);

        assertERC6909Balance(alice, 0);
        assertERC6909TotalSupply(0);
    }

    // Wrap
    // when the amount is 0
    //  [X] it reverts
    function test_wrap_whenAmountIsZero_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC6909Wrappable.ERC6909Wrappable_ZeroAmount.selector)
        );

        vm.prank(alice);
        token.wrap(TOKEN_ID, 0);
    }

    // when the tokenId is invalid
    //  [X] it reverts
    function test_wrap_whenTokenIdIsInvalid_reverts()
        public
        givenERC20TokenExists
        givenRecipientHasERC6909Tokens
        givenRecipientHasApprovedERC6909TokenSpending
    {
        vm.expectRevert(
            abi.encodeWithSelector(IERC6909Wrappable.ERC6909Wrappable_InvalidTokenId.selector, 999)
        );

        vm.prank(alice);
        token.wrap(999, AMOUNT);
    }

    // when the recipient has not approved the contract to spend the ERC6909 token
    //  [X] it reverts
    function test_wrap_whenRecipientHasNotApproved_reverts()
        public
        givenERC20TokenExists
        givenRecipientHasERC6909Tokens
    {
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC6909.ERC6909InsufficientAllowance.selector,
                address(token),
                0,
                AMOUNT,
                TOKEN_ID
            )
        );

        vm.prank(alice);
        token.wrap(TOKEN_ID, AMOUNT);
    }

    // when the caller does not have sufficient ERC6909 tokens
    //  [X] it reverts
    function test_wrap_givenRecipientHasInsufficientERC6909Tokens_reverts()
        public
        givenERC20TokenExists
        givenRecipientHasApprovedERC6909TokenSpending
    {
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC6909.ERC6909InsufficientBalance.selector,
                alice,
                0,
                AMOUNT,
                TOKEN_ID
            )
        );

        vm.prank(alice);
        token.wrap(TOKEN_ID, AMOUNT);
    }

    // given the ERC20 token has not been created
    //  [X] it creates the ERC20 token contract
    //  [X] the wrappedToken address is set correctly
    //  [X] the ERC6909 token is burned from the recipient
    //  [X] the ERC20 token is minted to the recipient
    //  [X] the ERC6909 token supply is reduced
    //  [X] the ERC20 token supply is increased
    function test_wrap_givenERC20TokenHasNotBeenCreated()
        public
        givenRecipientHasERC6909Tokens
        givenRecipientHasApprovedERC6909TokenSpending
    {
        // Wrap the token
        vm.prank(alice);
        token.wrap(TOKEN_ID, AMOUNT);

        assertWrappedTokenExists(true);

        assertERC20Balance(alice, AMOUNT);
        assertERC20TotalSupply(AMOUNT);

        assertERC6909Balance(alice, 0);
        assertERC6909TotalSupply(0);

        assertTokens(TOKEN_ID, token.getWrappedToken(TOKEN_ID));
    }

    // given the ERC20 token exists
    //  [X] the ERC6909 token is burned from the recipient
    //  [X] the ERC20 token is minted to the recipient
    //  [X] the ERC6909 token supply is reduced
    //  [X] the ERC20 token supply is increased
    function test_wrap_givenERC20TokenExists()
        public
        givenERC20TokenExists
        givenRecipientHasERC6909Tokens
        givenRecipientHasApprovedERC6909TokenSpending
    {
        // Wrap the token
        vm.prank(alice);
        address wrappedToken = token.wrap(TOKEN_ID, AMOUNT);

        assertWrappedTokenExists(true);
        assertEq(wrappedToken, token.getWrappedToken(TOKEN_ID), "Wrapped token address mismatch");

        assertERC20Balance(alice, AMOUNT);
        assertERC20TotalSupply(AMOUNT);

        assertERC6909Balance(alice, 0);
        assertERC6909TotalSupply(0);

        assertTokens(TOKEN_ID, token.getWrappedToken(TOKEN_ID));
    }

    // Unwrap
    // when the amount is 0
    //  [X] it reverts
    function test_unwrap_whenAmountIsZero_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC6909Wrappable.ERC6909Wrappable_ZeroAmount.selector)
        );

        vm.prank(alice);
        token.unwrap(TOKEN_ID, 0);
    }

    // when the tokenId is invalid
    //  [X] it reverts
    function test_unwrap_whenTokenIdIsInvalid_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC6909Wrappable.ERC6909Wrappable_InvalidTokenId.selector, 999)
        );

        vm.prank(alice);
        token.unwrap(999, AMOUNT);
    }

    // when the recipient has not approved the contract to spend the ERC20 token
    //  [X] it reverts
    function test_unwrap_whenRecipientHasNotApproved_reverts()
        public
        givenERC20TokenExists
        givenRecipientHasERC20Tokens
    {
        vm.expectRevert(stdError.arithmeticError);

        vm.prank(alice);
        token.unwrap(TOKEN_ID, AMOUNT);
    }

    // given the recipient has approved the contract to spend the ERC20 token
    //  given the recipient does not have sufficient ERC20 tokens
    //   [X] it reverts
    function test_unwrap_givenRecipientHasInsufficientERC20Tokens_reverts()
        public
        givenERC20TokenExists
        givenRecipientHasApprovedWrappedTokenSpending
    {
        vm.expectRevert(stdError.arithmeticError);

        vm.prank(alice);
        token.unwrap(TOKEN_ID, AMOUNT);
    }

    //  [X] the ERC6909 token is minted to the recipient
    //  [X] the ERC20 token is burned from the recipient
    //  [X] the ERC6909 token supply is increased
    //  [X] the ERC20 token supply is decreased
    function test_unwrap_givenRecipientHasApproved()
        public
        givenERC20TokenExists
        givenRecipientHasERC20Tokens
        givenRecipientHasApprovedWrappedTokenSpending
    {
        // Unwrap the token
        vm.prank(alice);
        token.unwrap(TOKEN_ID, AMOUNT);

        assertERC20Balance(alice, 0);
        assertERC20TotalSupply(0);

        assertERC6909Balance(alice, AMOUNT);
        assertERC6909TotalSupply(AMOUNT);
    }

    // getTokens
    // given there are no tokens
    //  [X] it returns an empty array
    // given there are multiple tokens
    //  [X] it returns the token IDs and wrapped token addresses of all tokens

    function test_getWrappableTokens_noTokens() public {
        token = new MockERC6909Wrappable(address(erc20Implementation));

        (uint256[] memory tokenIds, address[] memory wrappedTokens) = token.getWrappableTokens();
        assertEq(tokenIds.length, 0, "Token IDs length mismatch");
        assertEq(wrappedTokens.length, 0, "Wrapped tokens length mismatch");
    }

    function test_getWrappableTokens_givenMultipleTokens() public {
        // Create the second token
        uint256 tokenId2 = TOKEN_ID + 1;
        bytes memory additionalMetadata = abi.encodePacked(address(token), ASSET, DEPOSIT_PERIOD);
        token.setTokenMetadata(tokenId2, "Mock2", "MOCK2", 18, additionalMetadata);

        // Mint the tokens
        token.mint(alice, TOKEN_ID, AMOUNT, false);
        token.mint(bob, tokenId2, AMOUNT, true);

        (uint256[] memory tokenIds, address[] memory wrappedTokens) = token.getWrappableTokens();
        assertEq(tokenIds.length, 2, "Token IDs length mismatch");
        assertEq(wrappedTokens.length, 2, "Wrapped tokens length mismatch");

        assertEq(tokenIds[0], TOKEN_ID, "Token ID mismatch for token 0");
        assertEq(wrappedTokens[0], address(0), "Wrapped token mismatch for token 0");
        assertEq(tokenIds[1], tokenId2, "Token ID mismatch for token 1");
        assertEq(
            wrappedTokens[1],
            token.getWrappedToken(tokenId2),
            "Wrapped token mismatch for token 1"
        );
    }
}
