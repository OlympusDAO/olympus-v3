// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.20;

import {Test} from "@forge-std-1.9.6/Test.sol";
import {console2} from "@forge-std-1.9.6/console2.sol";

import {ReceiptTokenManager} from "src/policies/deposits/ReceiptTokenManager.sol";
import {IReceiptTokenManager} from "src/policies/interfaces/deposits/IReceiptTokenManager.sol";

import {IERC20} from "src/interfaces/IERC20.sol";
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {IERC6909Wrappable} from "src/interfaces/IERC6909Wrappable.sol";
import {IDepositReceiptToken} from "src/interfaces/IDepositReceiptToken.sol";

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
        _;
    }

    modifier mintToRecipient() {
        vm.prank(OWNER);
        receiptTokenManager.mint(RECIPIENT, _tokenId, MINT_AMOUNT, false);
        _;
    }

    modifier allowOwnerToSpend() {
        vm.prank(RECIPIENT);
        receiptTokenManager.approve(OWNER, _tokenId, MINT_AMOUNT);
        _;
    }

    modifier allowOwnerToSpendAll() {
        vm.prank(RECIPIENT);
        receiptTokenManager.approve(OWNER, _tokenId, type(uint256).max);
        _;
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
