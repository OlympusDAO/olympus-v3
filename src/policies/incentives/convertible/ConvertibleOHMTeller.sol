// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.30;

// Based on Bond Protocol's `FixedStrikeOptionTeller`:
// https://github.com/Bond-Protocol/option-contracts/blob/b8ce2ca2bae3bd06f0e7665c3aa8d827e4d8ca2c/src/fixed-strike/FixedStrikeOptionTeller.sol
//
// Key changes from the original:
// - Integrated into the Olympus Kernel-Module-Policy framework with role-based access control.
// - Simplified to OHM-only call options: removed payoutToken, receiver, and call/put parameters.
// - Minting via MINTR module on exercise (no pre-deposited collateral); quote tokens sent to TRSRY.
// - Only the deploying IncentiveDistributor (creator) can mint tokens via create();
//   token hash includes creator to scope tokens per deployer.
// - Removed reclaim(), protocol fees, and collateral tracking.
// - Per-creator mint caps: admin sets the cumulative mint cap per creator,
//   enforced in create() against `creatorMinted`; the cap cannot be lowered below the
//   creator's current `creatorMinted` so admin cannot retroactively shrink the budget.
//   Setting cap == creatorMinted freezes new mints while keeping live tokens exercisable.
//   MINTR approval is adjusted atomically in create/exercise/sweep.
// - Active token registry + permissionless sweep of expired tokens; Heart-driven periodic sweep.
// - Token naming uses decimal notation (e.g., "15.50") with "convOHM-" prefix.
// - burnFrom deducts allowance (original burn did not).
// - Solidity >=0.8.30; OZ SafeERC20/ReentrancyGuardTransient replaces solmate equivalents.
// - CloneERC20 split into CloneERC20 (reused existing) + CloneERC20Permit.

import {FullMath} from "src/libraries/FullMath.sol";
import {Timestamp} from "src/libraries/Timestamp.sol";
import {uint2str} from "src/libraries/Uint2Str.sol";
import {IConvertibleOHMTeller} from "src/policies/incentives/convertible/interfaces/IConvertibleOHMTeller.sol";
import {IPeriodicTask} from "src/interfaces/IPeriodicTask.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {ClonesWithImmutableArgs} from "@clones-with-immutable-args-1.1.2/ClonesWithImmutableArgs.sol";
import {ConvertibleOHMToken} from "src/policies/incentives/convertible/ConvertibleOHMToken.sol";
import {IERC20} from "@openzeppelin-5.3.0/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin-5.3.0/token/ERC20/extensions/IERC20Metadata.sol";
import {EnumerableSet} from "@openzeppelin-5.3.0/utils/structs/EnumerableSet.sol";
import {SafeCast} from "@openzeppelin-5.3.0/utils/math/SafeCast.sol";
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
    IPeriodicTask,
    IVersioned,
    Policy,
    PolicyEnabler,
    ReentrancyGuardTransient
{
    using SafeCast for int256;
    using SafeERC20 for IERC20;
    using FullMath for uint256;
    using ClonesWithImmutableArgs for address;
    using EnumerableSet for EnumerableSet.AddressSet;

    // ========== CONSTANTS & IMMUTABLES ========== //

    /// @notice The role for incentive distribution (deploying and minting convertible tokens)
    bytes32 public constant ROLE_CONVERTIBLE_DISTRIBUTOR = "convertible_distributor";

    /// @notice The role for the heart contract: allowed to call execute() for periodic sweeping of expired tokens.
    bytes32 public constant ROLE_HEART = "heart";

    /// @notice The OHM token precision
    uint256 private constant _OHM_PRECISION = 1e9;

    /// @notice The OHM token decimals
    uint8 private constant _OHM_DECIMALS = 9;

    /// @notice Minimum byte length of enableData_ (abi-encoded `address[] creators, uint256[] caps`).
    /// @dev abi.encode(address[], uint256[]) with empty arrays = 32 (offset 1) + 32 (offset 2) + 32 (len 1) + 32 (len 2) = 128.
    uint256 private constant _MIN_ENABLE_DATA_LENGTH = 128;

    /// @notice Minimum decimals required for quote tokens (used by _formatPrice)
    uint8 private constant _MIN_QUOTE_TOKEN_DECIMALS = 2;

    /// @notice Maximum allowed duration from current time to token expiry (~2 years)
    uint48 private constant _MAX_EXPIRY_HORIZON = 730 days;

    /// @notice Length of one UTC day, used for day-boundary rounding
    uint48 private constant _UTC_DAY = uint48(1 days);

    /// @notice Minimum allowed value for minDuration and minEligibleDelay
    uint48 private constant _MIN_DURATION_FLOOR = _UTC_DAY;

    /// @notice Default iteration limit used by Heart-triggered sweeps.
    uint256 public constant HEART_SWEEP_LIMIT = 50;

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

    /// @inheritdoc IConvertibleOHMTeller
    uint48 public override minEligibleDelay;

    /// @inheritdoc IConvertibleOHMTeller
    mapping(address creator => uint256) public override creatorMintCap;

    /// @inheritdoc IConvertibleOHMTeller
    mapping(address creator => uint256) public override creatorOutstanding;

    /// @inheritdoc IConvertibleOHMTeller
    mapping(address creator => uint256) public override creatorMinted;

    /// @notice Deployed tokens not yet swept (may briefly contain expired tokens until sweeping)
    EnumerableSet.AddressSet private _activeTokens;

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

        // Set the minimum duration and eligible delay to 1 day initially
        _setMinDuration(_MIN_DURATION_FLOOR);
        _setMinEligibleDelay(_MIN_DURATION_FLOOR);
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
    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        return (1, 0);
    }

    /// @notice Enables the teller with initial per-creator mint caps.
    /// @param enableData_ ABI-encoded (address[] creators, uint256[] caps). Arrays may be empty.
    function _enable(bytes calldata enableData_) internal override {
        if (enableData_.length < _MIN_ENABLE_DATA_LENGTH)
            revert Teller_InvalidParams(0, enableData_);

        (address[] memory creators, uint256[] memory caps) = abi.decode(
            enableData_,
            (address[], uint256[])
        );

        uint256 len = creators.length;
        if (len != caps.length) revert Teller_InvalidParams(0, abi.encodePacked(len, caps.length));

        for (uint256 i = 0; i < len; ++i) {
            _setCreatorMintCap(creators[i], caps[i]);
        }
    }

    // ========== TOKEN DEPLOYMENTS ========== //

    /// @inheritdoc IConvertibleOHMTeller
    /// @dev Reverts if:
    ///      - The policy is disabled.
    ///      - The caller has not been granted the convertible distributor role.
    ///      - Called re-entrantly.
    ///      - The eligible timestamp is earlier than the current time plus the minimum eligibility delay
    ///        (after rounding both to UTC midnight).
    ///      - The expiry timestamp is farther in the future than the maximum allowed horizon.
    ///      - The eligible timestamp is after the expiry timestamp.
    ///      - The gap between eligible and expiry is less than the minimum duration.
    ///      - The quote token address is zero or has no bytecode.
    ///      - The quote token has fewer decimals than required for price formatting.
    ///      - The strike price is zero or has insufficient precision relative to the quote token.
    function deploy(
        address quoteToken_,
        uint48 eligible_,
        uint48 expiry_,
        uint256 strikePrice_
    )
        external
        override
        onlyEnabled
        onlyRole(ROLE_CONVERTIBLE_DISTRIBUTOR)
        nonReentrant
        returns (address)
    {
        if (eligible_ == 0) {
            // Ceiling to the earliest UTC midnight >= block.timestamp + minEligibleDelay.
            // Tokens are day-granular, so eligible should land on a midnight boundary.
            uint48 minTimestamp = uint48(block.timestamp) + minEligibleDelay;
            eligible_ = _truncateToUTCDay(minTimestamp + _UTC_DAY - 1);
        }

        // Note: Convertible tokens are only unique to a day, not a specific timestamp
        (eligible_, expiry_) = _truncateBothToUTCDay(eligible_, expiry_);

        // Revert if eligible does not satisfy the minimum delay from the current time
        if (eligible_ < uint48(block.timestamp) + minEligibleDelay)
            revert Teller_InvalidParams(1, abi.encodePacked(eligible_));

        // Revert if expiry exceeds the maximum allowed horizon
        if (expiry_ > uint48(block.timestamp) + _MAX_EXPIRY_HORIZON)
            revert Teller_InvalidParams(2, abi.encodePacked(expiry_));

        // Revert if the difference between eligible and expiry is less than min duration or eligible is after expiry
        // Don't need to check expiry against current timestamp since eligible is already checked
        unchecked {
            if (eligible_ > expiry_ || expiry_ - eligible_ < minDuration)
                revert Teller_InvalidParams(2, abi.encodePacked(expiry_));
        }

        // Revert if the quote token address is the zero address or does not have a bytecode
        if (quoteToken_ == address(0) || quoteToken_.code.length == 0)
            revert Teller_InvalidParams(0, abi.encodePacked(quoteToken_));

        // Revert if the quote token has fewer than _MIN_QUOTE_TOKEN_DECIMALS decimals
        // (required by _formatPrice which computes 10 ** (decimals - 2))
        uint8 quoteDecimals = IERC20Metadata(quoteToken_).decimals();
        if (quoteDecimals < _MIN_QUOTE_TOKEN_DECIMALS)
            revert Teller_InvalidParams(0, abi.encodePacked(quoteToken_));

        // Revert if strike price is zero or out of bounds
        int8 priceDecimals = _getPriceDecimals(strikePrice_, quoteDecimals);
        // Check that the strike price is not zero and that the price decimals are not less than
        // half the quote decimals to avoid precision loss
        // For 18 decimal tokens, this means relative prices as low as 1e-9 are supported
        if (strikePrice_ == 0 || priceDecimals < -int8(quoteDecimals / 2))
            revert Teller_InvalidParams(3, abi.encodePacked(strikePrice_));

        // Resolve the existing token, or deploy a new one if none exists
        return _getOrDeployToken(quoteToken_, msg.sender, eligible_, expiry_, strikePrice_);
    }

    // ========== TOKEN MINTING ========== //

    /// @inheritdoc IConvertibleOHMTeller
    /// @dev Reverts if:
    ///      - The policy is disabled.
    ///      - The caller has not been granted the convertible distributor role.
    ///      - Called re-entrantly.
    ///      - The recipient is the zero address.
    ///      - The amount is zero.
    ///      - The token is not a deployed convertible token.
    ///      - The token has expired.
    ///      - The caller is not the token's creator.
    ///      - Minting this amount would push the creator's cumulative minted above the configured cap.
    function create(
        address token_,
        address to_,
        uint256 amount_
    ) external override onlyEnabled onlyRole(ROLE_CONVERTIBLE_DISTRIBUTOR) nonReentrant {
        _requireNonzeroAddress(1, to_);
        _requireNonzeroAmount(2, amount_);
        (ConvertibleOHMToken token, , address creator, , uint48 expiry, ) = _requireExistingToken(
            token_
        );
        _requireTokenNotExpired(expiry);
        // Only the creator (a distributor) that deployed this token can mint more
        if (msg.sender != creator) revert Teller_NotTokenCreator(msg.sender, creator);

        // Charge the creator's cumulative budget against the configured cap
        uint256 newMinted = creatorMinted[creator] + amount_;
        if (newMinted > creatorMintCap[creator])
            revert Teller_CapExceeded(creator, newMinted, creatorMintCap[creator]);
        creatorMinted[creator] = newMinted;

        // Bump outstanding in lockstep with minted and reserve MINTR approval
        creatorOutstanding[creator] += amount_;
        MINTR.increaseMintApproval(address(this), amount_);

        token.mintFor(to_, amount_);
        emit ConvertibleTokenMinted(token_, to_, amount_);
    }

    // ========== TOKEN EXERCISE ========== //

    /// @inheritdoc IConvertibleOHMTeller
    /// @dev Reverts if:
    ///      - The policy is disabled.
    ///      - Called re-entrantly.
    ///      - The amount is zero.
    ///      - The token is not a deployed convertible token.
    ///      - The current time is before the token's eligible timestamp.
    ///      - The token has expired.
    ///      - The caller does not have enough convertible tokens or allowance.
    ///      - The caller does not have enough quote tokens or allowance.
    ///      - The quote token applies a transfer fee (the treasury receives less than the calculated amount).
    function exercise(address token_, uint256 amount_) external override onlyEnabled nonReentrant {
        _requireNonzeroAmount(1, amount_);
        (
            ConvertibleOHMToken token,
            address quoteToken,
            address creator,
            uint48 eligible,
            uint48 expiry,
            uint256 price
        ) = _requireExistingToken(token_);
        // Validate that the convertible token is eligible to be exercised
        if (uint48(block.timestamp) < eligible) revert Teller_NotEligible(eligible);
        _requireTokenNotExpired(expiry);

        // Release the reserved outstanding and burn convOHM tokens
        creatorOutstanding[creator] -= amount_;
        token.burnFrom(msg.sender, amount_);

        // Mint OHM to user (consumes MINTR approval)
        MINTR.mintOhm(msg.sender, amount_);

        // Calculate amount of quote tokens equivalent to amount at price
        uint256 quoteAmount = amount_.mulDivUp(price, _OHM_PRECISION);

        // Transfer quote tokens from user.
        // Note: malicious / misconfigured quote tokens could make the convertible token un-exercisable;
        // this is treated as a "buyer beware" case, handleable on the front-end.
        uint256 balanceBefore = IERC20(quoteToken).balanceOf(address(TRSRY));
        IERC20(quoteToken).safeTransferFrom(msg.sender, address(TRSRY), quoteAmount);
        uint256 balanceAfter = IERC20(quoteToken).balanceOf(address(TRSRY));
        if (balanceAfter - balanceBefore < quoteAmount)
            revert Teller_FeeOnTransfer(quoteAmount, balanceAfter - balanceBefore);

        emit ConvertibleTokenExercised(address(token), msg.sender, amount_, quoteAmount);
    }

    // ========== TOKEN LIFECYCLE ========== //

    /// @inheritdoc IPeriodicTask
    /// @dev Performs a bounded sweep of expired tokens; errors are swallowed to keep the
    ///      Heart's task pipeline healthy.
    ///
    ///      Reverts if the caller has not been granted the heart role.
    ///
    ///      Scans backward from the tail; new tokens append at the tail. If the active
    ///      set ever grows past `HEART_SWEEP_LIMIT` and the tail is dominated by un-expired
    ///      tokens, Heart-driven sweeps may starve old expired entries at the front. This
    ///      is harmless (cap enforcement uses monotonic `creatorMinted`; exercise is
    ///      unaffected) and can be cleared at any time by a permissionless call to
    ///      `sweepExpiredTokens(maxIterations_)` with a larger limit.
    function execute() external override onlyRole(ROLE_HEART) {
        if (!isEnabled) return; // Don't do anything if disabled

        try this.sweepExpiredTokens(HEART_SWEEP_LIMIT) {
            // Do nothing
        } catch {
            // Avoid failing loudly: sweeping is not critical to core protocol invariants,
            // and a revert here would disrupt other periodic tasks chained from the Heart.
            emit SweepExpiredTokensFailed();
        }
    }

    /// @inheritdoc IConvertibleOHMTeller
    /// @dev Reverts if:
    ///      - The policy is disabled.
    ///      - Called re-entrantly.
    ///
    ///      Scans backward from the tail; new tokens append at the tail.
    function sweepExpiredTokens(uint256 maxIterations_) public override onlyEnabled nonReentrant {
        uint256 totalReclaimed;
        uint256 iterations;
        uint256 i = _activeTokens.length();
        while (iterations < maxIterations_ && i != 0) {
            unchecked {
                --i;
            }
            address tokenAddr = _activeTokens.at(i);
            ConvertibleOHMToken token = ConvertibleOHMToken(tokenAddr);
            if (_isExpired(token.expiry())) {
                uint256 supply = token.totalSupply();
                // Decrement creator outstanding by the token supply
                if (supply != 0) creatorOutstanding[token.creator()] -= supply;
                _activeTokens.remove(tokenAddr); // Remove token from active set
                totalReclaimed += supply;
                emit ActiveTokenSwept(tokenAddr, supply);
            }
            unchecked {
                ++iterations;
            }
        }
        if (totalReclaimed != 0) MINTR.decreaseMintApproval(address(this), totalReclaimed);
    }

    // ========== VIEW FUNCTIONS ========== //

    /// @inheritdoc IConvertibleOHMTeller
    /// @dev Reverts if:
    ///      - The amount is zero.
    ///      - The token is not a deployed convertible token.
    ///      - The token has expired.
    function exerciseCost(
        address token_,
        uint256 amount_
    ) external view override returns (address, uint256) {
        _requireNonzeroAmount(1, amount_);
        (, address quoteToken, , , uint48 expiry, uint256 strikePrice) = _requireExistingToken(
            token_
        );
        _requireTokenNotExpired(expiry);

        // Calculate and return the amount of quote tokens required to exercise
        return (quoteToken, amount_.mulDivUp(strikePrice, _OHM_PRECISION));
    }

    /// @inheritdoc IConvertibleOHMTeller
    function remainingMintApproval() external view override returns (uint256) {
        return MINTR.mintApproval(address(this));
    }

    /// @inheritdoc IConvertibleOHMTeller
    function activeTokensLength() external view override returns (uint256) {
        return _activeTokens.length();
    }

    /// @inheritdoc IConvertibleOHMTeller
    function activeTokenAt(uint256 index_) external view override returns (address) {
        return _activeTokens.at(index_);
    }

    /// @inheritdoc IConvertibleOHMTeller
    function isActiveToken(address token_) external view override returns (bool) {
        return _activeTokens.contains(token_);
    }

    /// @inheritdoc IConvertibleOHMTeller
    function activeTokens() external view override returns (address[] memory) {
        return _activeTokens.values();
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
    ) external view override returns (address) {
        (eligible_, expiry_) = _truncateBothToUTCDay(eligible_, expiry_);
        return _getToken(quoteToken_, creator_, eligible_, expiry_, strikePrice_);
    }

    // ========== INTERNAL FUNCTIONS ========== //

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
        if (token == address(0)) {
            token = _deployToken(quoteToken_, creator_, eligible_, expiry_, strikePrice_);
            tokens[tokenHash] = token;
            _activeTokens.add(token);
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
        // Revert early for EOAs (no code at address) with a meaningful error
        if (token_.code.length == 0) revert Teller_UnsupportedToken(token_);

        // Load token parameters via try/catch to revert with a meaningful error for non-token contracts
        address quoteToken;
        address creator;
        uint48 eligible;
        uint48 expiry;
        uint256 strikePrice;

        try ConvertibleOHMToken(token_).parameters() returns (
            address quoteToken_,
            address creator_,
            uint48 eligible_,
            uint48 expiry_,
            uint256 strikePrice_
        ) {
            quoteToken = quoteToken_;
            creator = creator_;
            eligible = eligible_;
            expiry = expiry_;
            strikePrice = strikePrice_;
        } catch {
            revert Teller_UnsupportedToken(token_);
        }

        // Retrieve the internally stored convertible token with this configuration
        // Reverts internally if token doesn't exist (timestamps are already truncated)
        ConvertibleOHMToken token = ConvertibleOHMToken(
            _getToken(quoteToken, creator, eligible, expiry, strikePrice)
        );

        // Revert if provided token address does not match stored token address
        if (token_ != address(token)) revert Teller_UnsupportedToken(token_);

        return (token, quoteToken, creator, eligible, expiry, strikePrice);
    }

    function _isExpired(uint48 expiry_) private view returns (bool) {
        return uint48(block.timestamp) >= expiry_;
    }

    function _requireTokenNotExpired(uint48 expiry_) private view {
        if (_isExpired(expiry_)) revert Teller_TokenExpired(expiry_);
    }

    /// @notice Derives a name and symbol of the convertible token
    /// @dev Examples:
    ///      - Strike 21.42 USDS, expiry 2025-06-01: Name "OHM/USDS 21.42 20250601",  Symbol "convOHM-20250601"
    ///      - Strike 150   USDS, expiry 2025-12-31: Name "OHM/USDS 150.00 20251231", Symbol "convOHM-20251231"
    ///
    ///      The name is stored as bytes32, which limits the total length to 32 characters.
    ///      With a 5 character quote symbol the fixed parts ("OHM/" + symbol + " " + " " + "YYYYMMDD")
    ///      consume 19 bytes, leaving 13 bytes for the formatted price (e.g. "150.00" = 6 bytes).
    ///      Strike prices with more than ~10 whole digits may cause the name to be silently truncated.
    ///      This is a cosmetic limitation only: the token's immutable parameters (strike, expiry, etc.)
    ///      are unaffected by name truncation.
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

        // Format the strike price as decimal with up to 2 fractional digits (e.g., "21.42")
        bytes memory price = _formatPrice(strikePrice_, IERC20Metadata(quoteToken_).decimals());

        // Name: "OHM/QUOTE PRICE YYYYMMDD", Symbol: "convOHM-YYYYMMDD"
        name = bytes32(abi.encodePacked("OHM/", quoteSymbol, " ", price, " ", date));
        symbol = bytes32(abi.encodePacked("convOHM-", date));
        return (name, symbol);
    }

    /// @notice Formats price as a decimal string with 2 fractional digits
    /// @dev Requires tokenDecimals_ >= 2 to avoid underflow
    /// @param price_ The price in token decimals
    /// @param tokenDecimals_ The number of decimals in the quote token
    /// @return The formatted price as bytes (e.g., "21.00", "21.42", "21.07")
    function _formatPrice(
        uint256 price_,
        uint8 tokenDecimals_
    ) internal pure returns (bytes memory) {
        uint256 whole = price_ / (10 ** tokenDecimals_);
        uint256 frac = (price_ % (10 ** tokenDecimals_)) / (10 ** (tokenDecimals_ - 2));
        return abi.encodePacked(uint2str(whole), ".", frac < 10 ? "0" : "", uint2str(frac));
    }

    /// @notice Calculates a number of price decimals in the provided price
    /// @dev Used for validation in deploy() to ensure a strike price has sufficient precision.
    ///      Reverts via SafeCast if tokenDecimals_ exceeds int8 range (> 127).
    /// @param price_ The price to calculate the number of decimals for
    /// @param tokenDecimals_ The number of decimals in the quote token
    /// @return The number of price decimals (can be negative for prices < 1)
    function _getPriceDecimals(uint256 price_, uint8 tokenDecimals_) internal pure returns (int8) {
        int8 decimals;
        while (price_ >= 10) {
            price_ = price_ / 10;
            unchecked {
                ++decimals;
            }
        }
        return decimals - int256(uint256(tokenDecimals_)).toInt8();
    }

    function _getToken(
        address quoteToken_,
        address creator_,
        uint48 eligible_,
        uint48 expiry_,
        uint256 strikePrice_
    ) internal view returns (address) {
        bytes32 tokenHash = _getTokenHash(quoteToken_, creator_, eligible_, expiry_, strikePrice_);
        address token = tokens[tokenHash];
        if (token == address(0)) revert Teller_TokenDoesNotExist(tokenHash);
        return token;
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

    /// @notice Truncates a timestamp to 00:00:00 UTC of its day.
    /// @dev This produces canonical timestamps for token hash computation.
    ///      Tokens are identified by day, not by exact second, so all timestamps
    ///      within the same UTC day are mapped to the same hash.
    function _truncateToUTCDay(uint48 timestamp_) internal pure returns (uint48) {
        return uint48(timestamp_ / _UTC_DAY) * _UTC_DAY;
    }

    /// @dev Convenience wrapper that truncates both eligible and expiry to 00:00:00 UTC.
    function _truncateBothToUTCDay(
        uint48 eligible_,
        uint48 expiry_
    ) private pure returns (uint48, uint48) {
        return (_truncateToUTCDay(eligible_), _truncateToUTCDay(expiry_));
    }

    function _requireNonzeroAmount(uint256 index_, uint256 a_) private pure {
        if (a_ == 0) revert Teller_InvalidParams(index_, abi.encodePacked(a_));
    }

    function _requireNonzeroAddress(uint256 index_, address a_) private pure {
        if (a_ == address(0)) revert Teller_InvalidParams(index_, abi.encodePacked(a_));
    }

    // ========== ADMIN CONFIG ========== //

    /// @inheritdoc IConvertibleOHMTeller
    /// @dev Reverts if:
    ///      - The policy is disabled.
    ///      - The caller has not been granted the admin role.
    ///      - The new duration is less than one day.
    function setMinDuration(uint48 duration_) external override onlyEnabled onlyAdminRole {
        // Must be a minimum of 1 day due to rounding of eligible and expiry timestamps
        if (duration_ < _MIN_DURATION_FLOOR)
            revert Teller_InvalidParams(0, abi.encodePacked(duration_));
        _setMinDuration(duration_);
    }

    function _setMinDuration(uint48 duration_) private {
        minDuration = duration_;
        emit MinDurationSet(duration_);
    }

    /// @inheritdoc IConvertibleOHMTeller
    /// @dev Reverts if:
    ///      - The policy is disabled.
    ///      - The caller has not been granted the admin role.
    ///      - The new delay is less than one day.
    function setMinEligibleDelay(uint48 delay_) external override onlyEnabled onlyAdminRole {
        if (delay_ < _MIN_DURATION_FLOOR) revert Teller_InvalidParams(0, abi.encodePacked(delay_));
        _setMinEligibleDelay(delay_);
    }

    function _setMinEligibleDelay(uint48 delay_) private {
        minEligibleDelay = delay_;
        emit MinEligibleDelaySet(delay_);
    }

    /// @inheritdoc IConvertibleOHMTeller
    /// @dev Reverts if:
    ///      - The policy is disabled.
    ///      - The caller has not been granted the admin role.
    ///      - The creator address is zero.
    ///      - The new cap is below the creator's cumulative minted.
    function setCreatorMintCap(
        address creator_,
        uint256 cap_
    ) external override onlyEnabled onlyAdminRole {
        _setCreatorMintCap(creator_, cap_);
    }

    /// @dev Enforces `cap >= creatorMinted` so the budget already charged is never retroactively shrunk.
    ///      Set `cap == creatorMinted` to freeze new mints while keeping live tokens exercisable.
    ///      `creator_` parameter index is fixed at 0 in the error.
    function _setCreatorMintCap(address creator_, uint256 cap_) private {
        _requireNonzeroAddress(0, creator_);
        uint256 minted = creatorMinted[creator_];
        if (cap_ < minted) revert Teller_CapBelowMinted(creator_, minted, cap_);
        creatorMintCap[creator_] = cap_;
        emit CreatorMintCapSet(creator_, cap_);
    }

    // ========== IERC165 ========== //

    /// @inheritdoc PolicyEnabler
    function supportsInterface(
        bytes4 interfaceId_
    ) public view virtual override(PolicyEnabler, IPeriodicTask) returns (bool) {
        return
            interfaceId_ == type(IConvertibleOHMTeller).interfaceId ||
            interfaceId_ == type(IPeriodicTask).interfaceId ||
            interfaceId_ == type(IVersioned).interfaceId ||
            super.supportsInterface(interfaceId_);
    }
}
