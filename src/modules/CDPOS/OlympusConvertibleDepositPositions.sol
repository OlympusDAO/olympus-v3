// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {ERC721} from "solmate/tokens/ERC721.sol";
import {CDPOSv1} from "./CDPOS.v1.sol";
import {Kernel, Module} from "src/Kernel.sol";

contract OlympusConvertibleDepositPositions is CDPOSv1 {
    constructor(
        address kernel_
    ) Module(Kernel(kernel_)) ERC721("Olympus Convertible Deposit Positions", "OCDP") {}

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
        uint256 remainingDeposit_,
        uint256 conversionPrice_,
        uint48 expiry_,
        bool wrap_
    ) internal returns (uint256 positionId) {
        // Create the position record
        positionId = ++positionCount;
        _positions[positionId] = Position({
            remainingDeposit: remainingDeposit_,
            conversionPrice: conversionPrice_,
            expiry: expiry_,
            wrapped: wrap_
        });

        // Update ERC721 storage
        _ownerOf[positionId] = owner_;
        _balanceOf[owner_]++;

        // Add the position ID to the user's list of positions
        _userPositions[owner_].push(positionId);

        // If specified, wrap the position
        if (wrap_) _mint(owner_, positionId);

        // Emit the event
        emit PositionCreated(
            positionId,
            owner_,
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
    ///             - The remaining deposit is 0
    ///             - The conversion price is 0
    ///             - The expiry is in the past
    function create(
        address owner_,
        uint256 remainingDeposit_,
        uint256 conversionPrice_,
        uint48 expiry_,
        bool wrap_
    ) external virtual override permissioned returns (uint256 positionId) {
        // Validate that the owner is not the zero address
        if (owner_ == address(0)) revert CDPOS_InvalidParams("owner");

        // Validate that the remaining deposit is greater than 0
        if (remainingDeposit_ == 0) revert CDPOS_InvalidParams("deposit");

        // Validate that the conversion price is greater than 0
        if (conversionPrice_ == 0) revert CDPOS_InvalidParams("conversion price");

        // Validate that the expiry is in the future
        if (expiry_ <= block.timestamp) revert CDPOS_InvalidParams("expiry");

        return _create(owner_, remainingDeposit_, conversionPrice_, expiry_, wrap_);
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
        newPositionId = _create(to_, amount_, position.conversionPrice, position.expiry, wrap_);

        // Emit the event
        emit PositionSplit(positionId_, newPositionId, amount_, to_, wrap_);

        return newPositionId;
    }

    // ========== ERC721 OVERRIDES ========== //

    /// @inheritdoc ERC721
    function tokenURI(uint256 id_) public view virtual override returns (string memory) {
        // TODO implement tokenURI SVG
        return "";
    }

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

    // ========== MODIFIERS ========== //

    modifier onlyValidPosition(uint256 positionId_) {
        if (_getPosition(positionId_).conversionPrice == 0)
            revert CDPOS_InvalidPositionId(positionId_);
        _;
    }

    modifier onlyPositionOwner(uint256 positionId_) {
        // This validates that the caller is the owner of the position
        if (_ownerOf[positionId_] != msg.sender) revert CDPOS_NotOwner(positionId_);
        _;
    }
}
