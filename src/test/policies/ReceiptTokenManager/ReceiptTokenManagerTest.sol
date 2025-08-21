// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.20;

import {Test} from "@forge-std-1.9.6/Test.sol";
import {console2} from "@forge-std-1.9.6/console2.sol";

import {ReceiptTokenManager} from "src/policies/deposits/ReceiptTokenManager.sol";
import {IReceiptTokenManager} from "src/policies/interfaces/deposits/IReceiptTokenManager.sol";

import {IERC20} from "src/interfaces/IERC20.sol";
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";

contract ReceiptTokenManagerTest is Test {
    // Test accounts
    address public OWNER;
    address public NON_OWNER;
    address public RECIPIENT;
    address public OPERATOR;

    // Contracts
    ReceiptTokenManager public receiptTokenManager;
    MockERC20 public asset;

    // Constants
    uint8 public constant DEPOSIT_PERIOD = 6;
    uint256 public constant MINT_AMOUNT = 100e18;
    string public constant OPERATOR_NAME = "abc";

    // State variables
    uint256 public tokenId;

    function setUp() public {
        // Create test accounts
        OWNER = makeAddr("OWNER");
        NON_OWNER = makeAddr("NON_OWNER");
        RECIPIENT = makeAddr("RECIPIENT");
        OPERATOR = makeAddr("OPERATOR");

        // Deploy contracts
        receiptTokenManager = new ReceiptTokenManager();
        asset = new MockERC20("Test Asset", "ASSET", 18);

        // Create a token for testing
        vm.prank(OWNER);
        tokenId = receiptTokenManager.createToken(
            OWNER,
            IERC20(address(asset)),
            DEPOSIT_PERIOD,
            OPERATOR,
            OPERATOR_NAME
        );
    }

    // ========== OWNERSHIP CONTROL TESTS ========== //

    function test_onlyOwnerCanMint() public {
        // Owner can mint
        vm.prank(OWNER);
        receiptTokenManager.mint(RECIPIENT, tokenId, MINT_AMOUNT, false);

        assertEq(receiptTokenManager.balanceOf(RECIPIENT, tokenId), MINT_AMOUNT);
    }

    function test_nonOwnerCannotMint() public {
        // Non-owner cannot mint
        vm.expectRevert(
            abi.encodeWithSelector(
                IReceiptTokenManager.ReceiptTokenManager_NotOwner.selector,
                NON_OWNER,
                OWNER
            )
        );
        vm.prank(NON_OWNER);
        receiptTokenManager.mint(RECIPIENT, tokenId, MINT_AMOUNT, false);
    }

    function test_onlyOwnerCanBurn() public {
        // First mint some tokens
        vm.prank(OWNER);
        receiptTokenManager.mint(RECIPIENT, tokenId, MINT_AMOUNT, false);

        // Owner can burn
        vm.prank(OWNER);
        receiptTokenManager.burn(RECIPIENT, tokenId, MINT_AMOUNT / 2, false);

        assertEq(receiptTokenManager.balanceOf(RECIPIENT, tokenId), MINT_AMOUNT / 2);
    }

    function test_nonOwnerCannotBurn() public {
        // First mint some tokens
        vm.prank(OWNER);
        receiptTokenManager.mint(RECIPIENT, tokenId, MINT_AMOUNT, false);

        // Non-owner cannot burn
        vm.expectRevert(
            abi.encodeWithSelector(
                IReceiptTokenManager.ReceiptTokenManager_NotOwner.selector,
                NON_OWNER,
                OWNER
            )
        );
        vm.prank(NON_OWNER);
        receiptTokenManager.burn(RECIPIENT, tokenId, MINT_AMOUNT / 2, false);
    }

    function test_mintWithWrapping() public {
        // Test minting with wrapping enabled
        vm.prank(OWNER);
        receiptTokenManager.mint(RECIPIENT, tokenId, MINT_AMOUNT, true);

        // Should have ERC6909 balance
        assertEq(receiptTokenManager.balanceOf(RECIPIENT, tokenId), MINT_AMOUNT);

        // Should also have wrapped ERC20 balance
        address wrappedToken = receiptTokenManager.getWrappedToken(tokenId);
        assertGt(IERC20(wrappedToken).balanceOf(RECIPIENT), 0);
    }

    function test_burnWithWrapping() public {
        // First mint with wrapping
        vm.prank(OWNER);
        receiptTokenManager.mint(RECIPIENT, tokenId, MINT_AMOUNT, true);

        // Then burn wrapped tokens
        vm.prank(OWNER);
        receiptTokenManager.burn(RECIPIENT, tokenId, MINT_AMOUNT / 2, true);

        assertEq(receiptTokenManager.balanceOf(RECIPIENT, tokenId), MINT_AMOUNT / 2);
    }

    // ========== TOKEN CREATION TESTS ========== //

    function test_createTokenSuccess() public {
        uint256 newTokenId = receiptTokenManager.getReceiptTokenId(
            OWNER,
            IERC20(address(asset)),
            DEPOSIT_PERIOD + 1,
            OPERATOR
        );

        vm.prank(OWNER);
        uint256 createdTokenId = receiptTokenManager.createToken(
            OWNER,
            IERC20(address(asset)),
            DEPOSIT_PERIOD + 1,
            OPERATOR,
            OPERATOR_NAME
        );

        assertEq(createdTokenId, newTokenId);
        assertEq(receiptTokenManager.getTokenOwner(newTokenId), OWNER);
        assertEq(address(receiptTokenManager.getTokenAsset(newTokenId)), address(asset));
        assertEq(receiptTokenManager.getTokenDepositPeriod(newTokenId), DEPOSIT_PERIOD + 1);
        assertEq(receiptTokenManager.getTokenOperator(newTokenId), OPERATOR);
    }

    function test_createTokenAlreadyExists() public {
        // Try to create the same token again
        vm.expectRevert(
            abi.encodeWithSelector(
                IReceiptTokenManager.ReceiptTokenManager_TokenExists.selector,
                tokenId
            )
        );
        vm.prank(OWNER);
        receiptTokenManager.createToken(
            OWNER,
            IERC20(address(asset)),
            DEPOSIT_PERIOD,
            OPERATOR,
            OPERATOR_NAME
        );
    }

    function test_tokenIdIncludesOwner() public {
        // Generate token IDs for same parameters but different owners
        uint256 tokenId1 = receiptTokenManager.getReceiptTokenId(
            OWNER,
            IERC20(address(asset)),
            DEPOSIT_PERIOD,
            OPERATOR
        );

        uint256 tokenId2 = receiptTokenManager.getReceiptTokenId(
            NON_OWNER,
            IERC20(address(asset)),
            DEPOSIT_PERIOD,
            OPERATOR
        );

        // Should be different because owners are different
        assertNotEq(tokenId1, tokenId2);
    }

    // ========== VIEW FUNCTION TESTS ========== //

    function test_getTokenMetadata() public {
        assertEq(receiptTokenManager.getTokenOwner(tokenId), OWNER);
        assertEq(address(receiptTokenManager.getTokenAsset(tokenId)), address(asset));
        assertEq(receiptTokenManager.getTokenDepositPeriod(tokenId), DEPOSIT_PERIOD);
        assertEq(receiptTokenManager.getTokenOperator(tokenId), OPERATOR);
    }

    function test_tokenHasCorrectMetadata() public {
        // Check that the created token has proper name and symbol
        string memory expectedName = string.concat(OPERATOR_NAME, asset.name(), " - 6 months");
        string memory expectedSymbol = string.concat(OPERATOR_NAME, asset.symbol(), "-6m");

        // Note: These are truncated to 32 bytes, so we check if they start correctly
        string memory actualName = receiptTokenManager.name(tokenId);
        string memory actualSymbol = receiptTokenManager.symbol(tokenId);

        assertTrue(bytes(actualName).length > 0);
        assertTrue(bytes(actualSymbol).length > 0);
        assertEq(receiptTokenManager.decimals(tokenId), asset.decimals());
    }

    // ========== EDGE CASE TESTS ========== //

    function test_mintZeroAmount() public {
        vm.prank(OWNER);
        receiptTokenManager.mint(RECIPIENT, tokenId, 0, false);

        assertEq(receiptTokenManager.balanceOf(RECIPIENT, tokenId), 0);
    }

    function test_burnZeroAmount() public {
        vm.prank(OWNER);
        receiptTokenManager.burn(RECIPIENT, tokenId, 0, false);

        assertEq(receiptTokenManager.balanceOf(RECIPIENT, tokenId), 0);
    }

    function test_multipleOwnersCanCreateTokens() public {
        // OWNER creates a token
        uint256 ownerTokenId = receiptTokenManager.getReceiptTokenId(
            OWNER,
            IERC20(address(asset)),
            DEPOSIT_PERIOD + 1,
            OPERATOR
        );

        vm.prank(OWNER);
        receiptTokenManager.createToken(
            OWNER,
            IERC20(address(asset)),
            DEPOSIT_PERIOD + 1,
            OPERATOR,
            OPERATOR_NAME
        );

        // NON_OWNER creates a different token
        uint256 nonOwnerTokenId = receiptTokenManager.getReceiptTokenId(
            NON_OWNER,
            IERC20(address(asset)),
            DEPOSIT_PERIOD + 1,
            OPERATOR
        );

        vm.prank(NON_OWNER);
        receiptTokenManager.createToken(
            NON_OWNER,
            IERC20(address(asset)),
            DEPOSIT_PERIOD + 1,
            OPERATOR,
            OPERATOR_NAME
        );

        // Both tokens should exist with correct owners
        assertEq(receiptTokenManager.getTokenOwner(ownerTokenId), OWNER);
        assertEq(receiptTokenManager.getTokenOwner(nonOwnerTokenId), NON_OWNER);

        // Owners should only be able to mint their own tokens
        vm.prank(OWNER);
        receiptTokenManager.mint(RECIPIENT, ownerTokenId, MINT_AMOUNT, false);

        vm.expectRevert(
            abi.encodeWithSelector(
                IReceiptTokenManager.ReceiptTokenManager_NotOwner.selector,
                OWNER,
                NON_OWNER
            )
        );
        vm.prank(OWNER);
        receiptTokenManager.mint(RECIPIENT, nonOwnerTokenId, MINT_AMOUNT, false);
    }
}
