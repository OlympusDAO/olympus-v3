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

// Bophades
import {Kernel, Keycode, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/OlympusRoles.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";
import {AssetManager} from "src/libraries/AssetManager.sol";

/// @title Deposit Manager
/// @notice This policy is used to manage deposits on behalf of other protocol contracts. For each deposit, a receipt token is minted 1:1 to the depositor.
/// @dev    This contract combines functionality from a number of inherited contracts, in order to simplify contract implementation.
///         Receipt tokens are ERC6909 tokens in order to reduce gas costs. They can optionally be wrapped to an ERC20 token.
contract DepositManager is Policy, PolicyEnabler, IDepositManager, AssetManager, ERC6909Wrappable {
    using SafeTransferLib for ERC20;

    // ========== CONSTANTS ========== //

    /// @notice The role that is allowed to deposit and withdraw funds
    bytes32 public constant ROLE_DEPOSITOR = "deposit_manager";

    // Tasks
    // [X] Rename to DepositManager
    // [X] Idle/vault strategy for deposited tokens
    // [X] ERC6909 migration
    // [X] Rename to receipt tokens
    // [X] CDTokenSupply to depositor supply
    // [ ] borrowing and repayment of deposited funds
    // [ ] consider shifting away from policy

    // ========== STRUCTS ========== //

    struct DepositConfiguration {
        IERC20 asset;
        uint8 periodMonths;
        uint16 reclaimRate;
    }

    // ========== STATE VARIABLES ========== //

    /// @notice Maps assets and depositors to the number of receipt tokens that have been minted
    /// @dev    This is used to ensure that the receipt tokens are solvent
    ///         As with the AssetManager, deposited asset tokens with different deposit periods are co-mingled.
    mapping(IERC20 => mapping(address => uint256)) internal _receiptTokenSupply;

    /// @notice Maps token ID to the deposit configuration
    mapping(uint256 => DepositConfiguration) internal _depositConfigurations;

    /// @notice Constant equivalent to 100%
    uint16 public constant ONE_HUNDRED_PERCENT = 100e2;

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
    function deposit(
        IERC20 asset_,
        uint8 periodMonths_,
        address depositor_,
        uint256 amount_,
        bool shouldWrap_
    ) external onlyRole(ROLE_DEPOSITOR) returns (uint256 shares) {
        // Deposit into vault
        shares = _depositAsset(asset_, depositor_, amount_);

        // Mint the receipt token to the caller
        uint256 tokenId = getReceiptTokenId(asset_, periodMonths_);
        _mint(depositor_, tokenId, amount_, shouldWrap_);

        return shares;
    }

    /// @inheritdoc IDepositManager
    function claimYield(
        IERC20 asset_,
        uint8 periodMonths_,
        address depositor_,
        uint256 amount_
    )
        external
        onlyRole(ROLE_DEPOSITOR)
        onlyConfiguredAsset(asset_, periodMonths_)
        returns (uint256 shares)
    {
        // Withdraw the funds from the vault
        shares = _withdrawAsset(asset_, depositor_, amount_);

        // The receipt token supply is not adjusted here, as there is no minting/burning of receipt tokens

        // Post-withdrawal, there should be at least as many underlying asset tokens as there are receipt tokens, otherwise the receipt token is not redeemable
        if (_receiptTokenSupply[asset_][msg.sender] > getDepositedAssets(asset_, msg.sender)) {
            revert DepositManager_Insolvent(
                address(asset_),
                _receiptTokenSupply[asset_][msg.sender],
                getDepositedAssets(asset_, msg.sender)
            );
        }

        // Emit an event
        emit ClaimedYield(address(asset_), depositor_, msg.sender, amount_, shares);
        return shares;
    }

    /// @inheritdoc IDepositManager
    function withdraw(
        IERC20 asset_,
        uint8 periodMonths_,
        address depositor_,
        address recipient_,
        uint256 amount_,
        bool wrapped_
    ) external onlyRole(ROLE_DEPOSITOR) returns (uint256 shares) {
        // Burn the receipt token from the depositor
        _burn(depositor_, getReceiptTokenId(asset_, periodMonths_), amount_, wrapped_);

        // Update the asset tracking for the caller (operator)
        _receiptTokenSupply[asset_][msg.sender] -= amount_;

        // Withdraw the funds from the vault to the recipient
        shares = _withdrawAsset(asset_, recipient_, amount_);

        return shares;
    }

    // TODO add reclaim

    // ========== TOKEN FUNCTIONS ========== //

    /// @inheritdoc IDepositManager
    function getReceiptTokenId(
        IERC20 asset_,
        uint8 periodMonths_
    ) public pure override returns (uint256) {
        return uint256(keccak256(abi.encode(asset_, periodMonths_)));
    }

    /// @inheritdoc IDepositManager
    function getAssetFromTokenId(uint256 tokenId_) public view override returns (IERC20, uint8) {
        return (
            _depositConfigurations[tokenId_].asset,
            _depositConfigurations[tokenId_].periodMonths
        );
    }

    // ========== TOKEN MANAGEMENT ========== //

    /// @inheritdoc IDepositManager
    function isConfiguredAsset(
        IERC20 asset_,
        uint8 periodMonths_
    ) public view override returns (bool) {
        return
            address(_depositConfigurations[getReceiptTokenId(asset_, periodMonths_)].asset) !=
            address(0);
    }

    modifier onlyConfiguredAsset(IERC20 asset_, uint8 periodMonths_) {
        if (!isConfiguredAsset(asset_, periodMonths_))
            revert DepositManager_AssetNotConfigured(address(asset_), periodMonths_);
        _;
    }

    function _truncate32(string memory str_) internal pure returns (string memory) {
        bytes32 nameBytes = bytes32(abi.encodePacked(str_));

        return string(abi.encodePacked(nameBytes));
    }

    function _setReceiptTokenData(
        IERC20 asset_,
        uint8 periodMonths_
    ) internal returns (uint256 tokenId) {
        // Generate a unique token ID for the token and deposit period combination
        tokenId = getReceiptTokenId(asset_, periodMonths_);

        // Set the metadata for the receipt token
        _setName(
            tokenId,
            _truncate32(
                string.concat(asset_.name(), " Receipt - ", uint2str(periodMonths_), " months")
            )
        );

        _setSymbol(
            tokenId,
            _truncate32(string.concat("r", asset_.symbol(), "-", uint2str(periodMonths_), "m"))
        );

        _setDecimals(tokenId, asset_.decimals());

        // Set additional metadata
        bytes memory additionalMetadata = abi.encodePacked(
            address(this), // Owner
            address(asset_), // Asset
            periodMonths_ // Period Months
        );
        _tokenMetadataAdditional[tokenId] = additionalMetadata;

        emit ReceiptTokenConfigured(tokenId, address(asset_), periodMonths_);
        return tokenId;
    }

    /// @dev Assumes that the token ID is valid
    function _setDepositReclaimRate(
        IERC20 asset_,
        uint8 periodMonths_,
        uint16 reclaimRate_
    ) internal {
        if (reclaimRate_ > ONE_HUNDRED_PERCENT) revert DepositManager_OutOfBounds();

        _depositConfigurations[getReceiptTokenId(asset_, periodMonths_)].reclaimRate = reclaimRate_;
        emit ReclaimRateUpdated(address(asset_), periodMonths_, reclaimRate_);
    }

    /// @inheritdoc IDepositManager
    function configureAsset(
        IERC20 asset_,
        IERC4626 vault_,
        uint8 periodMonths_,
        uint16 reclaimRate_
    ) external onlyEnabled onlyAdminRole returns (uint256 receiptTokenId) {
        // Configure the asset in the AssetManager
        _configureAsset(asset_, address(vault_));

        // Configure the ERC6909 receipt token
        receiptTokenId = _setReceiptTokenData(asset_, periodMonths_);

        // Set the deposit configuration
        _depositConfigurations[receiptTokenId] = DepositConfiguration({
            asset: asset_,
            periodMonths: periodMonths_,
            reclaimRate: 0
        });
        // Set the reclaim rate (which does validation and emits an event)
        _setDepositReclaimRate(asset_, periodMonths_, reclaimRate_);

        return receiptTokenId;
    }

    /// @inheritdoc IDepositManager
    function setDepositReclaimRate(
        IERC20 asset_,
        uint8 periodMonths_,
        uint16 reclaimRate_
    ) external onlyEnabled onlyAdminRole onlyConfiguredAsset(asset_, periodMonths_) {
        _setDepositReclaimRate(asset_, periodMonths_, reclaimRate_);
    }

    /// @inheritdoc IDepositManager
    function getDepositReclaimRate(
        IERC20 asset_,
        uint8 periodMonths_
    ) external view returns (uint16) {
        return _depositConfigurations[getReceiptTokenId(asset_, periodMonths_)].reclaimRate;
    }
}
