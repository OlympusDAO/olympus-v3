// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.15;

import {WithEnvironment} from "src/scripts/WithEnvironment.s.sol";
import {console2} from "@forge-std-1.9.6/console2.sol";

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IConvertibleDepositAuctioneer} from "src/policies/interfaces/deposits/IConvertibleDepositAuctioneer.sol";
import {IConvertibleDepositFacility} from "src/policies/interfaces/deposits/IConvertibleDepositFacility.sol";
import {IReceiptTokenManager} from "src/policies/interfaces/deposits/IReceiptTokenManager.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IDepositPositionManager} from "src/modules/DEPOS/IDepositPositionManager.sol";

// Mocks for testnet use
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";

/// @notice Automated script for bidding in ConvertibleDepositAuctioneer and converting positions
/// @dev    This script provides a streamlined interface with automatic parameter calculation
contract ConvertibleDepositBid is WithEnvironment {
    // ========== CONSTANTS ========== //

    /// @notice Slippage tolerance for minimum OHM out (5%)
    uint256 public constant SLIPPAGE_TOLERANCE = 5e16; // 5%
    uint256 public constant ONE_HUNDRED_PERCENT = 1e18;

    // ========== STATE VARIABLES ========== //

    address public usds;
    address public ohm;
    address public auctioneer;
    address public facility;
    address public receiptTokenManager;
    address public depositManager;
    address public deposModule;

    // Bid results
    uint256 public lastOhmOut;
    uint256 public lastPositionId;
    uint256 public lastReceiptTokenId;
    uint256 public lastActualAmount;

    // Conversion results
    uint256 public lastReceiptTokenIn;
    uint256 public lastConvertedTokenOut;

    // ========== SETUP ========== //

    /// @notice Validate that the caller is not the foundry default deployer
    function _validateCaller() internal view {
        // solhint-disable-next-line gas-custom-errors
        require(
            msg.sender != address(0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38),
            "Cannot use the default foundry deployer address, specify using --sender"
        );
    }

    function _setUp(string memory chain_) internal {
        _loadEnv(chain_);

        // Load contract addresses
        usds = _envAddressNotZero("external.tokens.USDS");
        ohm = _envAddressNotZero("olympus.legacy.OHM");
        auctioneer = _envAddressNotZero("olympus.policies.ConvertibleDepositAuctioneer");
        facility = _envAddressNotZero("olympus.policies.ConvertibleDepositFacility");
        receiptTokenManager = _envAddressNotZero("olympus.periphery.ReceiptTokenManager");
        depositManager = _envAddressNotZero("olympus.policies.DepositManager");
        deposModule = _envAddressNotZero("olympus.modules.OlympusDepositPositionManager");

        console2.log("=== Loaded Contract Addresses ===");
        console2.log("USDS:", usds);
        console2.log("OHM:", ohm);
        console2.log("Auctioneer:", auctioneer);
        console2.log("Facility:", facility);
    }

    // ========== PUBLIC FUNCTIONS ========== //

    /// @notice Place a bid in the ConvertibleDepositAuctioneer
    /// @param chain_ The chain to interact with
    /// @param depositPeriod_ The deposit period in months
    /// @param bidAmount_ Amount of USDS to bid
    function bid(string memory chain_, uint8 depositPeriod_, uint256 bidAmount_) external {
        _validateCaller();
        _setUp(chain_);

        console2.log("\n=== Automated Convertible Deposit Bid ===");
        console2.log("Deposit Period (months):", depositPeriod_);
        console2.log("Bid Amount:", bidAmount_);

        // Preview the bid to determine expected OHM output
        uint256 expectedOhmOut = _previewBid(depositPeriod_, bidAmount_);
        console2.log("Expected OHM convertible:", expectedOhmOut);

        // Calculate minimum OHM out with slippage protection
        uint256 minOhmOut = (expectedOhmOut * (ONE_HUNDRED_PERCENT - SLIPPAGE_TOLERANCE)) /
            ONE_HUNDRED_PERCENT;
        console2.log("Minimum OHM out (with 5% slippage):", minOhmOut);

        // Execute the bid
        _mintUSDS(bidAmount_);
        _approveUSDS(bidAmount_);
        _submitBid(depositPeriod_, bidAmount_, minOhmOut);
        _verifyBidResults();

        console2.log("Bid completed successfully");
    }

    /// @notice Convert all available CD positions to OHM
    /// @param chain_ The chain to interact with
    /// @param depositPeriod_ The deposit period to convert positions for
    function convert(string memory chain_, uint8 depositPeriod_) external {
        _validateCaller();
        _setUp(chain_);

        console2.log("\n=== Automated CD Position Conversion ===");
        console2.log("Deposit Period (months):", depositPeriod_);

        // Get all positions for the caller
        (uint256[] memory positionIds, uint256[] memory amounts) = _getConvertiblePositions(
            msg.sender,
            depositPeriod_
        );

        if (positionIds.length == 0) {
            console2.log("No convertible positions found");
            return;
        }

        console2.log("Found", positionIds.length, "convertible positions");

        // Preview the conversion
        (uint256 expectedReceiptIn, uint256 expectedOhmOut) = _previewConversion(
            msg.sender,
            positionIds,
            amounts
        );
        console2.log("Expected receipt tokens consumed:", expectedReceiptIn);
        console2.log("Expected OHM tokens minted:", expectedOhmOut);

        // Execute the conversion
        // Get receipt token ID for approval
        uint256 receiptTokenId = IDepositManager(depositManager).getReceiptTokenId(
            IERC20(usds),
            depositPeriod_,
            facility
        );
        _approveReceiptTokens(receiptTokenId, expectedReceiptIn);
        _performConversion(positionIds, amounts);
        _verifyConversionResults(expectedReceiptIn, expectedOhmOut);

        console2.log("Conversion completed successfully");
    }

    // ========== INTERNAL BID FUNCTIONS ========== //

    /// @notice Preview the OHM output from a bid
    function _previewBid(uint8 depositPeriod_, uint256 bidAmount_) internal view returns (uint256) {
        return IConvertibleDepositAuctioneer(auctioneer).previewBid(depositPeriod_, bidAmount_);
    }

    /// @notice Mint USDS tokens for the bid
    function _mintUSDS(uint256 amount_) internal {
        console2.log("\n1. Minting USDS tokens");

        uint256 balanceBefore = IERC20(usds).balanceOf(msg.sender);

        // Mint USDS (assuming it's a MockERC20 for testnet)
        vm.broadcast();
        MockERC20(usds).mint(msg.sender, amount_);

        uint256 balanceAfter = IERC20(usds).balanceOf(msg.sender);
        console2.log("  Minted USDS:", balanceAfter - balanceBefore);
    }

    /// @notice Approve USDS spending by the auctioneer
    function _approveUSDS(uint256 amount_) internal {
        console2.log("\n2. Approving USDS spending");

        vm.broadcast();
        IERC20(usds).approve(depositManager, amount_);

        console2.log("  Approved", amount_, "USDS for depositManager");
    }

    /// @notice Submit the bid to the auctioneer
    function _submitBid(uint8 depositPeriod_, uint256 bidAmount_, uint256 minOhmOut_) internal {
        console2.log("\n3. Submitting bid");

        vm.broadcast();
        (
            lastOhmOut,
            lastPositionId,
            lastReceiptTokenId,
            lastActualAmount
        ) = IConvertibleDepositAuctioneer(auctioneer).bid(
            depositPeriod_,
            bidAmount_,
            minOhmOut_,
            false, // wrapPosition
            false // wrapReceipt
        );

        console2.log("  Actual OHM convertible:", lastOhmOut);
        console2.log("  Position ID created:", lastPositionId);
        console2.log("  Receipt Token ID:", lastReceiptTokenId);
        console2.log("  Actual amount deposited:", lastActualAmount);
    }

    /// @notice Verify the bid results
    function _verifyBidResults() internal view {
        console2.log("\n4. Verifying bid results");

        // Check receipt token balance
        uint256 receiptBalance = IReceiptTokenManager(receiptTokenManager).balanceOf(
            msg.sender,
            lastReceiptTokenId
        );
        console2.log("  Receipt token balance:", receiptBalance);

        // solhint-disable-next-line gas-custom-errors
        require(receiptBalance >= lastActualAmount, "Insufficient receipt tokens received");
        console2.log("  Receipt tokens verified");
    }

    // ========== INTERNAL CONVERSION FUNCTIONS ========== //

    /// @notice Get all convertible positions for a user
    function _getConvertiblePositions(
        address user_,
        uint8 depositPeriod_
    ) internal view returns (uint256[] memory positionIds, uint256[] memory amounts) {
        // Get the receipt token ID for USDS and the specified deposit period
        uint256 receiptTokenId = IDepositManager(depositManager).getReceiptTokenId(
            IERC20(usds),
            depositPeriod_,
            facility
        );

        console2.log("  Receipt token ID for USDS period", depositPeriod_, ":", receiptTokenId);

        // Check if user has any receipt tokens
        uint256 receiptBalance = IReceiptTokenManager(receiptTokenManager).balanceOf(
            user_,
            receiptTokenId
        );
        console2.log("  User receipt token balance:", receiptBalance);

        if (receiptBalance == 0) {
            // Return empty arrays
            return (new uint256[](0), new uint256[](0));
        }

        // Get all position IDs owned by the user
        uint256[] memory allUserPositions = IDepositPositionManager(deposModule).getUserPositionIds(
            user_
        );
        console2.log("  Total user positions:", allUserPositions.length);

        // Find the first matching position and return it
        for (uint256 i = 0; i < allUserPositions.length; i++) {
            // Get position data to check if it matches our criteria
            IDepositPositionManager.Position memory position = IDepositPositionManager(deposModule)
                .getPosition(allUserPositions[i]);

            // Check if this position matches our asset and deposit period and has remaining deposit
            if (
                position.asset == usds &&
                position.periodMonths == depositPeriod_ &&
                position.remainingDeposit > 0
            ) {
                console2.log("    Found matching position:", allUserPositions[i]);
                console2.log("    Remaining deposit:", position.remainingDeposit);

                // Create single-element arrays for the found position
                positionIds = new uint256[](1);
                amounts = new uint256[](1);
                positionIds[0] = allUserPositions[i];
                amounts[0] = position.remainingDeposit;

                console2.log("  Convertible positions found: 1");
                return (positionIds, amounts);
            }
        }

        // No matching positions found
        console2.log("  Convertible positions found: 0");
        return (new uint256[](0), new uint256[](0));
    }

    /// @notice Preview the conversion output
    function _previewConversion(
        address user_,
        uint256[] memory positionIds_,
        uint256[] memory amounts_
    ) internal view returns (uint256 receiptTokenIn, uint256 convertedTokenOut) {
        return IConvertibleDepositFacility(facility).previewConvert(user_, positionIds_, amounts_);
    }

    /// @notice Approve receipt token spending
    function _approveReceiptTokens(uint256 receiptTokenId_, uint256 amount_) internal {
        console2.log("\n1. Approving receipt token spending");

        vm.broadcast();
        IReceiptTokenManager(receiptTokenManager).approve(depositManager, receiptTokenId_, amount_);

        console2.log("  Approved deposit manager to spend receipt tokens");
        console2.log("  Token ID:", receiptTokenId_);
        console2.log("  Amount:", amount_);
    }

    /// @notice Perform the actual conversion
    function _performConversion(uint256[] memory positionIds_, uint256[] memory amounts_) internal {
        console2.log("\n2. Converting positions to OHM");

        uint256 ohmBalanceBefore = IERC20(ohm).balanceOf(msg.sender);
        console2.log("  OHM balance before conversion:", ohmBalanceBefore);

        vm.broadcast();
        (lastReceiptTokenIn, lastConvertedTokenOut) = IConvertibleDepositFacility(facility).convert(
            positionIds_,
            amounts_,
            false // wrappedReceipt
        );

        console2.log("  Actual receipt tokens consumed:", lastReceiptTokenIn);
        console2.log("  Actual OHM tokens minted:", lastConvertedTokenOut);
    }

    /// @notice Verify conversion results
    function _verifyConversionResults(
        uint256 expectedReceiptIn_,
        uint256 expectedOhmOut_
    ) internal view {
        console2.log("\n3. Verifying conversion results");

        // Check OHM balance increased
        uint256 ohmBalanceAfter = IERC20(ohm).balanceOf(msg.sender);
        console2.log("  Final OHM balance:", ohmBalanceAfter);

        // Verify expected vs actual
        console2.log("  Expected receipt tokens consumed:", expectedReceiptIn_);
        console2.log("  Actual receipt tokens consumed:", lastReceiptTokenIn);
        console2.log("  Expected OHM minted:", expectedOhmOut_);
        console2.log("  Actual OHM minted:", lastConvertedTokenOut);

        // solhint-disable-next-line gas-custom-errors
        require(lastConvertedTokenOut > 0, "No OHM tokens minted");
        console2.log("  OHM tokens successfully minted");
    }
}
