// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.20;

import {ReceiptTokenManagerTest} from "./ReceiptTokenManagerTest.sol";
import {IReceiptTokenManager} from "src/policies/interfaces/deposits/IReceiptTokenManager.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {String} from "src/libraries/String.sol";
import {IDepositReceiptToken} from "src/interfaces/IDepositReceiptToken.sol";
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";

/**
 * @title CreateTokenTest
 * @notice Tests for ReceiptTokenManager token creation functionality
 */
contract ReceiptTokenManagerCreateTokenTest is ReceiptTokenManagerTest {
    using String for string;

    // given token creation parameters
    //  [X] token is created successfully
    //  [X] token ID matches expected value
    //  [X] token is marked as valid
    //  [X] token has correct name
    //  [X] token has correct symbol
    //  [X] token has correct decimals
    //  [X] token has correct owner
    //  [X] token has correct asset
    //  [X] token has correct deposit period
    //  [X] token has correct operator
    function test_createTokenSuccess() public {
        uint256 expectedTokenId = receiptTokenManager.getReceiptTokenId(
            OWNER,
            IERC20(address(asset)),
            DEPOSIT_PERIOD,
            OPERATOR
        );

        vm.prank(OWNER);
        uint256 createdTokenId = receiptTokenManager.createToken(
            IERC20(address(asset)),
            DEPOSIT_PERIOD,
            OPERATOR,
            OPERATOR_NAME
        );

        // Basic token validation
        assertEq(
            createdTokenId,
            expectedTokenId,
            "Created token ID should match expected token ID"
        );
        assertTrue(
            receiptTokenManager.isValidTokenId(createdTokenId),
            "Created token should be marked as valid"
        );

        // Token metadata assertions
        string memory tokenName = receiptTokenManager.getTokenName(createdTokenId);
        string memory tokenSymbol = receiptTokenManager.getTokenSymbol(createdTokenId);
        uint8 tokenDecimals = receiptTokenManager.getTokenDecimals(createdTokenId);

        // Check exact names using truncate32
        string memory expectedName = string
            .concat(OPERATOR_NAME, asset.name(), " - 6 months")
            .truncate32();
        string memory expectedSymbol = string
            .concat(OPERATOR_NAME, asset.symbol(), "-6m")
            .truncate32();

        assertEq(tokenName, expectedName, "Token name should match expected truncated name");
        assertEq(
            tokenSymbol,
            expectedSymbol,
            "Token symbol should match expected truncated symbol"
        );
        assertEq(
            tokenDecimals,
            asset.decimals(),
            "Token decimals should match underlying asset decimals"
        );

        // Token properties assertions
        assertEq(
            receiptTokenManager.getTokenOwner(createdTokenId),
            OWNER,
            "Token owner should be the caller (msg.sender)"
        );
        assertEq(
            address(receiptTokenManager.getTokenAsset(createdTokenId)),
            address(asset),
            "Token asset should match the provided asset"
        );
        assertEq(
            receiptTokenManager.getTokenDepositPeriod(createdTokenId),
            DEPOSIT_PERIOD,
            "Token deposit period should match the provided period"
        );
        assertEq(
            receiptTokenManager.getTokenOperator(createdTokenId),
            OPERATOR,
            "Token operator should match the provided operator"
        );

        // Wrapped token should be automatically created
        address wrappedToken = receiptTokenManager.getWrappedToken(createdTokenId);
        assertNotEq(wrappedToken, address(0), "Wrapped token should be automatically created");

        // Verify cloned ERC20 attributes
        IDepositReceiptToken wrappedTokenContract = IDepositReceiptToken(wrappedToken);
        assertEq(
            wrappedTokenContract.name(),
            expectedName,
            "Wrapped token name should match expected name"
        );
        assertEq(
            wrappedTokenContract.symbol(),
            expectedSymbol,
            "Wrapped token symbol should match expected symbol"
        );
        assertEq(
            wrappedTokenContract.decimals(),
            asset.decimals(),
            "Wrapped token decimals should match asset decimals"
        );
        assertEq(
            wrappedTokenContract.owner(),
            address(receiptTokenManager),
            "Wrapped token owner should be ReceiptTokenManager"
        );
        assertEq(
            address(wrappedTokenContract.asset()),
            address(asset),
            "Wrapped token asset should match provided asset"
        );
        assertEq(
            wrappedTokenContract.depositPeriod(),
            DEPOSIT_PERIOD,
            "Wrapped token deposit period should match provided period"
        );
        assertEq(
            wrappedTokenContract.operator(),
            OPERATOR,
            "Wrapped token operator should match provided operator"
        );
    }

    // given duplicate token creation attempt
    //  [X] reverts with TokenExists error
    function test_createTokenAlreadyExists() public {
        // Create token first time
        vm.prank(OWNER);
        uint256 tokenId = receiptTokenManager.createToken(
            IERC20(address(asset)),
            DEPOSIT_PERIOD,
            OPERATOR,
            OPERATOR_NAME
        );

        // Try to create the same token again
        vm.expectRevert(
            abi.encodeWithSelector(
                IReceiptTokenManager.ReceiptTokenManager_TokenExists.selector,
                tokenId
            )
        );
        vm.prank(OWNER);
        receiptTokenManager.createToken(
            IERC20(address(asset)),
            DEPOSIT_PERIOD,
            OPERATOR,
            OPERATOR_NAME
        );
    }

    // given different owners create tokens with same parameters
    //  [X] token IDs are different (owner included in hash)
    function test_tokenIdIncludesOwner() public view {
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
        assertNotEq(tokenId1, tokenId2, "Token IDs should be different when owners are different");
    }

    // given different owners create tokens with same parameters
    //  [X] both tokens exist with correct owners
    //  [X] both tokens have correct metadata and properties
    function test_multipleOwnersCanCreateTokens() public {
        // OWNER creates a token
        uint256 ownerTokenId = receiptTokenManager.getReceiptTokenId(
            OWNER,
            IERC20(address(asset)),
            DEPOSIT_PERIOD,
            OPERATOR
        );

        vm.prank(OWNER);
        receiptTokenManager.createToken(
            IERC20(address(asset)),
            DEPOSIT_PERIOD,
            OPERATOR,
            OPERATOR_NAME
        );

        // NON_OWNER creates a different token
        uint256 nonOwnerTokenId = receiptTokenManager.getReceiptTokenId(
            NON_OWNER,
            IERC20(address(asset)),
            DEPOSIT_PERIOD,
            OPERATOR
        );

        vm.prank(NON_OWNER);
        receiptTokenManager.createToken(
            IERC20(address(asset)),
            DEPOSIT_PERIOD,
            OPERATOR,
            OPERATOR_NAME
        );

        // Verify both tokens exist with correct owners
        assertEq(
            receiptTokenManager.getTokenOwner(ownerTokenId),
            OWNER,
            "First token should be owned by OWNER"
        );
        assertEq(
            receiptTokenManager.getTokenOwner(nonOwnerTokenId),
            NON_OWNER,
            "Second token should be owned by NON_OWNER"
        );

        // Verify both wrapped tokens are created
        address wrappedToken1 = receiptTokenManager.getWrappedToken(ownerTokenId);
        address wrappedToken2 = receiptTokenManager.getWrappedToken(nonOwnerTokenId);
        assertNotEq(wrappedToken1, address(0), "First wrapped token should be created");
        assertNotEq(wrappedToken2, address(0), "Second wrapped token should be created");
        assertNotEq(
            wrappedToken1,
            wrappedToken2,
            "Wrapped tokens should be different for different token IDs"
        );

        // Verify both tokens have correct properties (same except for owner)
        // First token assertions
        assertTrue(
            bytes(receiptTokenManager.getTokenName(ownerTokenId)).length > 0,
            "First token should have a name"
        );
        assertTrue(
            bytes(receiptTokenManager.getTokenSymbol(ownerTokenId)).length > 0,
            "First token should have a symbol"
        );
        assertEq(
            receiptTokenManager.getTokenDecimals(ownerTokenId),
            asset.decimals(),
            "First token decimals should match asset"
        );
        assertEq(
            address(receiptTokenManager.getTokenAsset(ownerTokenId)),
            address(asset),
            "First token asset should match"
        );
        assertEq(
            receiptTokenManager.getTokenDepositPeriod(ownerTokenId),
            DEPOSIT_PERIOD,
            "First token deposit period should match"
        );
        assertEq(
            receiptTokenManager.getTokenOperator(ownerTokenId),
            OPERATOR,
            "First token operator should match"
        );

        // Second token assertions
        assertTrue(
            bytes(receiptTokenManager.getTokenName(nonOwnerTokenId)).length > 0,
            "Second token should have a name"
        );
        assertTrue(
            bytes(receiptTokenManager.getTokenSymbol(nonOwnerTokenId)).length > 0,
            "Second token should have a symbol"
        );
        assertEq(
            receiptTokenManager.getTokenDecimals(nonOwnerTokenId),
            asset.decimals(),
            "Second token decimals should match asset"
        );
        assertEq(
            address(receiptTokenManager.getTokenAsset(nonOwnerTokenId)),
            address(asset),
            "Second token asset should match"
        );
        assertEq(
            receiptTokenManager.getTokenDepositPeriod(nonOwnerTokenId),
            DEPOSIT_PERIOD,
            "Second token deposit period should match"
        );
        assertEq(
            receiptTokenManager.getTokenOperator(nonOwnerTokenId),
            OPERATOR,
            "Second token operator should match"
        );
    }

    // given token metadata validation
    //  [X] name is set correctly (truncated to 32 bytes)
    function test_tokenHasCorrectName() public {
        vm.prank(OWNER);
        uint256 tokenId = receiptTokenManager.createToken(
            IERC20(address(asset)),
            DEPOSIT_PERIOD,
            OPERATOR,
            OPERATOR_NAME
        );

        string memory actualName = receiptTokenManager.getTokenName(tokenId);
        assertTrue(bytes(actualName).length > 0, "Token name should not be empty");

        // Name should be exactly equal to the truncated expected name
        string memory expectedName = string
            .concat(OPERATOR_NAME, asset.name(), " - 6 months")
            .truncate32();
        assertEq(actualName, expectedName, "Token name should match expected truncated name");
    }

    // given token metadata validation
    //  [X] symbol is set correctly (truncated to 32 bytes)
    function test_tokenHasCorrectSymbol() public {
        vm.prank(OWNER);
        uint256 tokenId = receiptTokenManager.createToken(
            IERC20(address(asset)),
            DEPOSIT_PERIOD,
            OPERATOR,
            OPERATOR_NAME
        );

        string memory actualSymbol = receiptTokenManager.getTokenSymbol(tokenId);
        assertTrue(bytes(actualSymbol).length > 0, "Token symbol should not be empty");

        // Symbol should be exactly equal to the truncated expected symbol
        string memory expectedSymbol = string
            .concat(OPERATOR_NAME, asset.symbol(), "-6m")
            .truncate32();
        assertEq(
            actualSymbol,
            expectedSymbol,
            "Token symbol should match expected truncated symbol"
        );
    }

    // given token metadata validation
    //  [X] decimals match underlying asset
    function test_tokenHasCorrectDecimals() public {
        vm.prank(OWNER);
        uint256 tokenId = receiptTokenManager.createToken(
            IERC20(address(asset)),
            DEPOSIT_PERIOD,
            OPERATOR,
            OPERATOR_NAME
        );

        assertEq(
            receiptTokenManager.getTokenDecimals(tokenId),
            asset.decimals(),
            "Token decimals should match underlying asset decimals"
        );
    }

    // given token ownership and security
    //  [X] msg.sender becomes token owner
    function test_tokenOwnershipSetCorrectly() public {
        vm.prank(OWNER);
        uint256 tokenId = receiptTokenManager.createToken(
            IERC20(address(asset)),
            DEPOSIT_PERIOD,
            OPERATOR,
            OPERATOR_NAME
        );

        assertEq(
            receiptTokenManager.getTokenOwner(tokenId),
            OWNER,
            "Token owner should be the caller (msg.sender)"
        );
    }

    // given token ownership and security
    //  [X] asset is stored correctly
    //  [X] deposit period is stored correctly
    //  [X] operator is stored correctly
    function test_tokenMetadataSetCorrectly() public {
        vm.prank(OWNER);
        uint256 tokenId = receiptTokenManager.createToken(
            IERC20(address(asset)),
            DEPOSIT_PERIOD,
            OPERATOR,
            OPERATOR_NAME
        );

        assertEq(
            address(receiptTokenManager.getTokenAsset(tokenId)),
            address(asset),
            "Token asset should match the provided asset"
        );
        assertEq(
            receiptTokenManager.getTokenDepositPeriod(tokenId),
            DEPOSIT_PERIOD,
            "Token deposit period should match the provided period"
        );
        assertEq(
            receiptTokenManager.getTokenOperator(tokenId),
            OPERATOR,
            "Token operator should match the provided operator"
        );
    }

    // ========== PARAMETER VALIDATION TESTS ========== //

    // given zero address asset
    //  [X] reverts with InvalidParams error
    function test_createTokenZeroAsset_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IReceiptTokenManager.ReceiptTokenManager_InvalidParams.selector,
                "asset"
            )
        );
        vm.prank(OWNER);
        receiptTokenManager.createToken(
            IERC20(address(0)),
            DEPOSIT_PERIOD,
            OPERATOR,
            OPERATOR_NAME
        );
    }

    // given zero deposit period
    //  [X] reverts with InvalidParams error
    function test_createTokenZeroDepositPeriod_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IReceiptTokenManager.ReceiptTokenManager_InvalidParams.selector,
                "depositPeriod"
            )
        );
        vm.prank(OWNER);
        receiptTokenManager.createToken(IERC20(address(asset)), 0, OPERATOR, OPERATOR_NAME);
    }

    // given zero address operator
    //  [X] reverts with InvalidParams error
    function test_createTokenZeroOperator_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IReceiptTokenManager.ReceiptTokenManager_InvalidParams.selector,
                "operator"
            )
        );
        vm.prank(OWNER);
        receiptTokenManager.createToken(
            IERC20(address(asset)),
            DEPOSIT_PERIOD,
            address(0),
            OPERATOR_NAME
        );
    }

    // given empty operator name
    //  [X] succeeds (empty operator names are allowed)
    function test_createTokenEmptyOperatorName_succeeds() public {
        vm.prank(OWNER);
        uint256 tokenId = receiptTokenManager.createToken(
            IERC20(address(asset)),
            DEPOSIT_PERIOD,
            OPERATOR,
            "" // Empty operator name should be allowed
        );

        // Verify token was created successfully
        assertTrue(
            receiptTokenManager.isValidTokenId(tokenId),
            "Token should be created successfully with empty operator name"
        );
        assertEq(
            receiptTokenManager.getTokenOwner(tokenId),
            OWNER,
            "Token owner should be set correctly"
        );
    }

    // given asset with 0 decimals
    //  [X] token is created successfully
    //  [X] token can be minted (ERC6909 and wrapped)
    //  [X] token has correct decimals (0)
    //  [X] wrapped token has correct decimals (0)
    function test_createTokenZeroDecimals_succeeds() public {
        // Create an asset with 0 decimals
        MockERC20 zeroDecimalsAsset = new MockERC20("ZeroToken", "ZERO", 0);
        
        vm.prank(OWNER);
        uint256 tokenId = receiptTokenManager.createToken(
            IERC20(address(zeroDecimalsAsset)),
            DEPOSIT_PERIOD,
            OPERATOR,
            OPERATOR_NAME
        );

        // Verify token was created successfully
        assertTrue(
            receiptTokenManager.isValidTokenId(tokenId),
            "Token with 0 decimals should be created successfully"
        );
        
        // Verify token has correct decimals
        assertEq(
            receiptTokenManager.getTokenDecimals(tokenId),
            0,
            "Token should have 0 decimals"
        );
        
        // Verify wrapped token has correct decimals
        address wrappedToken = receiptTokenManager.getWrappedToken(tokenId);
        assertNotEq(wrappedToken, address(0), "Wrapped token should exist");
        assertEq(
            IDepositReceiptToken(wrappedToken).decimals(),
            0,
            "Wrapped token should have 0 decimals"
        );
        
        // Test minting ERC6909 tokens
        uint256 mintAmount = 100; // No decimals, so just use whole number
        vm.prank(OWNER);
        receiptTokenManager.mint(OWNER, tokenId, mintAmount, false);
        
        assertEq(
            receiptTokenManager.balanceOf(OWNER, tokenId),
            mintAmount,
            "ERC6909 balance should match minted amount"
        );
        
        // Test minting wrapped tokens
        vm.prank(OWNER);
        receiptTokenManager.mint(OWNER, tokenId, mintAmount, true);
        
        assertEq(
            IDepositReceiptToken(wrappedToken).balanceOf(OWNER),
            mintAmount,
            "Wrapped token balance should match minted amount"
        );
    }
}
