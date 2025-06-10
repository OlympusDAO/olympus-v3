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

/// @title Convertible Deposit Token Manager
/// @notice This policy is used to manage convertible deposit ("CD") tokens on behalf of deposit facilities. It is meant to be used by the facilities, and is not an end-user policy.
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

    // ========== STATE VARIABLES ========== //

    /// @notice Maps assets and depositors to the number of receipt tokens that have been minted
    /// @dev    This is used to ensure that the receipt tokens are solvent
    mapping(address => mapping(address => uint256)) internal _receiptTokenSupply;

    /// @notice Maps assets and deposit periods to the reclaim rate
    mapping(address => mapping(uint8 => uint16)) internal _depositReclaimRates;

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
        shares = _depositAsset(address(asset_), depositor_, amount_);

        // Mint the receipt token to the caller
        uint256 tokenId = getReceiptTokenId(address(asset_), periodMonths_);
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
        shares = _withdrawAsset(address(asset_), depositor_, amount_);

        // The receipt token supply is not adjusted here, as there is no minting/burning of receipt tokens

        // Post-withdrawal, there should be at least as many underlying asset tokens as there are receipt tokens, otherwise the receipt token is not redeemable
        if (
            _receiptTokenSupply[address(asset_)][msg.sender] >
            getDepositedAssets(address(asset_), msg.sender)
        ) {
            revert DepositManager_Insolvent(
                address(asset_),
                _receiptTokenSupply[address(asset_)][msg.sender],
                getDepositedAssets(address(asset_), msg.sender)
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
        uint256 amount_,
        bool wrapped_
    ) external onlyRole(ROLE_DEPOSITOR) returns (uint256 shares) {
        // Burn the receipt token from the caller
        _burn(depositor_, getReceiptTokenId(address(asset_), periodMonths_), amount_, wrapped_);

        // Update the asset tracking for the caller (operator)
        _receiptTokenSupply[address(asset_)][msg.sender] -= amount_;

        // Withdraw the funds from the vault
        shares = _withdrawAsset(address(asset_), depositor_, amount_);

        return shares;
    }

    // ========== TOKEN FUNCTIONS ========== //

    /// @notice Generates a unique token ID for a token and deposit period combination
    ///
    /// @param  asset_          The address of the asset
    /// @param  periodMonths_   The period of the CD token
    /// @return tokenId         The unique token ID
    function getReceiptTokenId(address asset_, uint8 periodMonths_) public pure returns (uint256) {
        return uint256(keccak256(abi.encode(asset_, periodMonths_)));
    }

    // ========== TOKEN MANAGEMENT ========== //

    /// @inheritdoc IDepositManager
    function isConfiguredAsset(IERC20 asset_, uint8 periodMonths_) public view returns (bool) {
        return isValidTokenId(getReceiptTokenId(address(asset_), periodMonths_));
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
        tokenId = getReceiptTokenId(address(asset_), periodMonths_);

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

    function _setReclaimRate(IERC20 asset_, uint8 periodMonths_, uint16 reclaimRate_) internal {
        if (reclaimRate_ > ONE_HUNDRED_PERCENT) revert DepositManager_OutOfBounds();

        _depositReclaimRates[address(asset_)][periodMonths_] = reclaimRate_;
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
        _configureAsset(address(asset_), address(vault_));

        // Configure the ERC6909 receipt token
        receiptTokenId = _setReceiptTokenData(asset_, periodMonths_);

        // Set the reclaim rate
        _setReclaimRate(asset_, periodMonths_, reclaimRate_);

        return receiptTokenId;
    }

    /// @inheritdoc IDepositManager
    function setDepositReclaimRate(
        IERC20 asset_,
        uint8 periodMonths_,
        uint16 reclaimRate_
    ) external onlyEnabled onlyAdminRole onlyConfiguredAsset(asset_, periodMonths_) {
        _setReclaimRate(asset_, periodMonths_, reclaimRate_);
    }

    /// @inheritdoc IDepositManager
    function getDepositReclaimRate(
        IERC20 asset_,
        uint8 periodMonths_
    ) external view returns (uint16) {
        return _depositReclaimRates[address(asset_)][periodMonths_];
    }
}
