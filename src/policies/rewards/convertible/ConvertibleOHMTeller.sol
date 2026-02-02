// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.30;

// Based on Bond Protocol's `FixedStrikeOptionTeller`:
// `https://github.com/Bond-Protocol/option-contracts/blob/b8ce2ca2bae3bd06f0e7665c3aa8d827e4d8ca2c/src/fixed-strike/FixedStrikeOptionTeller.sol`

import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";
import {ClonesWithImmutableArgs} from "src/policies/rewards/convertible/lib/clones/ClonesWithImmutableArgs.sol";
import {ReentrancyGuardTransient} from "@openzeppelin-5.3.0/utils/ReentrancyGuardTransient.sol";

import {IConvertibleOHMTeller} from "src/policies/rewards/convertible/interfaces/IConvertibleOHMTeller.sol";
import {ConvertibleOHMToken} from "src/policies/rewards/convertible/ConvertibleOHMToken.sol";

import {TransferHelper} from "src/libraries/TransferHelper.sol";
import {FullMath} from "src/libraries/FullMath.sol";

// Bophades
import {Kernel, Keycode, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";

contract ConvertibleOHMTeller is
    IConvertibleOHMTeller,
    Policy,
    PolicyEnabler,
    ReentrancyGuardTransient
{
    using TransferHelper for ERC20;
    using FullMath for uint256;
    using ClonesWithImmutableArgs for address;

    // ========== CONSTANTS & IMMUTABLES ========== //

    /// @notice The role for configuration
    bytes32 public constant ROLE_TELLER_ADMIN = "convertible_admin";

    /// @notice The OHM token precision
    uint256 private constant _OHM_PRECISION = 1e9;

    /// @notice The OHM token decimals
    uint8 private constant _OHM_DECIMALS = 9;

    /// @notice The reference implementation of `ConvertibleOHMToken`, deployed upon creation for cloning
    address public immutable TOKEN_IMPLEMENTATION;

    /// @notice The OHM token (the payout token)
    ERC20 public immutable OHM;

    // ========== STATE VARIABLES ========== //

    /// @notice Convertible tokens (hash of parameters to address)
    mapping(bytes32 token_ => ConvertibleOHMToken) public tokens;

    /// @notice The minter module for minting OHM
    MINTRv1 public MINTR;

    /// @notice The treasury module for receiving quote tokens
    TRSRYv1 public TRSRY;

    /// @inheritdoc IConvertibleOHMTeller
    address public override rewardDistributor;

    /// @inheritdoc IConvertibleOHMTeller
    uint48 public override minDuration;

    // ========== CONSTRUCTOR ========== //

    /// @param kernel_ The address of the Olympus kernel
    /// @param ohm_ The address of the OHM token
    constructor(address kernel_, address ohm_) Policy(Kernel(kernel_)) {
        _requireNonzeroAddress(0, kernel_);
        _requireNonzeroAddress(1, ohm_);

        // Deploy the token implementation for cloning (deployments)
        TOKEN_IMPLEMENTATION = address(new ConvertibleOHMToken());

        OHM = ERC20(ohm_);
        if (OHM.decimals() != _OHM_DECIMALS) revert Teller_InvalidParams(1, abi.encodePacked(ohm_));

        // Set the minimum duration during which a convertible token must be eligible for exercise to 1 day initially
        minDuration = uint48(1 days);
    }

    // ========== POLICY CONFIGURATION ========== //

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](3);
        dependencies[0] = toKeycode("ROLES");
        dependencies[1] = toKeycode("MINTR");
        dependencies[2] = toKeycode("TRSRY");

        ROLES = ROLESv1(getModuleAddress(dependencies[0]));
        MINTR = MINTRv1(getModuleAddress(dependencies[1]));
        TRSRY = TRSRYv1(getModuleAddress(dependencies[2]));
        return dependencies;
    }

    /// @inheritdoc Policy
    function requestPermissions()
        external
        view
        override
        returns (Permissions[] memory permissions)
    {
        permissions = new Permissions[](1);
        permissions[0] = Permissions(toKeycode("MINTR"), MINTR.mintOhm.selector);
        return permissions;
    }

    /// @notice Returns the version of this policy
    function VERSION() external pure returns (uint8 major, uint8 minor) {
        return (1, 0);
    }

    // ========== TOKEN DEPLOYMENTS ========== //

    /// @inheritdoc IConvertibleOHMTeller
    function deploy(
        address quoteToken_,
        uint48 eligible_,
        uint48 expiry_,
        uint256 strikePrice_
    ) external override onlyEnabled nonReentrant returns (address) {
        _requireRewardDistributor();

        // If eligible is zero, use the current timestamp
        if (eligible_ == 0) eligible_ = uint48(block.timestamp);

        // Note: Convertible tokens are only unique to a day, not a specific timestamp
        (eligible_, expiry_) = _truncateBothToUTCDay(eligible_, expiry_);

        // Revert if eligible is in the past, we do this to avoid duplicates tokens with the same parameters otherwise
        // Truncate block.timestamp to the nearest day for comparison
        if (eligible_ < _truncateToUTCDay(uint48(block.timestamp)))
            revert Teller_InvalidParams(1, abi.encodePacked(eligible_));

        // Revert if the difference between eligible and expiry is less than min duration or eligible is after expiry
        // Don't need to check expiry against current timestamp since eligible is already checked
        if (eligible_ > expiry_ || expiry_ - eligible_ < minDuration)
            revert Teller_InvalidParams(2, abi.encodePacked(expiry_));

        // Revert if the quote token address is the zero address or does not have a bytecode
        if (quoteToken_ == address(0) || quoteToken_.code.length == 0)
            revert Teller_InvalidParams(0, abi.encodePacked(quoteToken_));

        // Revert if strike price is zero or out of bounds
        uint8 quoteDecimals = ERC20(quoteToken_).decimals();
        int8 priceDecimals = _getPriceDecimals(strikePrice_, quoteDecimals);
        // We check that the strike price is not zero and that the price decimals are not less than
        // half the quote decimals to avoid precision loss
        // For 18 decimal tokens, this means relative prices as low as 1e-9 are supported
        if (strikePrice_ == 0 || priceDecimals < -int8(quoteDecimals / 2))
            revert Teller_InvalidParams(3, abi.encodePacked(strikePrice_));

        // Create the token if one doesn't already exist
        // Timestamps are truncated above to give canonical version of hash
        bytes32 tokenHash = _getTokenHash(ERC20(quoteToken_), eligible_, expiry_, strikePrice_);
        ConvertibleOHMToken token = tokens[tokenHash];

        // If the token doesn't exist, deploy (clone) it
        if (address(token) == address(0)) {
            // Generate name and symbol
            (bytes32 name, bytes32 symbol) = _getNameAndSymbol(
                ERC20(quoteToken_),
                expiry_,
                strikePrice_
            );

            // Deploy (clone) the token with immutable args
            token = ConvertibleOHMToken(
                TOKEN_IMPLEMENTATION.clone(
                    abi.encodePacked(
                        name, // 0x00: bytes32
                        symbol, // 0x20: bytes32
                        _OHM_DECIMALS, // 0x40: uint8
                        quoteToken_, // 0x41: address
                        eligible_, // 0x55: uint48
                        expiry_, // 0x5b: uint48
                        address(this), // 0x61: address
                        strikePrice_ // 0x75: uint256
                    )
                )
            );

            // Set the domain separator for the token on creation to save gas on permit approvals
            token.updateDomainSeparator();

            // Store token
            tokens[tokenHash] = token;

            emit ConvertibleTokenCreated(
                address(token),
                quoteToken_,
                eligible_,
                expiry_,
                strikePrice_
            );
        }
        return address(token);
    }

    // ========== TOKEN MINTING ========== //

    /// @inheritdoc IConvertibleOHMTeller
    function create(
        address token_,
        address to_,
        uint256 amount_
    ) external override onlyEnabled nonReentrant {
        _requireRewardDistributor();
        _requireNonzeroAddress(1, to_);
        _requireNonzeroAmount(2, amount_);
        (ConvertibleOHMToken token, , , uint48 expiry, ) = _requireExistingToken(token_);
        if (expiry <= uint48(block.timestamp)) revert Teller_TokenExpired(expiry);

        token.mint(to_, amount_);
        emit ConvertibleTokenMinted(token_, to_, amount_);
    }

    // ========== TOKEN EXERCISE ========== //

    /// @inheritdoc IConvertibleOHMTeller
    function exercise(address token_, uint256 amount_) external override onlyEnabled nonReentrant {
        _requireNonzeroAmount(1, amount_);
        (
            ConvertibleOHMToken token,
            ERC20 quoteToken,
            uint48 eligible,
            uint48 expiry,
            uint256 price
        ) = _requireExistingToken(token_);
        // Validate that the convertible token is eligible to be exercised
        if (uint48(block.timestamp) < eligible) revert Teller_NotEligible(eligible);
        // Validate that the convertible token is not expired
        if (uint48(block.timestamp) >= expiry) revert Teller_TokenExpired(expiry);

        // Calculate amount of quote tokens equivalent to amount at price
        uint256 quoteAmount = amount_.mulDivUp(price, _OHM_PRECISION);

        // Transfer in quote tokens equivalent to the amount of convertible tokens being exercised * price
        // Transfer proceeds from user
        // Check balances before and after transfer to ensure that the correct amount was transferred
        // @audit this does enable potential malicious convertible tokens that can't be exercised
        // However, we view it as a "buyer beware" situation that can handled on the front-end
        quoteToken.safeTransferFrom(msg.sender, address(TRSRY), quoteAmount);

        // Burn convertible tokens
        token.burn(msg.sender, amount_);

        // Mint OHM to user
        MINTR.mintOhm(msg.sender, amount_);

        emit ConvertibleTokenExercised(address(token), msg.sender, amount_, quoteAmount);
    }

    // ========== VIEW FUNCTIONS ========== //

    /// @inheritdoc IConvertibleOHMTeller
    function exerciseCost(
        address token_,
        uint256 amount_
    ) external view override returns (address, uint256) {
        _requireNonzeroAmount(1, amount_);
        (, ERC20 quoteToken, , , uint256 strikePrice) = _requireExistingToken(token_);

        // Calculate and return the amount of quote tokens required to exercise
        return (address(quoteToken), amount_.mulDivUp(strikePrice, _OHM_PRECISION));
    }

    /// @inheritdoc IConvertibleOHMTeller
    function getToken(
        address quoteToken_,
        uint48 eligible_,
        uint48 expiry_,
        uint256 strikePrice_
    ) public view override returns (address) {
        (eligible_, expiry_) = _truncateBothToUTCDay(eligible_, expiry_);

        // Calculate a hash from the normalized inputs
        bytes32 tokenHash = _getTokenHash(ERC20(quoteToken_), eligible_, expiry_, strikePrice_);
        ConvertibleOHMToken token = tokens[tokenHash];

        // Revert if the convertible token does not exist
        if (address(token) == address(0)) revert Teller_TokenDoesNotExist(tokenHash);

        return address(token);
    }

    /// @inheritdoc IConvertibleOHMTeller
    function getTokenHash(
        address quoteToken_,
        uint48 eligible_,
        uint48 expiry_,
        uint256 strikePrice_
    ) external pure override returns (bytes32) {
        (eligible_, expiry_) = _truncateBothToUTCDay(eligible_, expiry_);
        return _getTokenHash(ERC20(quoteToken_), eligible_, expiry_, strikePrice_);
    }

    // ========== INTERNAL FUNCTIONS ========== //

    function _requireRewardDistributor() internal view {
        if (msg.sender != address(rewardDistributor)) revert Teller_OnlyRewardDistributor();
    }

    function _requireExistingToken(
        address token_
    ) internal view returns (ConvertibleOHMToken, ERC20, uint48, uint48, uint256) {
        // Load token parameters
        (
            ERC20 quoteToken,
            uint48 eligible,
            uint48 expiry,
            uint256 strikePrice
        ) = ConvertibleOHMToken(token_).parameters();

        // Retrieve the internally stored convertible token with this configuration
        // Reverts internally if token doesn't exist
        ConvertibleOHMToken token = ConvertibleOHMToken(
            getToken(address(quoteToken), eligible, expiry, strikePrice)
        );

        // Revert if provided token address does not match stored token address
        if (token_ != address(token)) revert Teller_UnsupportedToken(token_);

        return (token, quoteToken, eligible, expiry, strikePrice);
    }

    // TODO: optimize this algorithm and packing.
    // TODO: update comments.
    /// @notice Derive name and symbol of the token
    function _getNameAndSymbol(
        ERC20 quoteToken_,
        uint256 expiry_,
        uint256 strikePrice_
    ) internal view returns (bytes32, bytes32) {
        // Examples
        // WETH call option expiring on 2100-01-01 with strike price of 10_010.50 DAI would be formatted as:
        // Name: "WETH/DAI C 1.001e+4 2100-01-01"
        // Symbol: "oWETH-21000101"
        //
        // WETH put option expiring on 2100-01-01 with strike price of 10.546 DAI would be formatted as:
        // Name: "WETH/DAI P 1.054e+1 2100-01-01"
        // Symbol: "oWETH-21000101"
        //
        // Note: Names are more specific than symbols, but none are guaranteed to be completely unique to
        // a specific oToken.
        // To ensure uniqueness, the convertible token address and hash identifier should be used.

        // Get the date format from the expiry timestamp.
        // Convert a number of days into a human-readable date, courtesy of BokkyPooBah.
        // Source: https://github.com/bokkypoobah/BokkyPooBahsDateTimeLibrary/blob/master/contracts/BokkyPooBahsDateTimeLibrary.sol
        string memory yearStr;
        string memory monthStr;
        string memory dayStr;
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

            yearStr = _uint2str(uint256(_year) % 10000);
            monthStr = uint256(_month) < 10
                ? string(abi.encodePacked("0", _uint2str(uint256(_month))))
                : _uint2str(uint256(_month));
            dayStr = uint256(_day) < 10
                ? string(abi.encodePacked("0", _uint2str(uint256(_day))))
                : _uint2str(uint256(_day));
        }

        // Format token symbols
        // Symbols longer than 5 characters are truncated, min length would be 1 if tokens have no symbols,
        // max length is 11
        bytes memory tokenSymbols;
        {
            bytes memory quoteSymbol = bytes(quoteToken_.symbol());
            if (quoteSymbol.length > 5) quoteSymbol = abi.encodePacked(bytes5(quoteSymbol));

            // TODO: confirm that this format is right.
            tokenSymbols = abi.encodePacked("OHM/", quoteSymbol);
        }

        // Format strike price
        // Strike price is formatted as scientific notation to 3 significant figures
        // Will either be 8 or 9 bytes, e.g. 1.056e+1 (8) or 9.745e-12 (9)
        bytes memory strike = _getScientificNotation(strikePrice_, quoteToken_.decimals());

        // Construct name/symbol strings.

        // Name and symbol can each be at most 32 bytes since it is stored as a bytes32
        // Name is formatted as "payoutSymbol/quoteSymbol callPut strikePrice expiry" with the following constraints:
        // payoutSymbol - 5 bytes
        // "/" - 1 byte
        // quoteSymbol - 5 bytes
        // " " - 1 byte
        // callPut - 1 byte
        // " " - 1 byte
        // strikePrice - 8 or 9 bytes, scientific notation to 3 significant figures, e.g. 1.056e+1 (8) or 9.745e-12 (9)
        // " " - 1 byte
        // expiry - 8 bytes, YYYYMMDD
        // Total is 31 or 32 bytes

        // Symbol is formatted as "oPayoutSymbol-expiry" with the following constraints:
        // "o" - 1 byte
        // payoutSymbol - 5 bytes
        // "-" - 1 byte
        // expiry - 8 bytes, YYYYMMDD
        // Total is 15 bytes

        bytes32 name = bytes32(
            abi.encodePacked(tokenSymbols, " ", strike, " ", yearStr, monthStr, dayStr)
        );
        // TODO: decide what prefix should be used.
        bytes32 symbol = bytes32(abi.encodePacked("cOHM-", yearStr, monthStr, dayStr));

        return (name, symbol);
    }

    /// @notice Helper function to calculate number of price decimals in the provided price
    /// @param price_   The price to calculate the number of decimals for
    /// @return         The number of decimals
    function _getPriceDecimals(uint256 price_, uint8 tokenDecimals_) internal pure returns (int8) {
        int8 decimals;
        while (price_ >= 10) {
            price_ = price_ / 10;
            decimals++;
        }

        // Subtract the stated decimals from the calculated decimals to get the relative price decimals.
        // Required to do it this way vs. normalizing at the beginning since price decimals can be negative.
        return decimals - int8(tokenDecimals_);
    }

    /// @notice Helper function to format a uint256 into scientific notation with 3 significant figures
    /// @param price_           The price to format
    /// @param tokenDecimals_   The number of decimals in the token
    function _getScientificNotation(
        uint256 price_,
        uint8 tokenDecimals_
    ) internal pure returns (bytes memory) {
        // Get a bytes representation of the price in scientific notation with 3 significant figures.
        // 1. Get the number of price decimals
        int8 priceDecimals = _getPriceDecimals(price_, tokenDecimals_);

        // Scientific notation can support up to 2 digit exponents (i.e. price decimals)
        // The bounds for valid prices have been checked earlier when the token was deployed
        // so we don't have to check again here.

        // 2. Get a string of the price decimals and exponent figure
        bytes memory decStr;
        if (priceDecimals < 0) {
            uint256 decimals = uint256(uint8(-priceDecimals));
            decStr = bytes.concat("e-", bytes(_uint2str(decimals)));
        } else {
            uint256 decimals = uint256(uint8(priceDecimals));
            decStr = bytes.concat("e+", bytes(_uint2str(decimals)));
        }

        // 3. Get a string of the leading digits with decimal point
        uint8 priceMagnitude = uint8(int8(tokenDecimals_) + priceDecimals);
        uint256 digits = price_ / (10 ** (priceMagnitude < 3 ? 0 : priceMagnitude - 3));
        bytes memory digitStr = bytes(_uint2str(digits));
        uint256 len = bytes(digitStr).length;
        bytes memory leadingStr = bytes.concat(digitStr[0], ".");
        for (uint256 i = 1; i < len; ++i) {
            leadingStr = bytes.concat(leadingStr, digitStr[i]);
        }

        // 4. Combine and return
        // The bytes string should be at most 9 bytes (e.g. 1.056e-10)
        return bytes.concat(leadingStr, decStr);
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

    function _getTokenHash(
        ERC20 quoteToken_,
        uint48 eligible_,
        uint48 expiry_,
        uint256 strikePrice_
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(quoteToken_, eligible_, expiry_, strikePrice_));
    }

    // Truncates the timestamp to the nearest day at 0000 UTC (in seconds).
    function _truncateToUTCDay(uint48 timestamp) internal pure returns (uint48) {
        return uint48(timestamp / 1 days) * 1 days;
    }

    function _truncateBothToUTCDay(
        uint48 eligible_,
        uint48 expiry_
    ) private pure returns (uint48, uint48) {
        // Eligible and Expiry are rounded to the nearest day at 0000 UTC (in seconds) since
        // convertible tokens are only unique to a day, not a specific timestamp.
        return (_truncateToUTCDay(eligible_), _truncateToUTCDay(expiry_));
    }

    function _requireNonzeroAmount(uint256 index, uint256 a) private pure {
        if (a == 0) revert Teller_InvalidParams(index, abi.encodePacked(a));
    }

    function _requireNonzeroAddress(uint256 index, address a) private pure {
        if (a == address(0)) revert Teller_InvalidParams(index, abi.encodePacked(a));
    }

    // ========== ADMIN CONFIG ========== //

    /// @inheritdoc IConvertibleOHMTeller
    function setRewardDistributor(
        address rewardDistributor_
    ) external override onlyEnabled onlyRole(ROLE_TELLER_ADMIN) {
        _requireNonzeroAddress(0, rewardDistributor_);
        rewardDistributor = rewardDistributor_;
        emit RewardDistributorSet(rewardDistributor_);
    }

    /// @inheritdoc IConvertibleOHMTeller
    function setMinDuration(
        uint48 duration_
    ) external override onlyEnabled onlyRole(ROLE_TELLER_ADMIN) {
        // Must be a minimum of 1 day due to rounding of eligible and expiry timestamps
        if (duration_ < uint48(1 days)) revert Teller_InvalidParams(0, abi.encodePacked(duration_));
        minDuration = duration_;
    }
}
