// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.20;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IDepositManager} from "src/policies/interfaces/IDepositManager.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";

// Libraries
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";
import {SafeTransferLib} from "@solmate-6.2.0/utils/SafeTransferLib.sol";
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
    // [X] ReceiptTokenSupply to depositor supply
    // [ ] borrowing and repayment of deposited funds
    // [X] consider shifting away from policy
    // [X] consider if asset configuration should require a different role

    // ========== STATE VARIABLES ========== //

    /// @notice Maps asset liabilities key to the number of receipt tokens that have been minted
    /// @dev    This is used to ensure that the receipt tokens are solvent
    ///         As with the BaseAssetManager, deposited asset tokens with different deposit periods are co-mingled.
    mapping(bytes32 key => uint256 receiptTokenSupply) internal _assetLiabilities;

    /// @notice Maps token ID to the asset period
    mapping(uint256 tokenId => AssetPeriod) internal _assetPeriods;

    /// @notice Array of receipt token IDs
    uint256[] internal _receiptTokenIds;

    /// @notice Constant equivalent to 100%
    uint16 public constant ONE_HUNDRED_PERCENT = 100e2;

    // ========== MODIFIERS ========== //

    /// @notice Reverts if the asset period is not configured
    modifier onlyAssetPeriodExists(IERC20 asset_, uint8 depositPeriod_) {
        if (address(_assetPeriods[getReceiptTokenId(asset_, depositPeriod_)].asset) == address(0)) {
            revert DepositManager_InvalidAssetPeriod(address(asset_), depositPeriod_);
        }
        _;
    }

    /// @notice Reverts if the asset period is not enabled
    modifier onlyAssetPeriodEnabled(IERC20 asset_, uint8 depositPeriod_) {
        AssetPeriod memory assetPeriod = _assetPeriods[getReceiptTokenId(asset_, depositPeriod_)];
        if (assetPeriod.asset == address(0)) {
            revert DepositManager_InvalidAssetPeriod(address(asset_), depositPeriod_);
        }

        if (!assetPeriod.isEnabled) {
            revert DepositManager_AssetPeriodDisabled(address(asset_), depositPeriod_);
        }
        _;
    }

    // ========== CONSTRUCTOR ========== //

    constructor(
        address kernel_
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
        DepositParams calldata params_
    )
        external
        onlyEnabled
        onlyRole(ROLE_DEPOSIT_OPERATOR)
        onlyAssetPeriodEnabled(params_.asset, params_.depositPeriod)
        returns (uint256 receiptTokenId, uint256 actualAmount)
    {
        // Deposit into vault
        // This will revert if the asset is not configured
        (actualAmount, ) = _depositAsset(params_.asset, params_.depositor, params_.amount);

        // Mint the receipt token to the caller
        receiptTokenId = getReceiptTokenId(params_.asset, params_.depositPeriod);
        _mint(params_.depositor, receiptTokenId, actualAmount, params_.shouldWrap);

        // Update the asset liabilities for the caller (operator)
        _assetLiabilities[_getAssetLiabilitiesKey(params_.asset, msg.sender)] += actualAmount;

        return (receiptTokenId, actualAmount);
    }

    /// @inheritdoc IDepositManager
    function maxClaimYield(IERC20 asset_, address operator_) external view returns (uint256) {
        (, uint256 depositedSharesInAssets) = getOperatorAssets(asset_, operator_);
        uint256 operatorLiabilities = _assetLiabilities[_getAssetLiabilitiesKey(asset_, operator_)];

        // Avoid reverting
        // Adjust by 1 to account for the different behaviour in ERC4626.previewRedeem and ERC4626.previewWithdraw, which could leave the receipt token insolvent
        if (depositedSharesInAssets < operatorLiabilities + 1) return 0;

        return depositedSharesInAssets - operatorLiabilities - 1;
    }

    /// @inheritdoc IDepositManager
    /// @dev        This function is only callable by addresses with the deposit operator role
    function claimYield(
        IERC20 asset_,
        address recipient_,
        uint256 amount_
    ) external onlyEnabled onlyRole(ROLE_DEPOSIT_OPERATOR) onlyConfiguredAsset(asset_) {
        // Withdraw the funds from the vault
        (, uint256 actualAmount) = _withdrawAsset(asset_, recipient_, amount_);

        // The receipt token supply is not adjusted here, as there is no minting/burning of receipt tokens

        // Post-withdrawal, there should be at least as many underlying asset tokens as there are receipt tokens, otherwise the receipt token is not redeemable
        (, uint256 depositedSharesInAssets) = getOperatorAssets(asset_, msg.sender);
        bytes32 assetLiabilitiesKey = _getAssetLiabilitiesKey(asset_, msg.sender);
        if (_assetLiabilities[assetLiabilitiesKey] > depositedSharesInAssets) {
            revert DepositManager_Insolvent(
                address(asset_),
                _assetLiabilities[assetLiabilitiesKey]
            );
        }

        // Emit an event
        emit ClaimedYield(address(asset_), recipient_, msg.sender, actualAmount);
    }

    /// @inheritdoc IDepositManager
    /// @dev        This function is only callable by addresses with the deposit operator role
    function withdraw(
        WithdrawParams calldata params_
    ) external onlyEnabled onlyRole(ROLE_DEPOSIT_OPERATOR) returns (uint256 actualAmount) {
        // Validate that the recipient is not the zero address
        if (params_.recipient == address(0)) revert DepositManager_ZeroAddress();

        // Burn the receipt token from the depositor
        // Will revert if the asset configuration is not valid/invalid receipt token ID
        _burn(
            params_.depositor,
            getReceiptTokenId(params_.asset, params_.depositPeriod),
            params_.amount,
            params_.isWrapped
        );

        // Update the asset liabilities for the caller (operator)
        _assetLiabilities[_getAssetLiabilitiesKey(params_.asset, msg.sender)] -= params_.amount;

        // Withdraw the funds from the vault to the recipient
        // This will revert if the asset is not configured
        (, actualAmount) = _withdrawAsset(params_.asset, params_.recipient, params_.amount);

        return actualAmount;
    }

    /// @inheritdoc IDepositManager
    function getOperatorLiabilities(
        IERC20 asset_,
        address operator_
    ) external view returns (uint256) {
        return _assetLiabilities[_getAssetLiabilitiesKey(asset_, operator_)];
    }

    /// @notice Get the key for the asset liabilities mapping
    /// @dev    The key is the keccak256 of the asset address and the operator address
    function _getAssetLiabilitiesKey(
        IERC20 asset_,
        address operator_
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(address(asset_), operator_));
    }

    // ========== ASSET PERIOD ========== //

    /// @inheritdoc IDepositManager
    function isAssetPeriod(
        IERC20 asset_,
        uint8 depositPeriod_
    ) public view override returns (bool isConfigured, bool isEnabled) {
        uint256 receiptTokenId = getReceiptTokenId(asset_, depositPeriod_);
        isConfigured = address(_assetPeriods[receiptTokenId].asset) != address(0);
        isEnabled = _assetPeriods[receiptTokenId].isEnabled;

        return (isConfigured, isEnabled);
    }

    /// @inheritdoc IDepositManager
    /// @dev        This function is only callable by the manager or admin role
    function configureAssetVault(
        IERC20 asset_,
        IERC4626 vault_
    ) external onlyEnabled onlyManagerOrAdminRole {
        _configureAsset(asset_, address(vault_));
    }

    /// @inheritdoc IDepositManager
    /// @dev        This function is only callable by the manager or admin role
    function addAssetPeriod(
        IERC20 asset_,
        uint8 depositPeriod_,
        uint16 reclaimRate_
    )
        external
        onlyEnabled
        onlyManagerOrAdminRole
        onlyConfiguredAsset(asset_)
        returns (uint256 receiptTokenId)
    {
        // Validate that the deposit period is not 0
        if (depositPeriod_ == 0) revert DepositManager_OutOfBounds();

        // Validate that the asset and deposit period combination is not already configured
        (bool isConfigured, ) = isAssetPeriod(asset_, depositPeriod_);
        if (isConfigured) {
            revert DepositManager_AssetPeriodExists(address(asset_), depositPeriod_);
        }

        // Configure the ERC6909 receipt token
        receiptTokenId = _setReceiptTokenData(asset_, depositPeriod_);

        // Set the asset period
        _assetPeriods[receiptTokenId] = AssetPeriod({
            isEnabled: true,
            depositPeriod: depositPeriod_,
            reclaimRate: 0,
            asset: address(asset_)
        });

        // Add the deposit token ID to the array
        _receiptTokenIds.push(receiptTokenId);

        // Set the reclaim rate (which does validation and emits an event)
        _setAssetPeriodReclaimRate(asset_, depositPeriod_, reclaimRate_);

        // Emit event
        emit AssetPeriodConfigured(receiptTokenId, address(asset_), depositPeriod_);

        return receiptTokenId;
    }

    /// @inheritdoc IDepositManager
    /// @dev        This function is only callable by the manager or admin role
    function enableAssetPeriod(
        IERC20 asset_,
        uint8 depositPeriod_
    ) external onlyEnabled onlyManagerOrAdminRole onlyAssetPeriodExists(asset_, depositPeriod_) {
        // Validate that the asset period is disabled
        uint256 tokenId = getReceiptTokenId(asset_, depositPeriod_);
        if (_assetPeriods[tokenId].isEnabled) {
            revert DepositManager_AssetPeriodEnabled(address(asset_), depositPeriod_);
        }

        // Enable the asset period
        _assetPeriods[getReceiptTokenId(asset_, depositPeriod_)].isEnabled = true;

        // Emit event
        emit AssetPeriodEnabled(tokenId, address(asset_), depositPeriod_);
    }

    /// @inheritdoc IDepositManager
    /// @dev        This function is only callable by the manager or admin role
    function disableAssetPeriod(
        IERC20 asset_,
        uint8 depositPeriod_
    ) external onlyEnabled onlyManagerOrAdminRole onlyAssetPeriodExists(asset_, depositPeriod_) {
        // Validate that the asset period is enabled
        uint256 tokenId = getReceiptTokenId(asset_, depositPeriod_);
        if (!_assetPeriods[tokenId].isEnabled) {
            revert DepositManager_AssetPeriodDisabled(address(asset_), depositPeriod_);
        }

        // Disable the asset period
        _assetPeriods[getReceiptTokenId(asset_, depositPeriod_)].isEnabled = false;

        // Emit event
        emit AssetPeriodDisabled(tokenId, address(asset_), depositPeriod_);
    }

    /// @inheritdoc IDepositManager
    function getAssetPeriods() external view returns (AssetPeriod[] memory) {
        AssetPeriod[] memory depositAssets = new AssetPeriod[](_receiptTokenIds.length);
        for (uint256 i; i < _receiptTokenIds.length; ++i) {
            depositAssets[i] = _assetPeriods[_receiptTokenIds[i]];
        }
        return depositAssets;
    }

    /// @inheritdoc IDepositManager
    function getAssetPeriod(uint256 tokenId_) public view override returns (AssetPeriod memory) {
        return _assetPeriods[tokenId_];
    }

    /// @inheritdoc IDepositManager
    function getAssetPeriod(
        IERC20 asset_,
        uint8 depositPeriod_
    ) public view override returns (AssetPeriod memory) {
        return _assetPeriods[getReceiptTokenId(asset_, depositPeriod_)];
    }

    // ========== DEPOSIT RECLAIM RATE ========== //

    /// @dev Assumes that the token ID is valid
    function _setAssetPeriodReclaimRate(
        IERC20 asset_,
        uint8 depositPeriod_,
        uint16 reclaimRate_
    ) internal {
        if (reclaimRate_ > ONE_HUNDRED_PERCENT) revert DepositManager_OutOfBounds();

        _assetPeriods[getReceiptTokenId(asset_, depositPeriod_)].reclaimRate = reclaimRate_;
        emit AssetPeriodReclaimRateSet(address(asset_), depositPeriod_, reclaimRate_);
    }

    /// @inheritdoc IDepositManager
    /// @dev        This function is only callable by the manager or admin role
    function setAssetPeriodReclaimRate(
        IERC20 asset_,
        uint8 depositPeriod_,
        uint16 reclaimRate_
    ) external onlyEnabled onlyManagerOrAdminRole onlyAssetPeriodExists(asset_, depositPeriod_) {
        _setAssetPeriodReclaimRate(asset_, depositPeriod_, reclaimRate_);
    }

    /// @inheritdoc IDepositManager
    function getAssetPeriodReclaimRate(
        IERC20 asset_,
        uint8 depositPeriod_
    ) external view returns (uint16) {
        return _assetPeriods[getReceiptTokenId(asset_, depositPeriod_)].reclaimRate;
    }

    // ========== RECEIPT TOKEN FUNCTIONS ========== //

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

        return tokenId;
    }

    /// @inheritdoc IDepositManager
    function getReceiptTokenId(
        IERC20 asset_,
        uint8 depositPeriod_
    ) public pure override returns (uint256) {
        return uint256(keccak256(abi.encode(asset_, depositPeriod_)));
    }

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
        return IERC20(_assetPeriods[tokenId_].asset);
    }

    /// @inheritdoc IDepositManager
    function getReceiptTokenDepositPeriod(uint256 tokenId_) external view override returns (uint8) {
        return _assetPeriods[tokenId_].depositPeriod;
    }
}
