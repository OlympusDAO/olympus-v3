// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {ERC721} from "solmate/tokens/ERC721.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {CDPOSv1} from "./CDPOS.v1.sol";
import {Kernel, Module, Keycode, toKeycode} from "src/Kernel.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Timestamp} from "src/libraries/Timestamp.sol";
import {DecimalString} from "src/libraries/DecimalString.sol";

contract OlympusConvertibleDepositPositions is CDPOSv1 {
    // ========== STATE VARIABLES ========== //

    uint256 public constant DECIMALS = 1e18;

    /// @notice The number of decimal places to display when rendering values as decimal strings.
    /// @dev    This affects the display of the remaining deposit and conversion price in the SVG and JSON metadata.
    ///         It can be adjusted using the `setDisplayDecimals` function, which is permissioned.
    uint8 internal _displayDecimals = 2;

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
        _mint(msg.sender, positionId_);

        emit PositionWrapped(positionId_);
    }

    /// @inheritdoc CDPOSv1
    /// @dev        This function reverts if:
    ///             - The position ID is invalid
    ///             - The caller is not the owner of the position
    ///             - The position is not wrapped
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
        address convertibleDepositToken_,
        uint256 remainingDeposit_,
        uint256 conversionPrice_,
        uint48 expiry_,
        bool wrap_
    ) internal returns (uint256 positionId) {
        // Create the position record
        positionId = positionCount++;
        _positions[positionId] = Position({
            owner: owner_,
            convertibleDepositToken: convertibleDepositToken_,
            remainingDeposit: remainingDeposit_,
            conversionPrice: conversionPrice_,
            expiry: expiry_,
            wrapped: wrap_
        });

        // Update ERC721 storage
        // TODO remove this, only when wrapped
        // _ownerOf[positionId] = owner_;
        // _balanceOf[owner_]++;

        // Add the position ID to the user's list of positions
        _userPositions[owner_].push(positionId);

        // If specified, wrap the position
        if (wrap_) _mint(owner_, positionId);

        // Emit the event
        emit PositionCreated(
            positionId,
            owner_,
            convertibleDepositToken_,
            remainingDeposit_,
            conversionPrice_,
            expiry_,
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
    ///             - The expiry is in the past
    function create(
        address owner_,
        address convertibleDepositToken_,
        uint256 remainingDeposit_,
        uint256 conversionPrice_,
        uint48 expiry_,
        bool wrap_
    ) external virtual override permissioned returns (uint256 positionId) {
        // Validate that the owner is not the zero address
        if (owner_ == address(0)) revert CDPOS_InvalidParams("owner");

        // Validate that the convertible deposit token is not the zero address
        if (convertibleDepositToken_ == address(0))
            revert CDPOS_InvalidParams("convertible deposit token");

        // Validate that the remaining deposit is greater than 0
        if (remainingDeposit_ == 0) revert CDPOS_InvalidParams("deposit");

        // Validate that the conversion price is greater than 0
        if (conversionPrice_ == 0) revert CDPOS_InvalidParams("conversion price");

        // Validate that the expiry is in the future
        if (expiry_ <= block.timestamp) revert CDPOS_InvalidParams("expiry");

        return
            _create(
                owner_,
                convertibleDepositToken_,
                remainingDeposit_,
                conversionPrice_,
                expiry_,
                wrap_
            );
    }

    /// @inheritdoc CDPOSv1
    /// @dev        This function reverts if:
    ///             - The caller is not permissioned
    ///             - The position ID is invalid
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
            position.convertibleDepositToken,
            amount_,
            position.conversionPrice,
            position.expiry,
            wrap_
        );

        // Emit the event
        emit PositionSplit(
            positionId_,
            newPositionId,
            position.convertibleDepositToken,
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
    function _render(
        uint256 positionId_,
        Position memory position_
    ) internal view returns (string memory) {
        // Get the decimals of the deposit token
        uint8 depositDecimals = ERC20(position_.convertibleDepositToken).decimals();

        return
            string.concat(
                '<svg width="200" height="200" viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">',
                '<rect width="100" height="100" fill="#ffffff" />',
                string.concat(
                    '<text x="50" y="40" font-size="50" text-anchor="middle" fill="#768299">',
                    unicode"Ω",
                    "</text>"
                ),
                '<text x="50" y="50" font-size="7" text-anchor="middle" fill="#768299">Convertible Deposit</text>',
                string.concat(
                    '<text x="5" y="65" font-size="7" text-anchor="left" fill="#768299">ID: ',
                    Strings.toString(positionId_),
                    "</text>"
                ),
                string.concat(
                    '<text x="5" y="75" font-size="7" text-anchor="left" fill="#768299">Expiry: ',
                    _getTimeString(position_.expiry),
                    "</text>"
                ),
                string.concat(
                    '<text x="5" y="85" font-size="7" text-anchor="left" fill="#768299">Remaining: ',
                    DecimalString.toDecimalString(
                        position_.remainingDeposit,
                        depositDecimals,
                        _displayDecimals
                    ),
                    "</text>"
                ),
                string.concat(
                    '<text x="5" y="95" font-size="7" text-anchor="left" fill="#768299">Conversion: ',
                    DecimalString.toDecimalString(
                        position_.conversionPrice,
                        depositDecimals,
                        _displayDecimals
                    ),
                    "</text>"
                ), // TODO check decimals of conversion price. This probably isn't correct.
                "</svg>"
            );
    }

    // solhint-enable quotes

    /// @inheritdoc ERC721
    // solhint-disable quotes
    function tokenURI(uint256 id_) public view virtual override returns (string memory) {
        Position memory position = _getPosition(id_);

        // Get the decimals of the deposit token
        uint8 depositDecimals = ERC20(position.convertibleDepositToken).decimals();

        // solhint-disable-next-line quotes
        string memory jsonContent = string.concat(
            "{",
            string.concat('"name": "', name, '",'),
            string.concat('"symbol": "', symbol, '",'),
            '"attributes": [',
            string.concat('{"trait_type": "Position ID", "value": "', Strings.toString(id_), '"},'),
            string.concat(
                '{"trait_type": "Convertible Deposit Token", "value": "',
                Strings.toHexString(position.convertibleDepositToken),
                '"},'
            ),
            string.concat(
                '{"trait_type": "Expiry", "display_type": "date", "value": "',
                Strings.toString(position.expiry),
                '"},'
            ),
            string.concat(
                '{"trait_type": "Remaining Deposit", "value": "',
                DecimalString.toDecimalString(
                    position.remainingDeposit,
                    depositDecimals,
                    _displayDecimals
                ),
                '"},'
            ),
            string.concat(
                '{"trait_type": "Conversion Price", "value": "',
                DecimalString.toDecimalString(
                    position.conversionPrice,
                    depositDecimals,
                    _displayDecimals
                ),
                '"},'
            ),
            "]",
            string.concat(
                '"image": "',
                "data:image/svg+xml;base64,",
                Base64.encode(bytes(_render(id_, position))),
                '"}'
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

        // Ownership is validated in `transferFrom` on the parent contract

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
        // `create()` blocks a 0 conversion price, so this should never happen on a valid position
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
    /// @return     Returns true if the expiry timestamp is now or in the past
    function isExpired(uint256 positionId_) external view virtual override returns (bool) {
        return _getPosition(positionId_).expiry <= block.timestamp;
    }

    function _previewConvert(
        uint256 amount_,
        uint256 conversionPrice_
    ) internal pure returns (uint256) {
        return (amount_ * DECIMALS) / conversionPrice_; // TODO check decimals, rounding
    }

    /// @inheritdoc CDPOSv1
    function previewConvert(
        uint256 positionId_,
        uint256 amount_
    ) public view virtual override onlyValidPosition(positionId_) returns (uint256) {
        return _previewConvert(amount_, _getPosition(positionId_).conversionPrice);
    }

    // ========== ADMIN FUNCTIONS ========== //

    /// @notice Set the number of decimal places to display when rendering values as decimal strings.
    /// @dev    This affects the display of the remaining deposit and conversion price in the SVG and JSON metadata.
    function setDisplayDecimals(uint8 decimals_) external permissioned {
        _displayDecimals = decimals_;
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
