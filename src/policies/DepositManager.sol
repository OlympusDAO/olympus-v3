// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.20;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IDepositManager} from "src/policies/interfaces/IDepositManager.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";

// Libraries
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC6909Wrappable} from "src/libraries/ERC6909Wrappable.sol";
import {uint2str} from "src/libraries/Uint2Str.sol";
import {CloneableReceiptToken} from "src/libraries/CloneableReceiptToken.sol";
import {String} from "src/libraries/String.sol";

// Bophades
import {Kernel, Keycode, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/OlympusRoles.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";
import {BaseAssetManager} from "src/bases/BaseAssetManager.sol";

/// @title Deposit Manager
/// @notice This policy is used to manage deposits on behalf of other protocol contracts. For each deposit, a receipt token is minted 1:1 to the depositor.
/// @dev    This contract combines functionality from a number of inherited contracts, in order to simplify contract implementation.
///         Receipt tokens are ERC6909 tokens in order to reduce gas costs. They can optionally be wrapped to an ERC20 token.
contract DepositManager is
    Policy,
    PolicyEnabler,
    IDepositManager,
    BaseAssetManager,
    ERC6909Wrappable
{
    using SafeTransferLib for ERC20;
    using String for string;

    // ========== CONSTANTS ========== //

    /// @notice The role that is allowed to deposit and withdraw funds
    bytes32 public constant ROLE_DEPOSIT_OPERATOR = "deposit_operator";

    // Tasks
    // [X] Rename to DepositManager
    // [X] Idle/vault strategy for deposited tokens
    // [X] ERC6909 migration
    // [X] Rename to receipt tokens
    // [X] CDTokenSupply to depositor supply
    // [ ] borrowing and repayment of deposited funds
    // [X] consider shifting away from policy
    // [X] consider if asset configuration should require a different role

    // ========== STATE VARIABLES ========== //

    /// @notice Maps assets and operators to the number of receipt tokens that have been minted
    /// @dev    This is used to ensure that the receipt tokens are solvent
    ///         As with the BaseAssetManager, deposited asset tokens with different deposit periods are co-mingled.
    mapping(IERC20 asset => mapping(address operator => uint256 receiptTokenSupply))
        internal _assetLiabilities;

    /// @notice Maps token ID to the deposit configuration
    mapping(uint256 tokenId => DepositConfiguration) internal _depositConfigurations;

    /// @notice Array of deposit token IDs
    uint256[] internal _depositTokenIds;

    /// @notice Constant equivalent to 100%
    uint16 public constant ONE_HUNDRED_PERCENT = 100e2;

    // ========== MODIFIERS ========== //

    /// @notice Reverts if the deposit asset is not configured
    modifier onlyDepositAsset(IERC20 asset_, uint8 depositPeriod_) {
        if (!isDepositAsset(asset_, depositPeriod_))
            revert DepositManager_AssetNotConfigured(address(asset_), depositPeriod_);
        _;
    }

    // ========== CONSTRUCTOR ========== //

    constructor(
        address kernel_,
        address erc20Implementation_
    ) Policy(Kernel(kernel_)) ERC6909Wrappable(address(new CloneableReceiptToken())) {
        // Disabled by default by PolicyEnabler
    }

    // ========== Policy Configuration ========== //

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("ROLES");

        ROLES = ROLESv1(getModuleAddress(dependencies[0]));
    }

    /// @inheritdoc Policy
    function requestPermissions()
        external
        view
        override
        returns (Permissions[] memory permissions)
    {}

    function VERSION() external pure returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;

        return (major, minor);
    }

    // ========== DEPOSIT/WITHDRAW FUNCTIONS ========== //

    /// @inheritdoc IDepositManager
    /// @dev        This function is only callable by addresses with the deposit operator role
    function deposit(
        IERC20 asset_,
        uint8 depositPeriod_,
        address depositor_,
        uint256 amount_,
        bool shouldWrap_
    ) external onlyRole(ROLE_DEPOSIT_OPERATOR) returns (uint256 shares) {
        // Deposit into vault
        // This will revert if the asset is not configured
        shares = _depositAsset(asset_, depositor_, amount_);

        // Mint the receipt token to the caller
        uint256 tokenId = getReceiptTokenId(asset_, depositPeriod_);
        _mint(depositor_, tokenId, amount_, shouldWrap_);

        return shares;
    }

    /// @inheritdoc IDepositManager
    /// @dev        This function is only callable by addresses with the deposit operator role
    function claimYield(
        IERC20 asset_,
        address recipient_,
        uint256 amount_
    ) external onlyRole(ROLE_DEPOSIT_OPERATOR) onlyConfiguredAsset(asset_) {
        // Withdraw the funds from the vault
        _withdrawAsset(asset_, recipient_, amount_);

        // The receipt token supply is not adjusted here, as there is no minting/burning of receipt tokens

        // Post-withdrawal, there should be at least as many underlying asset tokens as there are receipt tokens, otherwise the receipt token is not redeemable
        (, uint256 depositedSharesInAssets) = getOperatorAssets(asset_, msg.sender);
        if (_assetLiabilities[asset_][msg.sender] > depositedSharesInAssets) {
            revert DepositManager_Insolvent(
                address(asset_),
                _assetLiabilities[asset_][msg.sender],
                depositedSharesInAssets
            );
        }

        // Emit an event
        emit ClaimedYield(address(asset_), recipient_, msg.sender, amount_);
    }

    /// @inheritdoc IDepositManager
    /// @dev        This function is only callable by addresses with the deposit operator role
    function withdraw(
        IERC20 asset_,
        uint8 depositPeriod_,
        address depositor_,
        address recipient_,
        uint256 amount_,
        bool wrapped_
    ) external onlyRole(ROLE_DEPOSIT_OPERATOR) returns (uint256 shares) {
        // Burn the receipt token from the depositor
        _burn(depositor_, getReceiptTokenId(asset_, depositPeriod_), amount_, wrapped_);

        // Update the asset liabilities for the caller (operator)
        _assetLiabilities[asset_][msg.sender] -= amount_;

        // Withdraw the funds from the vault to the recipient
        // This will revert if the asset is not configured
        shares = _withdrawAsset(asset_, recipient_, amount_);

        return shares;
    }

    // ========== TOKEN FUNCTIONS ========== //

    /// @inheritdoc IDepositManager
    function getReceiptTokenId(
        IERC20 asset_,
        uint8 depositPeriod_
    ) public pure override returns (uint256) {
        return uint256(keccak256(abi.encode(asset_, depositPeriod_)));
    }

    /// @inheritdoc IDepositManager
    function getAssetFromReceiptTokenId(
        uint256 tokenId_
    ) public view override returns (IERC20, uint8) {
        return (
            _depositConfigurations[tokenId_].asset,
            _depositConfigurations[tokenId_].depositPeriod
        );
    }

    // ========== DEPOSIT CONFIGURATION ========== //

    /// @inheritdoc IDepositManager
    function isDepositAsset(
        IERC20 asset_,
        uint8 depositPeriod_
    ) public view override returns (bool) {
        return
            address(_depositConfigurations[getReceiptTokenId(asset_, depositPeriod_)].asset) !=
            address(0);
    }

    function _setReceiptTokenData(
        IERC20 asset_,
        uint8 depositPeriod_
    ) internal returns (uint256 tokenId) {
        // Generate a unique token ID for the token and deposit period combination
        tokenId = getReceiptTokenId(asset_, depositPeriod_);

        // Set the metadata for the receipt token
        _setName(
            tokenId,
            string
                .concat(asset_.name(), " Receipt - ", uint2str(depositPeriod_), " months")
                .truncate32()
        );

        _setSymbol(
            tokenId,
            string.concat("r", asset_.symbol(), "-", uint2str(depositPeriod_), "m").truncate32()
        );

        _setDecimals(tokenId, asset_.decimals());

        // Set additional metadata
        bytes memory additionalMetadata = abi.encodePacked(
            address(this), // Owner
            address(asset_), // Asset
            depositPeriod_ // Deposit Period
        );
        _tokenMetadataAdditional[tokenId] = additionalMetadata;

        emit ReceiptTokenConfigured(tokenId, address(asset_), depositPeriod_);
        return tokenId;
    }

    /// @dev Assumes that the token ID is valid
    function _setDepositReclaimRate(
        IERC20 asset_,
        uint8 depositPeriod_,
        uint16 reclaimRate_
    ) internal {
        if (reclaimRate_ > ONE_HUNDRED_PERCENT) revert DepositManager_OutOfBounds();

        _depositConfigurations[getReceiptTokenId(asset_, depositPeriod_)]
            .reclaimRate = reclaimRate_;
        emit ReclaimRateUpdated(address(asset_), depositPeriod_, reclaimRate_);
    }

    /// @inheritdoc IDepositManager
    /// @dev        This function is only callable by the manager or admin role
    function configureDeposit(
        IERC20 asset_,
        IERC4626 vault_,
        uint8 depositPeriod_,
        uint16 reclaimRate_
    ) external onlyEnabled onlyManagerOrAdminRole returns (uint256 receiptTokenId) {
        // Configure the asset in the BaseAssetManager
        _configureAsset(asset_, address(vault_));

        // Configure the ERC6909 receipt token
        receiptTokenId = _setReceiptTokenData(asset_, depositPeriod_);

        // Set the deposit configuration
        _depositConfigurations[receiptTokenId] = DepositConfiguration({
            asset: asset_,
            depositPeriod: depositPeriod_,
            reclaimRate: 0
        });

        // Add the deposit token ID to the array
        _depositTokenIds.push(receiptTokenId);

        // Set the reclaim rate (which does validation and emits an event)
        _setDepositReclaimRate(asset_, depositPeriod_, reclaimRate_);

        return receiptTokenId;
    }

    /// @inheritdoc IDepositManager
    function getDepositAssets() external view returns (DepositConfiguration[] memory) {
        DepositConfiguration[] memory depositAssets = new DepositConfiguration[](
            _depositTokenIds.length
        );
        for (uint256 i; i < _depositTokenIds.length; ++i) {
            depositAssets[i] = _depositConfigurations[_depositTokenIds[i]];
        }
        return depositAssets;
    }

    /// @inheritdoc IDepositManager
    function getAssetLiabilities(IERC20 asset_, address operator_) external view returns (uint256) {
        return _assetLiabilities[asset_][operator_];
    }

    /// @inheritdoc IDepositManager
    /// @dev        This function is only callable by the manager or admin role
    function setDepositReclaimRate(
        IERC20 asset_,
        uint8 depositPeriod_,
        uint16 reclaimRate_
    ) external onlyEnabled onlyManagerOrAdminRole onlyDepositAsset(asset_, depositPeriod_) {
        _setDepositReclaimRate(asset_, depositPeriod_, reclaimRate_);
    }

    /// @inheritdoc IDepositManager
    function getDepositReclaimRate(
        IERC20 asset_,
        uint8 depositPeriod_
    ) external view returns (uint16) {
        return _depositConfigurations[getReceiptTokenId(asset_, depositPeriod_)].reclaimRate;
    }

    // ========== RECEIPT TOKEN FUNCTIONS ========== //

    /// @inheritdoc IDepositManager
    /// @dev        This is the same as the ERC6909 name() function, but is included for consistency
    function getReceiptTokenName(uint256 tokenId_) external view override returns (string memory) {
        return name(tokenId_);
    }

    /// @inheritdoc IDepositManager
    /// @dev        This is the same as the ERC6909 symbol() function, but is included for consistency
    function getReceiptTokenSymbol(
        uint256 tokenId_
    ) external view override returns (string memory) {
        return symbol(tokenId_);
    }

    /// @inheritdoc IDepositManager
    /// @dev        This is the same as the ERC6909 decimals() function, but is included for consistency
    function getReceiptTokenDecimals(uint256 tokenId_) external view override returns (uint8) {
        return decimals(tokenId_);
    }

    /// @inheritdoc IDepositManager
    function getReceiptTokenOwner(uint256) external view override returns (address) {
        return address(this);
    }

    /// @inheritdoc IDepositManager
    function getReceiptTokenAsset(uint256 tokenId_) external view override returns (IERC20) {
        return _depositConfigurations[tokenId_].asset;
    }

    /// @inheritdoc IDepositManager
    function getReceiptTokenDepositPeriod(uint256 tokenId_) external view override returns (uint8) {
        return _depositConfigurations[tokenId_].depositPeriod;
    }
}
