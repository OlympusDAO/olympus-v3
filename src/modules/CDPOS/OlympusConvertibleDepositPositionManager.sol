// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.15;

// Libraries
import {ERC721} from "@solmate-6.2.0/tokens/ERC721.sol";
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";
import {Strings} from "@openzeppelin-5.3.0/utils/Strings.sol";
import {Base64} from "@openzeppelin-5.3.0/utils/Base64.sol";
import {Timestamp} from "src/libraries/Timestamp.sol";
import {DecimalString} from "src/libraries/DecimalString.sol";

// Bophades
import {CDPOSv1} from "src/modules/CDPOS/CDPOS.v1.sol";
import {Kernel, Module, Keycode, toKeycode} from "src/Kernel.sol";

/// @title  Olympus Convertible Deposit Position Manager
/// @notice Implementation of the {CDPOSv1} interface
///         This contract is used to create, manage, and wrap/unwrap convertible deposit positions
contract OlympusConvertibleDepositPositionManager is CDPOSv1 {
    // ========== STATE VARIABLES ========== //

    /// @notice The number of decimal places to display when rendering values as decimal strings.
    /// @dev    This affects the display of the remaining deposit and conversion price in the SVG and JSON metadata.
    ///         It can be adjusted using the `setDisplayDecimals` function, which is permissioned.
    uint8 public displayDecimals = 2;

    // ========== CONSTRUCTOR ========== //

    constructor(
        address kernel_
    ) Module(Kernel(kernel_)) ERC721("Olympus Convertible Deposit Position", "OCDP") {}

    // ========== MODULE FUNCTIONS ========== //

    /// @inheritdoc Module
    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("CDPOS");
    }

    /// @inheritdoc Module
    function VERSION() public pure override returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;
    }

    // ========== WRAPPING ========== //

    /// @inheritdoc CDPOSv1
    /// @dev        This function reverts if:
    ///             - The position ID is invalid
    ///             - The caller is not the owner of the position
    ///             - The position is already wrapped
    ///
    ///             This is a public function that can be called by any address holding a position
    function wrap(
        uint256 positionId_
    ) external virtual override onlyValidPosition(positionId_) onlyPositionOwner(positionId_) {
        // Does not need to check for invalid position ID because the modifier already ensures that
        Position storage position = _positions[positionId_];

        // Validate that the position is not already wrapped
        if (position.wrapped) revert CDPOS_AlreadyWrapped(positionId_);

        // Mark the position as wrapped
        position.wrapped = true;

        // Mint the ERC721 token
        _safeMint(msg.sender, positionId_);

        emit PositionWrapped(positionId_);
    }

    /// @inheritdoc CDPOSv1
    /// @dev        This function reverts if:
    ///             - The position ID is invalid
    ///             - The caller is not the owner of the position
    ///             - The position is not wrapped
    ///
    ///             This is a public function that can be called by any address holding a position
    function unwrap(
        uint256 positionId_
    ) external virtual override onlyValidPosition(positionId_) onlyPositionOwner(positionId_) {
        // Does not need to check for invalid position ID because the modifier already ensures that
        Position storage position = _positions[positionId_];

        // Validate that the position is wrapped
        if (!position.wrapped) revert CDPOS_NotWrapped(positionId_);

        // Mark the position as unwrapped
        position.wrapped = false;

        // Burn the ERC721 token
        _burn(positionId_);

        emit PositionUnwrapped(positionId_);
    }

    // ========== POSITION MANAGEMENT =========== //

    function _create(
        address owner_,
        address asset_,
        uint8 periodMonths_,
        uint256 remainingDeposit_,
        uint256 conversionPrice_,
        uint48 conversionExpiry_,
        bool wrap_
    ) internal returns (uint256 positionId) {
        // Create the position record
        positionId = positionCount++;
        _positions[positionId] = Position({
            owner: owner_,
            asset: asset_,
            periodMonths: periodMonths_,
            remainingDeposit: remainingDeposit_,
            conversionPrice: conversionPrice_,
            expiry: conversionExpiry_,
            wrapped: wrap_
        });

        // Add the position ID to the user's list of positions
        _userPositions[owner_].push(positionId);

        // If specified, wrap the position
        if (wrap_) _safeMint(owner_, positionId);

        // Emit the event
        emit PositionCreated(
            positionId,
            owner_,
            asset_,
            periodMonths_,
            remainingDeposit_,
            conversionPrice_,
            conversionExpiry_,
            wrap_
        );

        return positionId;
    }

    /// @inheritdoc CDPOSv1
    /// @dev        This function reverts if:
    ///             - The caller is not permissioned
    ///             - The owner is the zero address
    ///             - The convertible deposit token is the zero address
    ///             - The remaining deposit is 0
    ///             - The conversion price is 0
    ///             - The conversion expiry is in the past
    ///
    ///             This is a permissioned function that can only be called by approved policies
    function mint(
        address owner_,
        address asset_,
        uint8 periodMonths_,
        uint256 remainingDeposit_,
        uint256 conversionPrice_,
        uint48 conversionExpiry_,
        bool wrap_
    ) external virtual override permissioned returns (uint256 positionId) {
        // Validate that the owner is not the zero address
        if (owner_ == address(0)) revert CDPOS_InvalidParams("owner");

        // Validate that the asset is not the zero address
        if (asset_ == address(0)) revert CDPOS_InvalidParams("asset");

        // Validate that the period is greater than 0
        if (periodMonths_ == 0) revert CDPOS_InvalidParams("period");

        // Validate that the remaining deposit is greater than 0
        if (remainingDeposit_ == 0) revert CDPOS_InvalidParams("deposit");

        // Validate that the conversion price is greater than 0
        if (conversionPrice_ == 0) revert CDPOS_InvalidParams("conversion price");

        // Validate that the conversion expiry is in the future
        if (conversionExpiry_ <= block.timestamp) revert CDPOS_InvalidParams("conversion expiry");

        return
            _create(
                owner_,
                asset_,
                periodMonths_,
                remainingDeposit_,
                conversionPrice_,
                conversionExpiry_,
                wrap_
            );
    }

    /// @inheritdoc CDPOSv1
    /// @dev        This function reverts if:
    ///             - The caller is not permissioned
    ///             - The position ID is invalid
    ///
    ///             This is a permissioned function that can only be called by approved policies
    function update(
        uint256 positionId_,
        uint256 amount_
    ) external virtual override permissioned onlyValidPosition(positionId_) {
        // Update the remaining deposit of the position
        Position storage position = _positions[positionId_];
        position.remainingDeposit = amount_;

        // Emit the event
        emit PositionUpdated(positionId_, amount_);
    }

    /// @inheritdoc CDPOSv1
    /// @dev        This function reverts if:
    ///             - The caller is not the owner of the position
    ///             - The amount is 0
    ///             - The amount is greater than the remaining deposit
    ///             - `to_` is the zero address
    ///
    ///             This is a public function that can be called by any address holding a position
    function split(
        uint256 positionId_,
        uint256 amount_,
        address to_,
        bool wrap_
    )
        external
        virtual
        override
        onlyValidPosition(positionId_)
        onlyPositionOwner(positionId_)
        returns (uint256 newPositionId)
    {
        Position storage position = _positions[positionId_];

        // Validate that the amount is greater than 0
        if (amount_ == 0) revert CDPOS_InvalidParams("amount");

        // Validate that the amount is less than or equal to the remaining deposit
        if (amount_ > position.remainingDeposit) revert CDPOS_InvalidParams("amount");

        // Validate that the to address is not the zero address
        if (to_ == address(0)) revert CDPOS_InvalidParams("to");

        // Calculate the remaining deposit of the existing position
        uint256 remainingDeposit = position.remainingDeposit - amount_;

        // Update the remaining deposit of the existing position
        position.remainingDeposit = remainingDeposit;

        // Create the new position
        newPositionId = _create(
            to_,
            position.asset,
            position.periodMonths,
            amount_,
            position.conversionPrice,
            position.expiry,
            wrap_
        );

        // Emit the event
        emit PositionSplit(
            positionId_,
            newPositionId,
            position.asset,
            position.periodMonths,
            amount_,
            to_,
            wrap_
        );

        return newPositionId;
    }

    // ========== ERC721 OVERRIDES ========== //

    function _getTimeString(uint48 time_) internal pure returns (string memory) {
        (string memory year, string memory month, string memory day) = Timestamp.toPaddedString(
            time_
        );

        return string.concat(year, "-", month, "-", day);
    }

    // solhint-disable quotes
    function _render(uint256, Position memory position_) internal view returns (string memory) {
        // Get the decimals of the deposit token
        uint8 depositDecimals;
        string memory cdSymbol;
        {
            ERC20 asset = ERC20(position_.asset);
            depositDecimals = asset.decimals();
            cdSymbol = asset.symbol();
        }

        bool positionIsConvertible = _isConvertible(position_);
        // TODO add deposit period

        return
            string.concat(
                '<svg width="500" height="600" viewBox="0 0 500 600" fill="none" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"><rect width="500" height="600" rx="18" fill="#141722" /><rect x="73.0154" y="63" width="353" height="353" rx="176.5" fill="#708B96" /><path id="Vector" d="M233.546 286.32C213.544 281.175 197.413 260.273 197.413 236.476C197.413 209.142 221.287 185.346 249.676 185.346C280.002 185.989 301.617 209.464 301.617 236.476C301.617 260.273 287.1 278.924 265.807 286.32V317.513H324.523V294.36H284.196V298.862C310.65 290.501 324.845 263.81 324.845 236.476C324.845 195.958 291.939 162.193 249.676 162.193C208.705 162.193 174.185 195.958 174.185 236.476C174.185 263.81 188.057 289.214 213.544 299.183L214.189 294.36H174.185V317.513H233.546V286.32Z" fill="#EEE9E2" />',
                string.concat(
                    '<text xml:space="preserve" class="heading"><tspan x="32" y="465.504">',
                    positionIsConvertible
                        ? string.concat(cdSymbol, "-OHM Convertible Deposit")
                        : string.concat(cdSymbol, " Yield-Bearing Deposit"),
                    "</tspan></text>"
                ),
                '<rect x="33" y="477" width="434" height="90" rx="9" fill="#2C2E37" />',
                positionIsConvertible
                    ? string.concat(
                        '<text xml:space="preserve" class="standard-text"><tspan x="42" y="503.16">Conversion Price</tspan><tspan x="457" y="503.003" text-anchor="end">',
                        DecimalString.toDecimalString(
                            position_.conversionPrice,
                            depositDecimals,
                            displayDecimals
                        ),
                        " ",
                        cdSymbol,
                        "/OHM</tspan></text>"
                    )
                    : string.concat(
                        '<text xml:space="preserve" class="standard-text"><tspan x="42" y="503.16">Remaining Deposit</tspan><tspan x="457" y="503.003" text-anchor="end">',
                        DecimalString.toDecimalString(
                            position_.remainingDeposit,
                            depositDecimals,
                            displayDecimals
                        ),
                        " ",
                        cdSymbol,
                        "</tspan></text>"
                    ),
                positionIsConvertible
                    ? string.concat(
                        '<text xml:space="preserve" class="standard-text"><tspan x="42" y="527.16">Convertible To</tspan><tspan x="457" y="527.003" text-anchor="end">',
                        DecimalString.toDecimalString(
                            _previewConvert(position_.remainingDeposit, position_.conversionPrice),
                            9,
                            2
                        ),
                        " OHM</tspan></text>"
                    )
                    : "",
                positionIsConvertible
                    ? string.concat(
                        '<text xml:space="preserve" class="standard-text"><tspan x="42" y="551.16">Conversion Expiry</tspan><tspan x="457" y="551.003" text-anchor="end">',
                        _getTimeString(position_.expiry),
                        "</tspan></text>"
                    )
                    : "",
                '<path id="Vector_2" d="M54.292 46.5102C52.9142 46.5102 52.2072 45.3229 52.2072 43.7639C52.2072 42.2049 52.9142 41.0056 54.292 41.0056C55.6819 41.0056 56.3647 42.2049 56.3647 43.7639C56.3647 45.3229 55.6819 46.5102 54.292 46.5102ZM50.0505 43.7639C50.0505 46.3303 51.692 48.2371 54.2801 48.2371C56.88 48.2371 58.5214 46.3303 58.5214 43.7639C58.5214 41.1975 56.88 39.2907 54.2801 39.2907C51.692 39.2907 50.0505 41.1975 50.0505 43.7639ZM59.2402 48.0332H61.2171V39.4585H59.2402V48.0332ZM63.0383 48.5369H62.3673V50.0601H63.6374C64.8714 50.0601 65.4585 49.5564 65.9498 48.1172L68.0705 41.8931H66.1175L65.3147 44.5075C65.123 45.1071 64.9553 45.9226 64.9553 45.9226H64.9313C64.9313 45.9226 64.7397 45.1071 64.548 44.5075L63.7212 41.8931H61.6604L63.4696 46.6181C63.7212 47.2658 63.8411 47.6255 63.8411 47.8893C63.8411 48.3091 63.6134 48.5369 63.0383 48.5369ZM68.5017 41.8931V48.0332H70.4547V44.5915C70.4547 43.8599 70.8141 43.3442 71.4251 43.3442C72.0122 43.3442 72.2877 43.728 72.2877 44.3876V48.0332H74.2407V44.5915C74.2407 43.8599 74.5882 43.3442 75.2113 43.3442C75.7983 43.3442 76.0739 43.728 76.0739 44.3876V48.0332H78.0269V44.0398C78.0269 42.6606 77.3319 41.7131 75.9421 41.7131C75.1512 41.7131 74.4923 42.049 74.0131 42.7926H73.9891C73.6776 42.133 73.0666 41.7131 72.2638 41.7131C71.3772 41.7131 70.7902 42.133 70.4067 42.7685H70.3707V41.8931H68.5017ZM78.9134 41.8931V50.0601H80.8664V47.3977H80.8902C81.2737 47.9134 81.8368 48.2251 82.6276 48.2251C84.2331 48.2251 85.2994 46.954 85.2994 44.9632C85.2994 43.1163 84.3049 41.7131 82.6755 41.7131C81.8368 41.7131 81.2377 42.085 80.8184 42.6367H80.7824V41.8931H78.9134ZM80.8063 45.0352C80.8063 44.0398 81.2377 43.2843 82.0884 43.2843C82.9271 43.2843 83.3225 43.9799 83.3225 45.0352C83.3225 46.0784 82.8671 46.7141 82.1244 46.7141C81.2857 46.7141 80.8063 46.0305 80.8063 45.0352ZM88.0671 48.2132C88.9177 48.2132 89.457 47.8774 89.9001 47.2777H89.9361V48.0332H91.8053V41.8931H89.8524V45.3229C89.8524 46.0545 89.4448 46.5582 88.774 46.5582C88.151 46.5582 87.8515 46.1865 87.8515 45.5148V41.8931H85.9104V45.9226C85.9104 47.2898 86.6533 48.2132 88.0671 48.2132ZM95.3517 48.2251C96.9572 48.2251 98.1432 47.5296 98.1432 46.1865C98.1432 44.6154 96.8733 44.3396 95.795 44.1597C95.0162 44.0157 94.3212 43.9558 94.3212 43.524C94.3212 43.1404 94.6927 42.9604 95.1719 42.9604C95.7111 42.9604 96.0825 43.1284 96.1544 43.6801H97.9517C97.8558 42.4687 96.9212 41.7131 95.1839 41.7131C93.7343 41.7131 92.5361 42.3848 92.5361 43.6801C92.5361 45.1191 93.6742 45.4069 94.7407 45.5869C95.5554 45.7306 96.2982 45.7907 96.2982 46.3424C96.2982 46.7382 95.9267 46.954 95.3398 46.954C94.6927 46.954 94.2854 46.6542 94.2134 46.0426H92.3683C92.4281 47.3977 93.5545 48.2251 95.3517 48.2251Z" fill="#EEE9E2" /><path id="Vector_3" d="M38.2714 47.349C36.5249 46.8978 35.1166 45.0653 35.1166 42.9788C35.1166 40.5823 37.201 38.496 39.6798 38.496C42.3275 38.5523 44.2148 40.6105 44.2148 42.9788C44.2148 45.0653 42.9472 46.7006 41.0882 47.349V50.0839H46.2148V48.0539H42.6937V48.4485C45.0036 47.7155 46.2429 45.3753 46.2429 42.9788C46.2429 39.4265 43.3698 36.466 39.6798 36.466C36.1025 36.466 33.0884 39.4265 33.0884 42.9788C33.0884 45.3753 34.2997 47.6027 36.5249 48.4767L36.5813 48.0539H33.0884V50.0839H38.2714V47.349Z" fill="#EEE9E2" />',
                '<defs><style type="text/css">.heading{fill:#F8CC82;font-family:"Helvetica Neue",Helvetica,-apple-system,BlinkMacSystemFont,Ubuntu,Jost,"DM Sans",sans-serif;font-size:24px;font-weight:500;letter-spacing:0em;white-space:pre;}.standard-text{fill:#EEE9E2;font-family:"Helvetica Neue",Helvetica,-apple-system,BlinkMacSystemFont,Ubuntu,Jost,"DM Sans",sans-serif;font-size:15px;font-weight:500;letter-spacing:0em;white-space:pre;}</style></defs></svg>'
            );
    }

    // solhint-enable quotes

    /// @inheritdoc ERC721
    // solhint-disable quotes
    function tokenURI(uint256 id_) public view virtual override returns (string memory) {
        Position memory position = _getPosition(id_);

        // Get the decimals of the deposit token
        uint8 depositDecimals = ERC20(position.asset).decimals();

        bool positionIsConvertible = _isConvertible(position);

        // solhint-disable-next-line quotes
        string memory jsonContent = string.concat(
            "{",
            string.concat('"name": "', name, '",'),
            string.concat('"symbol": "', symbol, '",'),
            '"attributes": [',
            string.concat('{"trait_type": "Position ID", "value": ', Strings.toString(id_), "},"),
            string.concat(
                '{"trait_type": "Deposit Asset", "value": "',
                Strings.toHexString(position.asset),
                '"},'
            ),
            string.concat(
                '{"trait_type": "Deposit Period", "value": ',
                Strings.toString(position.periodMonths),
                "},"
            ),
            positionIsConvertible
                ? string.concat(
                    '{"trait_type": "Conversion Expiry", "display_type": "date", "value": ',
                    Strings.toString(position.expiry),
                    "},"
                )
                : "",
            positionIsConvertible
                ? string.concat(
                    '{"trait_type": "Conversion Price", "value": ',
                    DecimalString.toDecimalString(
                        position.conversionPrice,
                        depositDecimals,
                        displayDecimals
                    ),
                    "},"
                )
                : "",
            string.concat(
                '{"trait_type": "Remaining Deposit", "value": ',
                DecimalString.toDecimalString(
                    position.remainingDeposit,
                    depositDecimals,
                    displayDecimals
                ),
                "}"
            ),
            "],",
            string.concat(
                '"image": "',
                "data:image/svg+xml;base64,",
                Base64.encode(bytes(_render(id_, position))),
                '"'
            ),
            "}"
        );

        return string.concat("data:application/json;base64,", Base64.encode(bytes(jsonContent)));
    }

    // solhint-enable quotes

    /// @inheritdoc ERC721
    /// @dev        This function performs the following:
    ///             - Updates the owner of the position
    ///             - Calls `transferFrom` on the parent contract
    function transferFrom(address from_, address to_, uint256 tokenId_) public override {
        Position storage position = _positions[tokenId_];

        // Validate that the position is valid
        if (position.conversionPrice == 0) revert CDPOS_InvalidPositionId(tokenId_);

        // Validate that the position is wrapped/minted
        if (!position.wrapped) revert CDPOS_NotWrapped(tokenId_);

        // Additional validation performed in super.transferForm():
        // - Approvals
        // - Ownership
        // - Destination address

        // Update the position record
        position.owner = to_;

        // Add to user positions on the destination address
        _userPositions[to_].push(tokenId_);

        // Remove from user terms on the source address
        bool found = false;
        for (uint256 i = 0; i < _userPositions[from_].length; i++) {
            if (_userPositions[from_][i] == tokenId_) {
                _userPositions[from_][i] = _userPositions[from_][_userPositions[from_].length - 1];
                _userPositions[from_].pop();
                found = true;
                break;
            }
        }
        if (!found) revert CDPOS_InvalidPositionId(tokenId_);

        // Call `transferFrom` on the parent contract
        super.transferFrom(from_, to_, tokenId_);
    }

    // ========== TERM INFORMATION ========== //

    function _getPosition(uint256 positionId_) internal view returns (Position memory) {
        Position memory position = _positions[positionId_];
        // `mint()` blocks a 0 conversion price, so this should never happen on a valid position
        if (position.conversionPrice == 0) revert CDPOS_InvalidPositionId(positionId_);

        return position;
    }

    /// @inheritdoc CDPOSv1
    function getUserPositionIds(
        address user_
    ) external view virtual override returns (uint256[] memory positionIds) {
        return _userPositions[user_];
    }

    /// @inheritdoc CDPOSv1
    /// @dev        This function reverts if:
    ///             - The position ID is invalid
    function getPosition(
        uint256 positionId_
    ) external view virtual override returns (Position memory) {
        return _getPosition(positionId_);
    }

    /// @inheritdoc CDPOSv1
    /// @dev        This function reverts if:
    ///             - The position ID is invalid
    ///
    /// @return     isExpired_  Returns true if the conversion expiry timestamp is now or in the past
    function isExpired(
        uint256 positionId_
    ) external view virtual override returns (bool isExpired_) {
        isExpired_ = _getPosition(positionId_).expiry <= block.timestamp;
    }

    function _isConvertible(Position memory position_) internal pure returns (bool) {
        return
            position_.conversionPrice != NON_CONVERSION_PRICE &&
            position_.expiry != NON_CONVERSION_EXPIRY;
    }

    /// @inheritdoc CDPOSv1
    /// @dev        This function reverts if:
    ///             - The position ID is invalid
    ///
    /// @return     isConvertible_  Returns true if the conversion price is not the maximum value
    function isConvertible(
        uint256 positionId_
    ) external view virtual override returns (bool isConvertible_) {
        isConvertible_ = _isConvertible(_getPosition(positionId_));
    }

    function _previewConvert(
        uint256 amount_,
        uint256 conversionPrice_
    ) internal pure returns (uint256) {
        // amount_ and conversionPrice_ are in the same decimals and cancel each other out
        // The output needs to be in OHM, so we multiply by 1e9
        // This also deliberately rounds down
        return (amount_ * 1e9) / conversionPrice_;
    }

    /// @inheritdoc CDPOSv1
    function previewConvert(
        uint256 positionId_,
        uint256 amount_
    ) public view virtual override onlyValidPosition(positionId_) returns (uint256) {
        Position memory position = _getPosition(positionId_);

        // If expired, conversion output is 0
        if (position.expiry <= block.timestamp) return 0;

        // If the amount is greater than the remaining deposit, revert
        if (amount_ > position.remainingDeposit) revert CDPOS_InvalidParams("amount");

        // If conversion is not supported, revert
        if (!_isConvertible(position)) revert CDPOS_NotConvertible(positionId_);

        return _previewConvert(amount_, position.conversionPrice);
    }

    // ========== ADMIN FUNCTIONS ========== //

    /// @notice Set the number of decimal places to display when rendering values as decimal strings.
    /// @dev    This affects the display of the remaining deposit and conversion price in the SVG and JSON metadata.
    function setDisplayDecimals(uint8 decimals_) external permissioned {
        displayDecimals = decimals_;
    }

    // ========== MODIFIERS ========== //

    modifier onlyValidPosition(uint256 positionId_) {
        if (_getPosition(positionId_).conversionPrice == 0)
            revert CDPOS_InvalidPositionId(positionId_);
        _;
    }

    modifier onlyPositionOwner(uint256 positionId_) {
        // This validates that the caller is the owner of the position
        if (_getPosition(positionId_).owner != msg.sender) revert CDPOS_NotOwner(positionId_);
        _;
    }
}
