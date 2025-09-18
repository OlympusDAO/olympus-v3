// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.20;

import {Test} from "@forge-std-1.9.6/Test.sol";

import {ReceiptTokenManager} from "src/policies/deposits/ReceiptTokenManager.sol";

import {IERC20} from "src/interfaces/IERC20.sol";
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {ERC6909} from "@openzeppelin-5.3.0/token/ERC6909/draft-ERC6909.sol";

/**
 * @title ReceiptTokenManagerTest
 * @notice Base test contract for ReceiptTokenManager tests
 */
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

    uint256 internal _tokenId;
    IERC20 internal _wrappedToken;

    modifier createReceiptToken() {
        vm.prank(OWNER);
        uint256 actualTokenId = receiptTokenManager.createToken(
            IERC20(address(asset)),
            DEPOSIT_PERIOD,
            OPERATOR,
            OPERATOR_NAME
        );
        // Verify the token ID matches our expected ID
        assertEq(actualTokenId, _tokenId, "Created token ID should match expected token ID");

        _wrappedToken = IERC20(receiptTokenManager.getWrappedToken(_tokenId));
        _;
    }

    modifier mintToRecipient() {
        vm.prank(OWNER);
        receiptTokenManager.mint(RECIPIENT, _tokenId, MINT_AMOUNT, false);
        _;
    }

    modifier mintToRecipientWrapped() {
        vm.prank(OWNER);
        receiptTokenManager.mint(RECIPIENT, _tokenId, MINT_AMOUNT, true);
        _;
    }

    modifier allowOwnerToSpend() {
        vm.prank(RECIPIENT);
        receiptTokenManager.approve(OWNER, _tokenId, MINT_AMOUNT);
        _;
    }

    modifier allowReceiptTokenManagerToSpendWrapped() {
        vm.prank(RECIPIENT);
        _wrappedToken.approve(address(receiptTokenManager), MINT_AMOUNT);
        _;
    }

    modifier allowOwnerToSpendAll() {
        vm.prank(RECIPIENT);
        receiptTokenManager.approve(OWNER, _tokenId, type(uint256).max);
        _;
    }

    // ========== HELPER FUNCTIONS ========== //

    /// @notice Helper to expect ERC6909InsufficientBalance revert
    function expectInsufficientBalance(address owner, uint256 balance, uint256 amount) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC6909.ERC6909InsufficientBalance.selector,
                owner,
                balance,
                amount,
                _tokenId
            )
        );
    }

    /// @notice Helper to expect ERC6909InsufficientAllowance revert
    function expectInsufficientAllowance(
        address spender,
        uint256 allowance,
        uint256 amount
    ) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC6909.ERC6909InsufficientAllowance.selector,
                spender,
                allowance,
                amount,
                _tokenId
            )
        );
    }

    /// @notice Helper to expect ERC6909InvalidReceiver revert
    function expectInvalidReceiver(address receiver_) internal {
        vm.expectRevert(abi.encodeWithSelector(ERC6909.ERC6909InvalidReceiver.selector, receiver_));
    }

    function setUp() public virtual {
        // Create test accounts
        OWNER = makeAddr("OWNER");
        NON_OWNER = makeAddr("NON_OWNER");
        RECIPIENT = makeAddr("RECIPIENT");
        OPERATOR = makeAddr("OPERATOR");

        // Deploy contracts
        receiptTokenManager = new ReceiptTokenManager();
        asset = new MockERC20("Test Asset", "ASSET", 18);

        // Generate the expected token ID (but don't create the token yet)
        _tokenId = receiptTokenManager.getReceiptTokenId(
            OWNER,
            IERC20(address(asset)),
            DEPOSIT_PERIOD,
            OPERATOR
        );
    }
}
