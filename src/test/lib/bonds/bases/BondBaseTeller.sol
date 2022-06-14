// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.10;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {Auth, Authority} from "solmate/auth/Auth.sol";

import {IBondTeller} from "../interfaces/IBondTeller.sol";
import {IBondCallback} from "../interfaces/IBondCallback.sol";
import {IBondAggregator} from "../interfaces/IBondAggregator.sol";
import {IBondAuctioneer} from "../interfaces/IBondAuctioneer.sol";

import {TransferHelper} from "libraries/TransferHelper.sol";
import {FullMath} from "libraries/FullMath.sol";

/// @title Bond Teller
/// @notice Bond Teller Base Contract
/// @dev Bond is a permissionless system to create Olympus-style bond markets
///      for any token pair. The markets do not require maintenance and will manage
///      bond prices based on activity. Bond issuers create BondMarkets that pay out
///      a Payout Token in exchange for deposited Quote Tokens. Users can purchase
///      future-dated Payout Tokens with Quote Tokens at the current market price and
///      receive Bond Tokens to represent their position while their bond vests.
///      Once the Bond Tokens vest, they can redeem it for the Quote Tokens.
///
/// @dev The Teller contract handles all interactions with end users and manages tokens
///      issued to represent bond positions. Users purchase bonds by depositing Quote Tokens
///      and receive a Bond Token (token type is implementation-specific) that represents
///      their payout and the designated expiry. Once a bond vests, Investors can redeem their
///      Bond Tokens for the underlying Payout Token. A Teller requires one or more Auctioneer
///      contracts to be deployed to provide markets for users to purchase bonds from.
///
/// @author Oighty, Zeus, Potted Meat, indigo
abstract contract BondBaseTeller is IBondTeller, Auth, ReentrancyGuard {
    using TransferHelper for ERC20;
    using FullMath for uint256;

    /* ========== ERRORS ========== */

    error Teller_InvalidCallback();
    error Teller_TokenNotMatured(uint48 maturesOn);
    error Teller_NotAuthorized();
    error Teller_TokenDoesNotExist(ERC20 underlying, uint48 expiry);
    error Teller_UnsupportedToken();
    error Teller_InvalidParams();

    /* ========== EVENTS ========== */
    event Bonded(uint256 indexed id, uint256 amount, uint256 payout);

    /* ========== STATE VARIABLES ========== */

    /// @notice Tokens the protocol prefers as fees. Used to change what fee is paid in if Quote Token is preferred.
    mapping(ERC20 => bool) public preferredFeeToken;

    /// @notice Fee tiers charged by the protocol. Index -> fee, 0 index is the default fee. Configurable by policy.
    mapping(uint256 => uint48) public feeTiers;

    /// @notice Fee tier applicable to each market owner. Default fee tier is 0. Configurable by policy.
    mapping(address => uint256) public partnerFeeTier;

    /// @notice 'Create' function fee discount. Amount standard fee is reduced by for partners who just want to use the 'create' function to issue bond tokens. Configurable by policy.
    uint48 public createFeeDiscount;

    uint48 public constant FEE_DECIMALS = 1e5; // one percent equals 1000.

    /// @notice Fees earned by the protocol by token
    mapping(ERC20 => uint256) public fees;

    // Address the protocol receives fees at
    address internal immutable _protocol;

    // BondAggregator contract with utility functions
    IBondAggregator internal immutable _aggregator;

    constructor(
        address protocol_,
        IBondAggregator aggregator_,
        address guardian_,
        Authority authority_
    ) Auth(guardian_, authority_) {
        _protocol = protocol_;
        _aggregator = aggregator_;

        feeTiers[0] = uint48(2500); // Default fee tier
        feeTiers[1] = uint48(1500);
        feeTiers[2] = uint48(1000);
    }

    /// @inheritdoc IBondTeller
    function setFeeTier(uint256 tier_, uint48 fee_)
        external
        override
        requiresAuth
    {
        /// Restricted to authorized addresses, initially restricted to guardian

        /// Check if the fee is valid
        if (fee_ > FEE_DECIMALS) revert Teller_InvalidParams();

        /// Set the fee for the tier
        feeTiers[tier_] = fee_;
    }

    /// @inheritdoc IBondTeller
    function setPartnerFeeTier(address partner_, uint256 tier_)
        external
        override
        requiresAuth
    {
        /// Restricted to authorized addresses, initially restricted to guardian

        /// Ensure fee tier is not 0
        if (feeTiers[tier_] == 0) revert Teller_InvalidParams();

        /// Set the fee tier for the partner
        partnerFeeTier[partner_] = tier_;
    }

    /// @inheritdoc IBondTeller
    function changePreferredTokenStatus(ERC20 token_, bool status_)
        external
        override
        requiresAuth
    {
        /// Restricted to authorized addresses, initially restricted to policy
        preferredFeeToken[token_] = status_;
    }

    /// @inheritdoc IBondTeller
    function claimFees(ERC20[] memory tokens_) external override requiresAuth {
        /// Restricted to authorized addresses, initially restricted to policy
        uint256 len = tokens_.length;
        for (uint256 i; i < len; ++i) {
            ERC20 token = tokens_[i];
            uint256 send = fees[token];

            fees[token] = 0;
            token.safeTransfer(_protocol, send);
        }
    }

    /// @inheritdoc IBondTeller
    function getFee(address partner_) external view returns (uint48) {
        return feeTiers[partnerFeeTier[partner_]];
    }

    /* ========== USER FUNCTIONS ========== */

    /// @inheritdoc IBondTeller
    function purchase(
        address recipient_,
        uint256 id_,
        uint256 amount_,
        uint256 minAmountOut_
    ) external virtual nonReentrant returns (uint256, uint48) {
        ERC20 payoutToken;
        ERC20 quoteToken;
        uint48 vesting;
        uint256 payout;

        bool feeInQuote;
        uint256 feeAmount;

        {
            IBondAuctioneer auctioneer = _aggregator.getAuctioneer(id_);
            address owner;
            (owner, , payoutToken, quoteToken, vesting, ) = auctioneer
                .getMarketInfoForPurchase(id_);

            // Fees are paid in payout token, unless the quote token is designated
            // as a preferred fee token when the market is created.
            feeInQuote = preferredFeeToken[quoteToken];

            // Auctioneer handles bond pricing, capacity, and duration
            // Fee information needs to be passed to the auctioneer to correctly account
            // for fees in the market capacity adjustments
            (payout, feeAmount) = auctioneer.purchaseBond(
                id_,
                amount_,
                minAmountOut_,
                feeInQuote,
                feeTiers[partnerFeeTier[owner]]
            );
        }

        // Allocate fee to protocol
        fees[(feeInQuote ? quoteToken : payoutToken)] += feeAmount;

        // Ensure enough payout tokens are available
        _handleTransfers(id_, amount_, payout, feeInQuote, feeAmount);

        // Handle payout to user (either transfer tokens if instant swap or issue bond token)
        uint48 expiry = _handlePayout(recipient_, payout, payoutToken, vesting);

        emit Bonded(id_, amount_, payout);

        return (payout, expiry);
    }

    /// @notice     Handles transfer of funds from user and market owner/callback
    function _handleTransfers(
        uint256 id_,
        uint256 amount_,
        uint256 payout_,
        bool feeInQuote_,
        uint256 feePaid_
    ) internal {
        // Get info from auctioneer
        (
            address owner,
            address callbackAddr,
            ERC20 payoutToken,
            ERC20 quoteToken,
            ,

        ) = _aggregator.getAuctioneer(id_).getMarketInfoForPurchase(id_);

        // Calculate amounts net of fees
        uint256 totalPaid = payout_ + (feeInQuote_ ? 0 : feePaid_);
        uint256 amount = amount_ - (feeInQuote_ ? feePaid_ : 0);

        // Have to transfer to teller first if fee in quote token
        // Check balance before and after to ensure full amount received, revert if not
        // Handles edge cases like fee-on-transfer tokens (which are not supported)
        uint256 quoteBalance = quoteToken.balanceOf(address(this));
        quoteToken.safeTransferFrom(msg.sender, address(this), amount_);
        if (quoteToken.balanceOf(address(this)) < quoteBalance + amount_)
            revert Teller_UnsupportedToken();

        // If callback address supplied, transfer tokens from user to callback, then execute callback function,
        // and ensure proper amount of tokens transferred in.
        if (callbackAddr != address(0)) {
            // Send quote token to callback transferred in first to allow use during callback
            // Note to auditor: Please verify these transfers cannot be manipulated
            quoteToken.safeTransfer(callbackAddr, amount);

            // Call the callback function to receive payout tokens for payout
            uint256 payoutBalance = payoutToken.balanceOf(address(this));
            IBondCallback(callbackAddr).callback(id_, amount, totalPaid);

            if (
                payoutToken.balanceOf(address(this)) <
                (payoutBalance + totalPaid)
            ) revert Teller_InvalidCallback();
        } else {
            // If no callback is provided, transfer tokens from market owner to this contract
            // for payout.
            // Check balance before and after to ensure full amount received, revert if not
            // Handles edge cases like fee-on-transfer tokens (which are not supported)
            uint256 payoutBalance = payoutToken.balanceOf(address(this));
            payoutToken.safeTransferFrom(owner, address(this), totalPaid);
            if (
                payoutToken.balanceOf(address(this)) <
                (payoutBalance + totalPaid)
            ) revert Teller_UnsupportedToken();

            quoteToken.safeTransfer(owner, amount);
        }
    }

    /// @notice             Handle payout to recipient
    /// @dev                Implementation-agnostic. Must be implemented in contracts that
    ///                     extend this base since it is called by purchase.
    /// @param recipient_   Address to receive payout
    /// @param payout_      Amount of payoutToken to be paid
    /// @param underlying_   Token to be paid out
    /// @param vesting_     Time parameter for when the payout is available, could be a
    ///                     timestamp or duration depending on the implementation
    /// @return expiry      Timestamp when the payout will vest
    function _handlePayout(
        address recipient_,
        uint256 payout_,
        ERC20 underlying_,
        uint48 vesting_
    ) internal virtual returns (uint48 expiry);

    /// @notice             Derive name and symbol of token for market
    /// @param underlying_   Underlying token to be paid out when the Bond Token vests
    /// @param expiry_      Timestamp that the Bond Token vests at
    /// @return name        Bond token name, format is "Token DD-MM-YY"
    /// @return symbol      Bond token symbol, format is "TKN-DDMMYY"
    function _getNameAndSymbol(ERC20 underlying_, uint256 expiry_)
        internal
        view
        returns (string memory name, string memory symbol)
    {
        // Convert a number of days into a human-readable date, courtesy of BokkyPooBah.
        // Source: https://github.com/bokkypoobah/BokkyPooBahsDateTimeLibrary/blob/master/contracts/BokkyPooBahsDateTimeLibrary.sol

        uint256 year;
        uint256 month;
        uint256 day;
        {
            int256 __days = int256(expiry_ / 1 days);

            int256 num1 = __days + 68569 + 2440588; // 2440588 = OFFSET19700101
            int256 num2 = (4 * num1) / 146097;
            num1 = num1 - (146097 * num2 + 3) / 4;
            int256 _year = (4000 * (num1 + 1)) / 1461001;
            num1 = num1 - (1461 * _year) / 4 + 31;
            int256 _month = (80 * num1) / 2447;
            int256 _day = num1 - (2447 * _month) / 80;
            num1 = _month / 11;
            _month = _month + 2 - 12 * num1;
            _year = 100 * (num2 - 49) + _year + num1;

            year = uint256(_year);
            month = uint256(_month);
            day = uint256(_day);
        }

        string memory yearStr = _uint2str(year % 100);
        string memory monthStr = month < 10
            ? string(abi.encodePacked("0", _uint2str(month)))
            : _uint2str(month);
        string memory dayStr = day < 10
            ? string(abi.encodePacked("0", _uint2str(day)))
            : _uint2str(day);

        // Construct name/symbol strings.
        name = string(
            abi.encodePacked(
                underlying_.name(),
                " ",
                dayStr,
                "-",
                monthStr,
                "-",
                yearStr
            )
        );
        symbol = string(
            abi.encodePacked(
                underlying_.symbol(),
                "-",
                dayStr,
                monthStr,
                yearStr
            )
        );
    }

    // Some fancy math to convert a uint into a string, courtesy of Provable Things.
    // Updated to work with solc 0.8.0.
    // https://github.com/provable-things/ethereum-api/blob/master/provableAPI_0.6.sol
    function _uint2str(uint256 _i) internal pure returns (string memory) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_i - (_i / 10) * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }
}
