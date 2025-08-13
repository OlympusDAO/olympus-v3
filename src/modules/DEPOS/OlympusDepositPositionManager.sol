// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.15;

// Interfaces
import {IERC165} from "@openzeppelin-5.3.0/utils/introspection/IERC165.sol";

// Libraries
import {ERC721} from "@solmate-6.2.0/tokens/ERC721.sol";
import {EnumerableSet} from "@openzeppelin-5.3.0/utils/structs/EnumerableSet.sol";

// Bophades
import {DEPOSv1} from "src/modules/DEPOS/DEPOS.v1.sol";
import {Kernel, Module, Keycode, toKeycode} from "src/Kernel.sol";
import {IDepositPositionManager} from "src/modules/DEPOS/IDepositPositionManager.sol";
import {IPositionTokenRenderer} from "src/modules/DEPOS/IPositionTokenRenderer.sol";

/// @title  Olympus Deposit Position Manager
/// @notice Implementation of the {DEPOSv1} interface
///         This contract is used to create, manage, and wrap/unwrap deposit positions. Positions are optionally convertible.
contract OlympusDepositPositionManager is DEPOSv1 {
    using EnumerableSet for EnumerableSet.UintSet;

    // ========== STATE VARIABLES ========== //

    /// @notice The address of the token renderer contract
    /// @dev    If set, tokenURI() will delegate to this contract. If not set, tokenURI() returns an empty string.
    address internal _tokenRenderer;

    uint256 internal constant _OHM_SCALE = 1e9;

    // ========== CONSTRUCTOR ========== //

    constructor(
        address kernel_,
        address tokenRenderer_
    ) Module(Kernel(kernel_)) ERC721("Olympus Deposit Position", "ODP") {
        _setTokenRenderer(tokenRenderer_);
    }

    // ========== MODULE FUNCTIONS ========== //

    /// @inheritdoc Module
    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("DEPOS");
    }

    /// @inheritdoc Module
    function VERSION() public pure override returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;
    }

    // ========== WRAPPING ========== //

    /// @inheritdoc IDepositPositionManager
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
        if (position.wrapped) revert DEPOS_AlreadyWrapped(positionId_);

        // Mark the position as wrapped
        position.wrapped = true;

        // Mint the ERC721 token
        _safeMint(msg.sender, positionId_);

        emit PositionWrapped(positionId_);
    }

    /// @inheritdoc IDepositPositionManager
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
        if (!position.wrapped) revert DEPOS_NotWrapped(positionId_);

        // Mark the position as unwrapped
        position.wrapped = false;

        // Burn the ERC721 token
        _burn(positionId_);

        emit PositionUnwrapped(positionId_);
    }

    // ========== POSITION MANAGEMENT =========== //

    function _create(
        address operator_,
        IDepositPositionManager.MintParams memory params_
    ) internal returns (uint256 positionId) {
        // Create the position record
        positionId = _positionCount++;
        _positions[positionId] = Position({
            operator: operator_,
            owner: params_.owner,
            asset: params_.asset,
            periodMonths: params_.periodMonths,
            remainingDeposit: params_.remainingDeposit,
            conversionPrice: params_.conversionPrice,
            expiry: params_.expiry,
            wrapped: params_.wrapPosition,
            additionalData: params_.additionalData
        });

        // Add the position ID to the user's list of positions
        _userPositions[params_.owner].add(positionId);

        // If specified, wrap the position
        if (params_.wrapPosition) _safeMint(params_.owner, positionId);

        // Emit the event
        emit PositionCreated(
            positionId,
            params_.owner,
            params_.asset,
            params_.periodMonths,
            params_.remainingDeposit,
            params_.conversionPrice,
            params_.expiry,
            params_.wrapPosition
        );

        return positionId;
    }

    /// @inheritdoc IDepositPositionManager
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
        IDepositPositionManager.MintParams calldata params_
    ) external virtual override permissioned returns (uint256 positionId) {
        // Validate that the owner is not the zero address
        if (params_.owner == address(0)) revert DEPOS_InvalidParams("owner");

        // Validate that the asset is not the zero address
        if (params_.asset == address(0)) revert DEPOS_InvalidParams("asset");

        // Validate that the period is greater than 0
        if (params_.periodMonths == 0) revert DEPOS_InvalidParams("period");

        // Validate that the remaining deposit is greater than 0
        if (params_.remainingDeposit == 0) revert DEPOS_InvalidParams("deposit");

        // Validate that the conversion price is greater than 0
        if (params_.conversionPrice == 0) revert DEPOS_InvalidParams("conversion price");

        // Validate that the conversion expiry is in the future
        if (params_.expiry <= block.timestamp) revert DEPOS_InvalidParams("conversion expiry");

        return
            _create(
                msg.sender, // Calling policy is the operator
                params_
            );
    }

    /// @inheritdoc IDepositPositionManager
    /// @dev        This function reverts if:
    ///             - The caller is not permissioned
    ///             - The position ID is invalid
    ///             - The caller is not the operator that created the position
    ///
    ///             This is a permissioned function that can only be called by approved policies
    function setRemainingDeposit(
        uint256 positionId_,
        uint256 amount_
    )
        external
        virtual
        override
        permissioned
        onlyValidPosition(positionId_)
        onlyPositionOperator(positionId_)
    {
        // Update the remaining deposit of the position
        Position storage position = _positions[positionId_];
        position.remainingDeposit = amount_;

        // Emit the event
        emit PositionRemainingDepositUpdated(positionId_, amount_);
    }

    /// @inheritdoc IDepositPositionManager
    /// @dev        This function reverts if:
    ///             - The caller is not permissioned
    ///             - The position ID is invalid
    ///             - The caller is not the operator that created the position
    ///
    ///             This is a permissioned function that can only be called by approved policies
    function setAdditionalData(
        uint256 positionId_,
        bytes calldata additionalData_
    )
        external
        virtual
        override
        permissioned
        onlyValidPosition(positionId_)
        onlyPositionOperator(positionId_)
    {
        // Update the additional data of the position
        Position storage position = _positions[positionId_];
        position.additionalData = additionalData_;

        // Emit the event
        emit PositionAdditionalDataUpdated(positionId_, additionalData_);
    }

    /// @inheritdoc IDepositPositionManager
    /// @dev        This function reverts if:
    ///             - The caller is not permissioned
    ///             - The caller is not the operator that created the position
    ///             - The amount is 0
    ///             - The amount is greater than the remaining deposit
    ///             - `to_` is the zero address
    ///
    ///             This is a permissioned function that can only be called by approved policies
    function split(
        uint256 positionId_,
        uint256 amount_,
        address to_,
        bool wrap_
    )
        external
        virtual
        override
        permissioned
        onlyValidPosition(positionId_)
        onlyPositionOperator(positionId_)
        returns (uint256 newPositionId)
    {
        Position storage position = _positions[positionId_];

        // Validate that the amount is greater than 0
        if (amount_ == 0) revert DEPOS_InvalidParams("amount");

        // Validate that the amount is less than or equal to the remaining deposit
        if (amount_ > position.remainingDeposit) revert DEPOS_InvalidParams("amount");

        // Validate that the to address is not the zero address
        if (to_ == address(0)) revert DEPOS_InvalidParams("to");

        // Calculate the remaining deposit of the existing position
        uint256 remainingDeposit = position.remainingDeposit - amount_;

        // Update the remaining deposit of the existing position
        position.remainingDeposit = remainingDeposit;

        // Create the new position
        newPositionId = _create(
            position.operator, // Operator is the same as the existing position
            IDepositPositionManager.MintParams({
                owner: to_,
                asset: position.asset,
                periodMonths: position.periodMonths,
                remainingDeposit: amount_,
                conversionPrice: position.conversionPrice,
                expiry: position.expiry,
                wrapPosition: wrap_,
                additionalData: position.additionalData
            })
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

    /// @inheritdoc ERC721
    function tokenURI(uint256 id_) public view virtual override returns (string memory) {
        if (_tokenRenderer == address(0)) return "";

        return IPositionTokenRenderer(_tokenRenderer).tokenURI(address(this), id_);
    }

    /// @inheritdoc ERC721
    /// @dev        This function performs the following:
    ///             - Updates the owner of the position
    ///             - Calls `transferFrom` on the parent contract
    function transferFrom(address from_, address to_, uint256 tokenId_) public override {
        Position storage position = _positions[tokenId_];

        // Validate that the position is valid
        if (position.conversionPrice == 0) revert DEPOS_InvalidPositionId(tokenId_);

        // Validate that the position is wrapped/minted
        if (!position.wrapped) revert DEPOS_NotWrapped(tokenId_);

        // Additional validation performed in super.transferForm():
        // - Approvals
        // - Ownership
        // - Destination address

        // Update the position record
        position.owner = to_;

        // Add to user positions on the destination address
        _userPositions[to_].add(tokenId_);

        // Remove from user positions on the source address
        if (!_userPositions[from_].remove(tokenId_)) revert DEPOS_InvalidPositionId(tokenId_);

        // Call `transferFrom` on the parent contract
        super.transferFrom(from_, to_, tokenId_);
    }

    // ========== TERM INFORMATION ========== //

    /// @inheritdoc IDepositPositionManager
    function getPositionCount() external view virtual override returns (uint256) {
        return _positionCount;
    }

    function _getPosition(uint256 positionId_) internal view returns (Position memory) {
        Position memory position = _positions[positionId_];
        // `mint()` blocks a 0 conversion price, so this should never happen on a valid position
        if (position.conversionPrice == 0) revert DEPOS_InvalidPositionId(positionId_);

        return position;
    }

    /// @inheritdoc IDepositPositionManager
    function getUserPositionIds(
        address user_
    ) external view virtual override returns (uint256[] memory) {
        return _userPositions[user_].values();
    }

    /// @inheritdoc IDepositPositionManager
    /// @dev        This function reverts if:
    ///             - The position ID is invalid
    function getPosition(
        uint256 positionId_
    ) external view virtual override returns (Position memory) {
        return _getPosition(positionId_);
    }

    /// @inheritdoc IDepositPositionManager
    /// @dev        This function reverts if:
    ///             - The position ID is invalid
    ///
    /// @return     isExpired_  Returns true if the conversion expiry timestamp is now or in the past
    function isExpired(uint256 positionId_) external view virtual override returns (bool) {
        return _getPosition(positionId_).expiry <= block.timestamp;
    }

    function _isConvertible(Position memory position_) internal pure returns (bool) {
        return
            position_.conversionPrice != NON_CONVERSION_PRICE &&
            position_.expiry != NON_CONVERSION_EXPIRY;
    }

    /// @inheritdoc IDepositPositionManager
    /// @dev        This function reverts if:
    ///             - The position ID is invalid
    ///
    /// @return     isConvertible_  Returns true if the conversion price is not the maximum value
    function isConvertible(uint256 positionId_) external view virtual override returns (bool) {
        return _isConvertible(_getPosition(positionId_));
    }

    function _previewConvert(
        uint256 amount_,
        uint256 conversionPrice_
    ) internal pure returns (uint256) {
        // amount_ and conversionPrice_ are in the same decimals and cancel each other out
        // The output needs to be in OHM, so we multiply by 1e9
        // This also deliberately rounds down
        return (amount_ * _OHM_SCALE) / conversionPrice_;
    }

    /// @inheritdoc IDepositPositionManager
    function previewConvert(
        uint256 positionId_,
        uint256 amount_
    ) public view virtual override onlyValidPosition(positionId_) returns (uint256) {
        Position memory position = _getPosition(positionId_);

        // If expired, conversion output is 0
        if (position.expiry <= block.timestamp) return 0;

        // If the amount is greater than the remaining deposit, revert
        if (amount_ > position.remainingDeposit) revert DEPOS_InvalidParams("amount");

        // If conversion is not supported, revert
        if (!_isConvertible(position)) revert DEPOS_NotConvertible(positionId_);

        return _previewConvert(amount_, position.conversionPrice);
    }

    // ========== TOKEN URI RENDERER ========== //

    function _setTokenRenderer(address renderer_) internal {
        // If setting to zero address, just clear the renderer
        if (renderer_ == address(0)) {
            _tokenRenderer = address(0);
            emit TokenRendererSet(address(0));
            return;
        }

        // Validate that the renderer contract supports the required interface
        if (!IERC165(renderer_).supportsInterface(type(IPositionTokenRenderer).interfaceId)) {
            revert DEPOS_InvalidRenderer(renderer_);
        }

        // Set the renderer
        _tokenRenderer = renderer_;
        emit TokenRendererSet(renderer_);
    }

    /// @inheritdoc IDepositPositionManager
    /// @dev        This function reverts if:
    ///             - The caller is not permissioned
    ///             - The renderer contract does not implement the required interface
    function setTokenRenderer(address renderer_) external virtual override permissioned {
        _setTokenRenderer(renderer_);
    }

    /// @inheritdoc IDepositPositionManager
    function getTokenRenderer() external view virtual override returns (address) {
        return _tokenRenderer;
    }

    // ========== ERC165 SUPPORT ========== //

    function supportsInterface(bytes4 interfaceId_) public view virtual override returns (bool) {
        return
            interfaceId_ == type(IDepositPositionManager).interfaceId ||
            super.supportsInterface(interfaceId_);
    }

    // ========== MODIFIERS ========== //

    modifier onlyValidPosition(uint256 positionId_) {
        if (_getPosition(positionId_).conversionPrice == 0)
            revert DEPOS_InvalidPositionId(positionId_);
        _;
    }

    modifier onlyPositionOperator(uint256 positionId_) {
        // This validates that the caller is the operator of the position
        if (_getPosition(positionId_).operator != msg.sender) revert DEPOS_NotOperator(positionId_);
        _;
    }

    modifier onlyPositionOwner(uint256 positionId_) {
        // This validates that the caller is the owner of the position
        if (_getPosition(positionId_).owner != msg.sender) revert DEPOS_NotOwner(positionId_);
        _;
    }
}
