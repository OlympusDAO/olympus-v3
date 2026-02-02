// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.30;

// Based on Bond Protocol's `FixedStrikeOptionTeller`:
// `https://github.com/Bond-Protocol/option-contracts/blob/b8ce2ca2bae3bd06f0e7665c3aa8d827e4d8ca2c/src/fixed-strike/FixedStrikeOptionTeller.sol`

import {FullMath} from "src/libraries/FullMath.sol";
import {Timestamp} from "src/libraries/Timestamp.sol";
import {uint2str} from "src/libraries/Uint2Str.sol";
import {IConvertibleOHMTeller} from "src/policies/rewards/convertible/interfaces/IConvertibleOHMTeller.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {ClonesWithImmutableArgs} from "@clones-with-immutable-args-1.1.2/ClonesWithImmutableArgs.sol";
import {ConvertibleOHMToken} from "src/policies/rewards/convertible/ConvertibleOHMToken.sol";
import {IERC20} from "@openzeppelin-5.3.0/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin-5.3.0/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin-5.3.0/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardTransient} from "@openzeppelin-5.3.0/utils/ReentrancyGuardTransient.sol";

// Bophades
import {Kernel, Keycode, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";

contract ConvertibleOHMTeller is
    IConvertibleOHMTeller,
    IVersioned,
    Policy,
    PolicyEnabler,
    ReentrancyGuardTransient
{
    using SafeERC20 for IERC20;
    using FullMath for uint256;
    using ClonesWithImmutableArgs for address;

    // ========== CONSTANTS & IMMUTABLES ========== //

    /// @notice The role for configuration
    bytes32 public constant ROLE_TELLER_ADMIN = "convertible_admin";

    /// @notice The role for reward distribution (deploying and minting convertible tokens)
    bytes32 public constant ROLE_REWARD_DISTRIBUTOR = "convertible_distributor";

    /// @notice The OHM token precision
    uint256 private constant _OHM_PRECISION = 1e9;

    /// @notice The OHM token decimals
    uint8 private constant _OHM_DECIMALS = 9;

    /// @notice The reference implementation of `ConvertibleOHMToken`, deployed upon creation for cloning
    address public immutable TOKEN_IMPLEMENTATION;

    /// @notice The OHM token (the payout token)
    address public immutable OHM;

    // ========== STATE VARIABLES ========== //

    /// @notice Convertible tokens (hash of parameters to address)
    mapping(bytes32 token_ => address) public tokens;

    /// @notice The minter module for minting OHM
    MINTRv1 public MINTR;

    /// @notice The treasury module for receiving quote tokens
    TRSRYv1 public TRSRY;

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

        OHM = ohm_;
        if (IERC20Metadata(ohm_).decimals() != _OHM_DECIMALS)
            revert Teller_InvalidParams(1, abi.encodePacked(ohm_));

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
        Keycode kc = toKeycode("MINTR");
        permissions = new Permissions[](3);
        permissions[0] = Permissions({keycode: kc, funcSelector: MINTR.mintOhm.selector});
        permissions[1] = Permissions({
            keycode: kc,
            funcSelector: MINTR.increaseMintApproval.selector
        });
        permissions[2] = Permissions({
            keycode: kc,
            funcSelector: MINTR.decreaseMintApproval.selector
        });
        return permissions;
    }

    /// @notice Returns the version of this policy
    function VERSION() external pure returns (uint8 major, uint8 minor) {
        return (1, 0);
    }

    /// @notice Overrides _enable to accept initial minting cap
    /// @param enableData_ ABI-encoded (uint256 mintCap)
    function _enable(bytes calldata enableData_) internal override {
        if (enableData_.length != 0) {
            uint256 mintCap = abi.decode(enableData_, (uint256));
            _setMintCap(mintCap);
        }
    }

    // ========== TOKEN DEPLOYMENTS ========== //

    /// @inheritdoc IConvertibleOHMTeller
    function deploy(
        address quoteToken_,
        uint48 eligible_,
        uint48 expiry_,
        uint256 strikePrice_
    )
        external
        override
        onlyEnabled
        onlyRole(ROLE_REWARD_DISTRIBUTOR)
        nonReentrant
        returns (address)
    {
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
        uint8 quoteDecimals = IERC20Metadata(quoteToken_).decimals();
        int8 priceDecimals = _getPriceDecimals(strikePrice_, quoteDecimals);
        // We check that the strike price is not zero and that the price decimals are not less than
        // half the quote decimals to avoid precision loss
        // For 18 decimal tokens, this means relative prices as low as 1e-9 are supported
        if (strikePrice_ == 0 || priceDecimals < -int8(quoteDecimals / 2))
            revert Teller_InvalidParams(3, abi.encodePacked(strikePrice_));

        // Create the token if one doesn't already exist
        return _getOrDeployToken(quoteToken_, msg.sender, eligible_, expiry_, strikePrice_);
    }

    // ========== TOKEN MINTING ========== //

    /// @inheritdoc IConvertibleOHMTeller
    function create(
        address token_,
        address to_,
        uint256 amount_
    ) external override onlyEnabled onlyRole(ROLE_REWARD_DISTRIBUTOR) nonReentrant {
        _requireNonzeroAddress(1, to_);
        _requireNonzeroAmount(2, amount_);
        (ConvertibleOHMToken token, , address creator, , uint48 expiry, ) = _requireExistingToken(
            token_
        );
        if (expiry <= uint48(block.timestamp)) revert Teller_TokenExpired(expiry);
        // Only the creator (RewardDistributor) that deployed this token can mint more
        if (msg.sender != creator) revert Teller_NotTokenCreator(msg.sender, creator);

        token.mintFor(to_, amount_);
        emit ConvertibleTokenMinted(token_, to_, amount_);
    }

    // ========== TOKEN EXERCISE ========== //

    /// @inheritdoc IConvertibleOHMTeller
    function exercise(address token_, uint256 amount_) external override onlyEnabled nonReentrant {
        _requireNonzeroAmount(1, amount_);
        (
            ConvertibleOHMToken token,
            address quoteToken,
            ,
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

        // Burn convertible tokens
        token.burnFrom(msg.sender, amount_);

        // Mint OHM to user
        MINTR.mintOhm(msg.sender, amount_);

        // Transfer quote tokens from user
        // @audit this does enable potential malicious convertible tokens that can't be exercised
        // However, we view it as a "buyer beware" situation that can handled on the front-end
        IERC20(quoteToken).safeTransferFrom(msg.sender, address(TRSRY), quoteAmount);

        emit ConvertibleTokenExercised(address(token), msg.sender, amount_, quoteAmount);
    }

    // ========== VIEW FUNCTIONS ========== //

    /// @inheritdoc IConvertibleOHMTeller
    function exerciseCost(
        address token_,
        uint256 amount_
    ) external view override returns (address, uint256) {
        _requireNonzeroAmount(1, amount_);
        (, address quoteToken, , , , uint256 strikePrice) = _requireExistingToken(token_);

        // Calculate and return the amount of quote tokens required to exercise
        return (quoteToken, amount_.mulDivUp(strikePrice, _OHM_PRECISION));
    }

    /// @inheritdoc IConvertibleOHMTeller
    function remainingMintApproval() external view override returns (uint256 remaining_) {
        return MINTR.mintApproval(address(this));
    }

    /// @inheritdoc IConvertibleOHMTeller
    function getTokenHash(
        address quoteToken_,
        address creator_,
        uint48 eligible_,
        uint48 expiry_,
        uint256 strikePrice_
    ) external pure override returns (bytes32) {
        (eligible_, expiry_) = _truncateBothToUTCDay(eligible_, expiry_);
        return _getTokenHash(quoteToken_, creator_, eligible_, expiry_, strikePrice_);
    }

    /// @inheritdoc IConvertibleOHMTeller
    function getToken(
        address quoteToken_,
        address creator_,
        uint48 eligible_,
        uint48 expiry_,
        uint256 strikePrice_
    ) public view override returns (address) {
        (eligible_, expiry_) = _truncateBothToUTCDay(eligible_, expiry_);

        // Calculate a hash from the normalized inputs
        bytes32 tokenHash = _getTokenHash(quoteToken_, creator_, eligible_, expiry_, strikePrice_);
        address token = tokens[tokenHash];

        // Revert if the convertible token does not exist
        if (token == address(0)) revert Teller_TokenDoesNotExist(tokenHash);

        return token;
    }

    // ========== INTERNAL FUNCTIONS ========== //

    /// @notice Sets the minting cap by adjusting MINTR approval
    /// @param cap_ The target minting cap (in OHM units)
    function _setMintCap(uint256 cap_) internal {
        uint256 currentApproval = MINTR.mintApproval(address(this));
        unchecked {
            if (cap_ > currentApproval) {
                MINTR.increaseMintApproval(address(this), cap_ - currentApproval);
            } else if (cap_ < currentApproval) {
                MINTR.decreaseMintApproval(address(this), currentApproval - cap_);
            }
        }
        emit MintCapUpdated(cap_, currentApproval);
    }

    function _getOrDeployToken(
        address quoteToken_,
        address creator_,
        uint48 eligible_,
        uint48 expiry_,
        uint256 strikePrice_
    ) private returns (address) {
        // Warning. The timestamps should be truncated above to give canonical version of hash
        bytes32 tokenHash = _getTokenHash(quoteToken_, creator_, eligible_, expiry_, strikePrice_);
        address token = tokens[tokenHash];

        // If the token doesn't exist, deploy (clone) it
        if (address(token) == address(0)) {
            token = _deployToken(quoteToken_, creator_, eligible_, expiry_, strikePrice_);
            tokens[tokenHash] = token;
            emit ConvertibleTokenCreated(
                token,
                quoteToken_,
                creator_,
                eligible_,
                expiry_,
                strikePrice_
            );
        }
        return token;
    }

    function _deployToken(
        address quoteToken_,
        address creator_,
        uint48 eligible_,
        uint48 expiry_,
        uint256 strikePrice_
    ) private returns (address token) {
        // Generate name and symbol
        (bytes32 name, bytes32 symbol) = _getNameAndSymbol(quoteToken_, expiry_, strikePrice_);

        // Build immutable args for cloning
        bytes memory immutableArgs = abi.encodePacked(
            name, // 0x00: bytes32
            symbol, // 0x20: bytes32
            _OHM_DECIMALS, // 0x40: uint8
            quoteToken_, // 0x41: address
            eligible_, // 0x55: uint48
            expiry_, // 0x5b: uint48
            address(this), // 0x61: address
            creator_, // 0x75: address
            strikePrice_ // 0x89: uint256
        );

        // Deploy (clone) the token with immutable args
        token = TOKEN_IMPLEMENTATION.clone(immutableArgs);

        // Set the domain separator for the token on creation to save gas on permit approvals
        ConvertibleOHMToken(token).updateDomainSeparator();
    }

    function _requireExistingToken(
        address token_
    ) internal view returns (ConvertibleOHMToken, address, address, uint48, uint48, uint256) {
        // Load token parameters
        (
            address quoteToken,
            address creator,
            uint48 eligible,
            uint48 expiry,
            uint256 strikePrice
        ) = ConvertibleOHMToken(token_).parameters();

        // Retrieve the internally stored convertible token with this configuration
        // Reverts internally if token doesn't exist
        ConvertibleOHMToken token = ConvertibleOHMToken(
            getToken(quoteToken, creator, eligible, expiry, strikePrice)
        );

        // Revert if provided token address does not match stored token address
        if (token_ != address(token)) revert Teller_UnsupportedToken(token_);

        return (token, quoteToken, creator, eligible, expiry, strikePrice);
    }

    /// @notice Derives a name and symbol of the convertible token
    /// @dev Examples:
    ///      - Strike 15.50 USDS, expiry 2025-06-01: Name "OHM/USDS 15.5 20250601", Symbol "cOHM-20250601"
    ///      - Strike 150   USDS, expiry 2025-12-31: Name "OHM/USDS 150 20251231",  Symbol "cOHM-20251231"
    function _getNameAndSymbol(
        address quoteToken_,
        uint256 expiry_,
        uint256 strikePrice_
    ) internal view returns (bytes32 name, bytes32 symbol) {
        // Convert the expiry timestamp as YYYYMMDD
        (string memory y, string memory m, string memory d) = Timestamp.toPaddedString(
            uint48(expiry_)
        );
        bytes memory date = abi.encodePacked(y, m, d);

        // Get the quote symbol (truncated to 5 chars max)
        bytes memory quoteSymbol = bytes(IERC20Metadata(quoteToken_).symbol());
        if (quoteSymbol.length > 5) quoteSymbol = abi.encodePacked(bytes5(quoteSymbol));

        // Format the strike price as decimal with up to 2 fractional digits (e.g., "15.00")
        bytes memory price = _formatPrice(strikePrice_, IERC20Metadata(quoteToken_).decimals());

        // Name: "OHM/QUOTE PRICE YYYYMMDD", Symbol: "cOHM-YYYYMMDD"
        name = bytes32(abi.encodePacked("OHM/", quoteSymbol, " ", price, " ", date));
        // TODO: decide what prefix should be used.
        symbol = bytes32(abi.encodePacked("cOHM-", date));
        return (name, symbol);
    }

    /// @notice Formats price as a decimal string with 2 fractional digits
    /// @dev Requires tokenDecimals_ >= 2 to avoid underflow
    /// @param price_ The price in token decimals
    /// @param tokenDecimals_ The number of decimals in the quote token
    /// @return The formatted price as bytes (e.g., "15.00", "15.50", "15.05")
    function _formatPrice(
        uint256 price_,
        uint8 tokenDecimals_
    ) internal pure returns (bytes memory) {
        uint256 wholePart = price_ / (10 ** tokenDecimals_);
        uint256 fracPart = (price_ % (10 ** tokenDecimals_)) / (10 ** (tokenDecimals_ - 2));
        return
            abi.encodePacked(
                uint2str(wholePart),
                ".",
                fracPart < 10 ? "0" : "",
                uint2str(fracPart)
            );
    }

    /// @notice Calculates a number of price decimals in the provided price
    /// @dev Used for validation in deploy() to ensure a strike price has sufficient precision
    /// @param price_ The price to calculate the number of decimals for
    /// @param tokenDecimals_ The number of decimals in the quote token
    /// @return The number of price decimals (can be negative for prices < 1)
    function _getPriceDecimals(uint256 price_, uint8 tokenDecimals_) internal pure returns (int8) {
        int8 decimals;
        while (price_ >= 10) {
            price_ = price_ / 10;
            decimals++;
        }
        return decimals - int8(tokenDecimals_);
    }

    function _getTokenHash(
        address quoteToken_,
        address creator_,
        uint48 eligible_,
        uint48 expiry_,
        uint256 strikePrice_
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(quoteToken_, creator_, eligible_, expiry_, strikePrice_));
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
    function setMinDuration(
        uint48 duration_
    ) external override onlyEnabled onlyRole(ROLE_TELLER_ADMIN) {
        // Must be a minimum of 1 day due to rounding of eligible and expiry timestamps
        if (duration_ < uint48(1 days)) revert Teller_InvalidParams(0, abi.encodePacked(duration_));
        minDuration = duration_;
    }

    /// @inheritdoc IConvertibleOHMTeller
    function setMintCap(uint256 cap_) external override onlyEnabled onlyAdminRole {
        _setMintCap(cap_);
    }

    // ========== IERC165 ========== //

    /// @inheritdoc PolicyEnabler
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(PolicyEnabler) returns (bool) {
        return
            interfaceId == type(IConvertibleOHMTeller).interfaceId ||
            interfaceId == type(IVersioned).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
