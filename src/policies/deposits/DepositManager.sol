// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.20;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IReceiptTokenManager} from "src/policies/interfaces/deposits/IReceiptTokenManager.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";

// Libraries
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";
import {EnumerableSet} from "@openzeppelin-5.3.0/utils/structs/EnumerableSet.sol";
import {TransferHelper} from "src/libraries/TransferHelper.sol";

// Bophades
import {Kernel, Keycode, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/OlympusRoles.sol";
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";
import {BaseAssetManager} from "src/bases/BaseAssetManager.sol";
import {ReceiptTokenManager} from "src/policies/deposits/ReceiptTokenManager.sol";

/// @title Deposit Manager
/// @notice This policy manages deposits and withdrawals for Olympus protocol contracts
/// @dev    Key Features:
///         - ERC6909 receipt tokens with optional ERC20 wrapping, using ReceiptTokenManager
///         - Operator isolation preventing cross-operator fund access
///         - Borrowing functionality
///         - Configurable reclaim rates for risk management
contract DepositManager is Policy, PolicyEnabler, IDepositManager, BaseAssetManager {
    using TransferHelper for ERC20;
    using EnumerableSet for EnumerableSet.UintSet;

    // ========== CONSTANTS ========== //

    /// @notice The role that is allowed to deposit and withdraw funds
    bytes32 public constant ROLE_DEPOSIT_OPERATOR = "deposit_operator";

    /// @notice The receipt token manager for creating receipt tokens
    ReceiptTokenManager internal immutable _RECEIPT_TOKEN_MANAGER;

    // ========== MODULES ==========

    /// @notice The Treasury module
    TRSRYv1 public TRSRY;

    // ========== STATE VARIABLES ========== //

    /// @notice Maps asset liabilities key to the number of receipt tokens that have been minted
    /// @dev    This is used to ensure that the receipt tokens are solvent
    ///         As with the BaseAssetManager, deposited asset tokens with different deposit periods are co-mingled.
    mapping(bytes32 key => uint256 receiptTokenSupply) internal _assetLiabilities;

    /// @notice Maps token ID to the asset period
    mapping(uint256 tokenId => AssetPeriod) internal _assetPeriods;

    /// @notice Set of token IDs that this DepositManager owns
    EnumerableSet.UintSet internal _ownedTokenIds;

    /// @notice Constant equivalent to 100%
    uint16 public constant ONE_HUNDRED_PERCENT = 100e2;

    /// @notice Maps operator address to its name
    mapping(address operator => bytes3 name) internal _operatorToName;

    /// @notice A set of operator names
    /// @dev    This contains unique values
    mapping(bytes3 name => bool isRegistered) internal _operatorNames;

    // ========== BORROWING STATE VARIABLES ========== //

    /// @notice Maps asset-operator key to current borrowed amounts
    /// @dev    The key is the keccak256 of the asset address and the operator address
    mapping(bytes32 key => uint256 borrowedAmount) internal _borrowedAmounts;

    // ========== MODIFIERS ========== //

    /// @notice Reverts if the asset period is not configured
    modifier onlyAssetPeriodExists(
        IERC20 asset_,
        uint8 depositPeriod_,
        address operator_
    ) {
        uint256 tokenId = _RECEIPT_TOKEN_MANAGER.getReceiptTokenId(
            address(this),
            asset_,
            depositPeriod_,
            operator_
        );
        if (address(_assetPeriods[tokenId].asset) == address(0)) {
            revert DepositManager_InvalidAssetPeriod(address(asset_), depositPeriod_, operator_);
        }
        _;
    }

    /// @notice Reverts if the asset period is not enabled
    modifier onlyAssetPeriodEnabled(
        IERC20 asset_,
        uint8 depositPeriod_,
        address operator_
    ) {
        uint256 tokenId = _RECEIPT_TOKEN_MANAGER.getReceiptTokenId(
            address(this),
            asset_,
            depositPeriod_,
            operator_
        );
        AssetPeriod memory assetPeriod = _assetPeriods[tokenId];
        if (assetPeriod.asset == address(0)) {
            revert DepositManager_InvalidAssetPeriod(address(asset_), depositPeriod_, operator_);
        }
        if (!assetPeriod.isEnabled) {
            revert DepositManager_AssetPeriodDisabled(address(asset_), depositPeriod_, operator_);
        }
        _;
    }

    // ========== CONSTRUCTOR ========== //

    constructor(address kernel_, address tokenManager_) Policy(Kernel(kernel_)) {
        // Validate that the token manager implements IReceiptTokenManager
        if (!IERC165(tokenManager_).supportsInterface(type(IReceiptTokenManager).interfaceId)) {
            revert DepositManager_InvalidParams("token manager");
        }

        _RECEIPT_TOKEN_MANAGER = ReceiptTokenManager(tokenManager_);

        // Disabled by default by PolicyEnabler
    }

    // ========== Policy Configuration ========== //

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](2);
        dependencies[0] = toKeycode("ROLES");
        dependencies[1] = toKeycode("TRSRY");

        ROLES = ROLESv1(getModuleAddress(dependencies[0]));
        TRSRY = TRSRYv1(getModuleAddress(dependencies[1]));
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
    ///
    ///             The actions of the calling deposit operator are restricted to its own namespace, preventing the operator from accessing funds of other operators.
    ///
    ///             This function reverts if:
    ///             - The contract is not enabled
    ///             - The caller does not have the deposit operator role
    ///             - The asset/deposit period/operator combination is not enabled
    ///             - The deposit amount is below the minimum deposit requirement
    ///             - The deposit would exceed the asset's deposit cap for the operator
    ///             - The depositor has not approved the DepositManager to spend the asset tokens
    ///             - The depositor has insufficient asset token balance
    ///             - The asset is a fee-on-transfer token
    ///             - Zero shares would be received from the vault
    function deposit(
        DepositParams calldata params_
    )
        external
        onlyEnabled
        onlyRole(ROLE_DEPOSIT_OPERATOR)
        onlyAssetPeriodEnabled(params_.asset, params_.depositPeriod, msg.sender)
        returns (uint256 receiptTokenId, uint256 actualAmount)
    {
        // Deposit into vault
        // This will revert if the asset is not configured
        // This takes place before any state changes to avoid ERC777 re-entrancy
        (actualAmount, ) = _depositAsset(params_.asset, params_.depositor, params_.amount);

        // Mint the receipt token to the caller
        receiptTokenId = _RECEIPT_TOKEN_MANAGER.getReceiptTokenId(
            address(this),
            params_.asset,
            params_.depositPeriod,
            msg.sender
        );
        _RECEIPT_TOKEN_MANAGER.mint(
            params_.depositor,
            receiptTokenId,
            actualAmount,
            params_.shouldWrap
        );

        // Update the asset liabilities for the caller (operator)
        _assetLiabilities[_getAssetLiabilitiesKey(params_.asset, msg.sender)] += actualAmount;

        return (receiptTokenId, actualAmount);
    }

    /// @inheritdoc IDepositManager
    /// @dev        The actions of the calling deposit operator are restricted to its own namespace, preventing the operator from accessing funds of other operators.
    ///
    ///             Note that the returned value is a theoretical maximum. The theoretical value may not be accurate or possible due to rounding and other behaviours in an ERC4626 vault.
    function maxClaimYield(IERC20 asset_, address operator_) external view returns (uint256) {
        (, uint256 depositedSharesInAssets) = getOperatorAssets(asset_, operator_);
        bytes32 assetLiabilitiesKey = _getAssetLiabilitiesKey(asset_, operator_);
        uint256 operatorLiabilities = _assetLiabilities[assetLiabilitiesKey];
        uint256 borrowedAmount = _borrowedAmounts[assetLiabilitiesKey];

        // Avoid reverting
        // Adjust by 1 to account for the different behaviour in ERC4626.previewRedeem and ERC4626.previewWithdraw, which could leave the receipt token insolvent
        if (depositedSharesInAssets + borrowedAmount < operatorLiabilities + 1) return 0;

        return depositedSharesInAssets + borrowedAmount - operatorLiabilities - 1;
    }

    /// @inheritdoc IDepositManager
    /// @dev        This function is only callable by addresses with the deposit operator role
    ///
    ///             The actions of the calling deposit operator are restricted to its own namespace, preventing the operator from accessing funds of other operators.
    ///
    ///             This function reverts if:
    ///             - The contract is not enabled
    ///             - The caller does not have the deposit operator role
    ///             - The asset is not configured in BaseAssetManager
    ///             - Zero shares would be withdrawn from the vault
    ///             - The operator becomes insolvent after the withdrawal (assets + borrowed < liabilities)
    function claimYield(
        IERC20 asset_,
        address recipient_,
        uint256 amount_
    )
        external
        onlyEnabled
        onlyRole(ROLE_DEPOSIT_OPERATOR)
        onlyConfiguredAsset(asset_)
        returns (uint256 actualAmount)
    {
        // Withdraw the funds from the vault
        (, actualAmount) = _withdrawAsset(asset_, recipient_, amount_);

        // The receipt token supply is not adjusted here, as there is no minting/burning of receipt tokens

        // Validate operator solvency after withdrawal
        _validateOperatorSolvency(asset_, msg.sender);

        // Emit an event
        emit OperatorYieldClaimed(address(asset_), recipient_, msg.sender, actualAmount);

        return actualAmount;
    }

    /// @inheritdoc IDepositManager
    /// @dev        This function is only callable by addresses with the deposit operator role
    ///
    ///             The actions of the calling deposit operator are restricted to its own namespace, preventing the operator from accessing funds of other operators.
    ///
    ///             This function reverts if:
    ///             - The contract is not enabled
    ///             - The caller does not have the deposit operator role
    ///             - The recipient is the zero address
    ///             - The asset/deposit period/operator combination is not configured
    ///             - The depositor has insufficient receipt token balance
    ///             - For wrapped tokens: depositor has not approved ReceiptTokenManager to spend the wrapped ERC20 token
    ///             - For unwrapped tokens: depositor has not approved the caller to spend ERC6909 tokens
    ///             - Zero shares would be withdrawn from the vault
    ///             - The operator becomes insolvent after the withdrawal (assets + borrowed < liabilities)
    function withdraw(
        WithdrawParams calldata params_
    ) external onlyEnabled onlyRole(ROLE_DEPOSIT_OPERATOR) returns (uint256 actualAmount) {
        // Validate that the recipient is not the zero address
        if (params_.recipient == address(0)) revert DepositManager_ZeroAddress();

        // Burn the receipt token from the depositor
        // Will revert if the asset configuration is not valid/invalid receipt token ID
        _RECEIPT_TOKEN_MANAGER.burn(
            params_.depositor,
            _RECEIPT_TOKEN_MANAGER.getReceiptTokenId(
                address(this),
                params_.asset,
                params_.depositPeriod,
                msg.sender
            ),
            params_.amount,
            params_.isWrapped
        );

        // Update the asset liabilities for the caller (operator)
        _assetLiabilities[_getAssetLiabilitiesKey(params_.asset, msg.sender)] -= params_.amount;

        // Withdraw the funds from the vault to the recipient
        // This will revert if the asset is not configured
        (, actualAmount) = _withdrawAsset(params_.asset, params_.recipient, params_.amount);

        // Validate operator solvency after state updates
        _validateOperatorSolvency(params_.asset, msg.sender);

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

    /// @notice Validates that an operator remains solvent after a withdrawal
    /// @dev    This function ensures that operator assets + borrowed amount >= operator liabilities
    ///         This is the core solvency constraint for the DepositManager
    /// @param asset_ The asset to validate solvency for
    /// @param operator_ The operator to validate solvency for
    function _validateOperatorSolvency(IERC20 asset_, address operator_) internal view {
        (, uint256 depositedSharesInAssets) = getOperatorAssets(asset_, operator_);
        bytes32 assetLiabilitiesKey = _getAssetLiabilitiesKey(asset_, operator_);
        uint256 operatorLiabilities = _assetLiabilities[assetLiabilitiesKey];
        uint256 borrowedAmount = _borrowedAmounts[assetLiabilitiesKey];

        if (operatorLiabilities > depositedSharesInAssets + borrowedAmount) {
            revert DepositManager_Insolvent(
                address(asset_),
                operatorLiabilities,
                depositedSharesInAssets,
                borrowedAmount
            );
        }
    }

    // ========== OPERATOR NAMES ========== //

    /// @inheritdoc IDepositManager
    /// @dev        Note that once set, an operator name cannot be changed.
    ///
    ///             This function reverts if:
    ///             - The contract is not enabled
    ///             - The caller does not have the admin or manager role
    ///             - The operator's name is already set
    ///             - The name is already in use by another operator
    ///             - The operator name is empty
    ///             - The operator name is not exactly 3 characters long
    ///             - The operator name contains characters that are not a-z or 0-9
    function setOperatorName(
        address operator_,
        string calldata name_
    ) external onlyEnabled onlyManagerOrAdminRole {
        // Validate that the name is not already set for the operator
        if (_operatorToName[operator_] != bytes3(0)) {
            revert DepositManager_OperatorNameSet(operator_);
        }

        // Validate that the name is not empty
        if (bytes(name_).length == 0) {
            revert DepositManager_OperatorNameInvalid();
        }

        // Validate that the name contains 3 characters
        if (bytes(name_).length != 3) {
            revert DepositManager_OperatorNameInvalid();
        }
        // Validate that the characters are a-z, 0-9
        {
            bytes memory nameBytes = bytes(name_);
            for (uint256 i = 0; i < 3; i++) {
                if (bytes1(nameBytes[i]) >= 0x61 && bytes1(nameBytes[i]) <= 0x7A) {
                    continue; // Lowercase letter
                }

                if (bytes1(nameBytes[i]) >= 0x30 && bytes1(nameBytes[i]) <= 0x39) {
                    continue; // Number
                }

                revert DepositManager_OperatorNameInvalid();
            }
        }

        bytes3 nameBytes3 = bytes3(bytes(name_));
        // Validate that the name isn't in use by another operator
        if (_operatorNames[nameBytes3]) revert DepositManager_OperatorNameInUse(name_);

        // Set the name
        _operatorToName[operator_] = nameBytes3;

        // Add to the operator names to prevent re-use
        _operatorNames[nameBytes3] = true;

        // Emit event
        emit OperatorNameSet(operator_, name_);
    }

    /// @inheritdoc IDepositManager
    function getOperatorName(address operator_) public view returns (string memory) {
        bytes memory nameBytes = new bytes(3);
        bytes3 operatorName = _operatorToName[operator_];
        if (operatorName == bytes3(0)) {
            return "";
        }

        nameBytes[0] = bytes1(operatorName[0]);
        nameBytes[1] = bytes1(operatorName[1]);
        nameBytes[2] = bytes1(operatorName[2]);

        // Convert bytes to string
        return string(nameBytes);
    }

    // ========== ASSET PERIOD ========== //

    /// @inheritdoc IDepositManager
    function isAssetPeriod(
        IERC20 asset_,
        uint8 depositPeriod_,
        address operator_
    ) public view override returns (AssetPeriodStatus memory status) {
        uint256 receiptTokenId = _RECEIPT_TOKEN_MANAGER.getReceiptTokenId(
            address(this),
            asset_,
            depositPeriod_,
            operator_
        );
        status.isConfigured = address(_assetPeriods[receiptTokenId].asset) != address(0);
        status.isEnabled = _assetPeriods[receiptTokenId].isEnabled;
        return status;
    }

    /// @inheritdoc IDepositManager
    /// @dev        This function reverts if:
    ///             - The contract is not enabled
    ///             - The caller does not have the admin or manager role
    ///             - asset_ is the zero address
    ///             - minimumDeposit_ > depositCap_
    function addAsset(
        IERC20 asset_,
        IERC4626 vault_,
        uint256 depositCap_,
        uint256 minimumDeposit_
    ) external onlyEnabled onlyManagerOrAdminRole {
        _addAsset(asset_, vault_, depositCap_, minimumDeposit_);
    }

    /// @inheritdoc IDepositManager
    /// @dev        This function reverts if:
    ///             - The contract is not enabled
    ///             - The caller does not have the admin or manager role
    ///             - asset_ is not configured
    ///             - The existing minimum deposit > depositCap_
    function setAssetDepositCap(
        IERC20 asset_,
        uint256 depositCap_
    ) external onlyEnabled onlyManagerOrAdminRole {
        _setAssetDepositCap(asset_, depositCap_);
    }

    /// @inheritdoc IDepositManager
    /// @dev        This function reverts if:
    ///             - The contract is not enabled
    ///             - The caller does not have the admin or manager role
    ///             - asset_ is not configured
    ///             - minimumDeposit_ > the existing deposit cap
    function setAssetMinimumDeposit(
        IERC20 asset_,
        uint256 minimumDeposit_
    ) external onlyEnabled onlyManagerOrAdminRole {
        _setAssetMinimumDeposit(asset_, minimumDeposit_);
    }

    /// @inheritdoc IDepositManager
    /// @dev        This function is only callable by the manager or admin role
    ///
    ///             This function reverts if:
    ///             - The contract is not enabled
    ///             - The caller does not have the manager or admin role
    ///             - The asset has not been added via addAsset()
    ///             - The operator is the zero address
    ///             - The deposit period is 0
    ///             - The asset/deposit period/operator combination is already configured
    ///             - The operator name has not been set
    ///             - The reclaim rate exceeds 100%
    ///             - Receipt token creation fails (invalid parameters in ReceiptTokenManager)
    function addAssetPeriod(
        IERC20 asset_,
        uint8 depositPeriod_,
        address operator_,
        uint16 reclaimRate_
    )
        external
        onlyEnabled
        onlyManagerOrAdminRole
        onlyConfiguredAsset(asset_)
        returns (uint256 receiptTokenId)
    {
        // Validate that the operator is not the zero address
        if (operator_ == address(0)) revert DepositManager_ZeroAddress();

        // Validate that the deposit period is not 0
        if (depositPeriod_ == 0) revert DepositManager_OutOfBounds();

        // Validate that the asset and deposit period combination is not already configured
        if (isAssetPeriod(asset_, depositPeriod_, operator_).isConfigured) {
            revert DepositManager_AssetPeriodExists(address(asset_), depositPeriod_, operator_);
        }

        // Configure the ERC6909 receipt token and asset period atomically
        receiptTokenId = _setReceiptTokenData(asset_, depositPeriod_, operator_);

        // Set the reclaim rate (which does validation and emits an event)
        _setAssetPeriodReclaimRate(asset_, depositPeriod_, operator_, reclaimRate_);

        // Emit event
        emit AssetPeriodConfigured(receiptTokenId, address(asset_), operator_, depositPeriod_);

        return receiptTokenId;
    }

    /// @inheritdoc IDepositManager
    /// @dev        This function is only callable by the manager or admin role
    ///
    ///             This function reverts if:
    ///             - The contract is not enabled
    ///             - The caller does not have the manager or admin role
    ///             - The asset/deposit period/operator combination does not exist
    ///             - The asset period is already enabled
    function enableAssetPeriod(
        IERC20 asset_,
        uint8 depositPeriod_,
        address operator_
    )
        external
        onlyEnabled
        onlyManagerOrAdminRole
        onlyAssetPeriodExists(asset_, depositPeriod_, operator_)
    {
        uint256 tokenId = _RECEIPT_TOKEN_MANAGER.getReceiptTokenId(
            address(this),
            asset_,
            depositPeriod_,
            operator_
        );
        if (_assetPeriods[tokenId].isEnabled) {
            revert DepositManager_AssetPeriodEnabled(address(asset_), depositPeriod_, operator_);
        }
        _assetPeriods[tokenId].isEnabled = true;

        // Emit event
        emit AssetPeriodEnabled(tokenId, address(asset_), operator_, depositPeriod_);
    }

    /// @inheritdoc IDepositManager
    /// @dev        This function is only callable by the manager or admin role
    ///
    ///             This function reverts if:
    ///             - The contract is not enabled
    ///             - The caller does not have the manager or admin role
    ///             - The asset/deposit period/operator combination does not exist
    ///             - The asset period is already disabled
    function disableAssetPeriod(
        IERC20 asset_,
        uint8 depositPeriod_,
        address operator_
    )
        external
        onlyEnabled
        onlyManagerOrAdminRole
        onlyAssetPeriodExists(asset_, depositPeriod_, operator_)
    {
        uint256 tokenId = _RECEIPT_TOKEN_MANAGER.getReceiptTokenId(
            address(this),
            asset_,
            depositPeriod_,
            operator_
        );
        if (!_assetPeriods[tokenId].isEnabled) {
            revert DepositManager_AssetPeriodDisabled(address(asset_), depositPeriod_, operator_);
        }
        _assetPeriods[tokenId].isEnabled = false;

        // Emit event
        emit AssetPeriodDisabled(tokenId, address(asset_), operator_, depositPeriod_);
    }

    /// @inheritdoc IDepositManager
    function getAssetPeriods() external view override returns (AssetPeriod[] memory assetPeriods) {
        // Get all token IDs owned by this contract
        uint256[] memory tokenIds = _ownedTokenIds.values();

        // Build the array of asset periods (all owned tokens should have valid asset periods)
        assetPeriods = new AssetPeriod[](tokenIds.length);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            assetPeriods[i] = _assetPeriods[tokenIds[i]];
        }

        return assetPeriods;
    }

    /// @inheritdoc IDepositManager
    function getAssetPeriod(uint256 tokenId_) public view override returns (AssetPeriod memory) {
        return _assetPeriods[tokenId_];
    }

    /// @inheritdoc IDepositManager
    function getAssetPeriod(
        IERC20 asset_,
        uint8 depositPeriod_,
        address operator_
    ) public view override returns (AssetPeriod memory) {
        return _assetPeriods[getReceiptTokenId(asset_, depositPeriod_, operator_)];
    }

    // ========== DEPOSIT RECLAIM RATE ========== //

    /// @dev Assumes that the token ID is valid
    function _setAssetPeriodReclaimRate(
        IERC20 asset_,
        uint8 depositPeriod_,
        address operator_,
        uint16 reclaimRate_
    ) internal {
        if (reclaimRate_ > ONE_HUNDRED_PERCENT) revert DepositManager_OutOfBounds();

        _assetPeriods[
            _RECEIPT_TOKEN_MANAGER.getReceiptTokenId(
                address(this),
                asset_,
                depositPeriod_,
                operator_
            )
        ].reclaimRate = reclaimRate_;
        emit AssetPeriodReclaimRateSet(address(asset_), operator_, depositPeriod_, reclaimRate_);
    }

    /// @inheritdoc IDepositManager
    /// @dev        This function is only callable by the manager or admin role
    ///
    ///             This function reverts if:
    ///             - The contract is not enabled
    ///             - The caller does not have the manager or admin role
    ///             - The asset/deposit period/operator combination does not exist
    ///             - The reclaim rate exceeds 100%
    function setAssetPeriodReclaimRate(
        IERC20 asset_,
        uint8 depositPeriod_,
        address operator_,
        uint16 reclaimRate_
    )
        external
        onlyEnabled
        onlyManagerOrAdminRole
        onlyAssetPeriodExists(asset_, depositPeriod_, operator_)
    {
        _setAssetPeriodReclaimRate(asset_, depositPeriod_, operator_, reclaimRate_);
    }

    /// @inheritdoc IDepositManager
    function getAssetPeriodReclaimRate(
        IERC20 asset_,
        uint8 depositPeriod_,
        address operator_
    ) external view returns (uint16) {
        return
            _assetPeriods[
                _RECEIPT_TOKEN_MANAGER.getReceiptTokenId(
                    address(this),
                    asset_,
                    depositPeriod_,
                    operator_
                )
            ].reclaimRate;
    }

    // ========== BORROWING FUNCTIONS ========== //

    /// @inheritdoc IDepositManager
    /// @dev        This function is only callable by addresses with the deposit operator role
    ///
    ///             This function reverts if:
    ///             - The contract is not enabled
    ///             - The caller does not have the deposit operator role
    ///             - The recipient is the zero address
    ///             - The asset has not been added via addAsset()
    ///             - The amount exceeds the operator's available borrowing capacity
    ///             - Zero shares would be withdrawn from the vault
    ///             - The operator becomes insolvent after the withdrawal (assets + borrowed < liabilities)
    function borrowingWithdraw(
        BorrowingWithdrawParams calldata params_
    ) external onlyEnabled onlyRole(ROLE_DEPOSIT_OPERATOR) returns (uint256 actualAmount) {
        // Validate that the recipient is not the zero address
        if (params_.recipient == address(0)) revert DepositManager_ZeroAddress();

        // Validate that the asset is configured
        if (!_isConfiguredAsset(params_.asset)) revert AssetManager_NotConfigured();

        // Check borrowing capacity
        uint256 availableCapacity = getBorrowingCapacity(params_.asset, msg.sender);
        if (params_.amount > availableCapacity) {
            revert DepositManager_BorrowingLimitExceeded(
                address(params_.asset),
                msg.sender,
                params_.amount,
                availableCapacity
            );
        }

        // Withdraw the funds from the vault to the recipient
        (, actualAmount) = _withdrawAsset(params_.asset, params_.recipient, params_.amount);

        // Update borrowed amount
        // The requested amount is used, in order to avoid issues with insolvency checks
        _borrowedAmounts[_getAssetLiabilitiesKey(params_.asset, msg.sender)] += params_.amount;

        // Validate operator solvency after state updates
        _validateOperatorSolvency(params_.asset, msg.sender);

        // Emit event
        emit BorrowingWithdrawal(
            address(params_.asset),
            msg.sender,
            params_.recipient,
            actualAmount
        );

        return actualAmount;
    }

    /// @inheritdoc IDepositManager
    /// @dev        This function is only callable by addresses with the deposit operator role
    ///
    ///             This function reverts if:
    ///             - The contract is not enabled
    ///             - The caller does not have the deposit operator role
    ///             - The asset has not been added via addAsset()
    ///             - The amount exceeds the current borrowed amount for the operator
    ///             - The payer has not approved DepositManager to spend the asset tokens
    ///             - The payer has insufficient asset token balance
    ///             - The asset is a fee-on-transfer token
    ///             - Zero shares would be deposited into the vault
    ///             - The operator becomes insolvent after the repayment (assets + borrowed < liabilities)
    function borrowingRepay(
        BorrowingRepayParams calldata params_
    ) external onlyEnabled onlyRole(ROLE_DEPOSIT_OPERATOR) returns (uint256 actualAmount) {
        // Validate that the asset is configured
        if (!_isConfiguredAsset(params_.asset)) revert AssetManager_NotConfigured();

        // Get the borrowing key
        bytes32 borrowingKey = _getAssetLiabilitiesKey(params_.asset, msg.sender);

        // Check that the operator is not over-paying
        // This would cause accounting issues
        uint256 currentBorrowed = _borrowedAmounts[borrowingKey];
        if (currentBorrowed < params_.amount) {
            revert DepositManager_BorrowedAmountExceeded(
                address(params_.asset),
                msg.sender,
                params_.amount,
                currentBorrowed
            );
        }

        // Transfer funds from payer to this contract
        // We ignore the actual amount deposited into the vault, as the payer will not be able to over-pay in case of an off-by-one issue
        // This takes place before any state changes to avoid ERC777 re-entrancy
        _depositAsset(params_.asset, params_.payer, params_.amount);

        // Update borrowed amount
        _borrowedAmounts[borrowingKey] -= params_.amount;

        // Validate operator solvency after borrowed amount change
        _validateOperatorSolvency(params_.asset, msg.sender);

        // Emit event
        emit BorrowingRepayment(address(params_.asset), msg.sender, params_.payer, params_.amount);

        return params_.amount;
    }

    /// @inheritdoc IDepositManager
    /// @dev        This function is only callable by addresses with the deposit operator role
    ///
    ///             This function reverts if:
    ///             - The contract is not enabled
    ///             - The caller does not have the deposit operator role
    ///             - The asset has not been added via addAsset()
    ///             - The amount exceeds the current borrowed amount for the operator
    ///             - The payer has insufficient receipt token balance
    ///             - The payer has not approved the caller to spend ERC6909 tokens
    ///             - The operator becomes insolvent after the default (assets + borrowed < liabilities)
    function borrowingDefault(
        BorrowingDefaultParams calldata params_
    ) external onlyEnabled onlyRole(ROLE_DEPOSIT_OPERATOR) {
        // Validate that the asset is configured
        if (!_isConfiguredAsset(params_.asset)) revert AssetManager_NotConfigured();

        // Get the borrowing key
        bytes32 borrowingKey = _getAssetLiabilitiesKey(params_.asset, msg.sender);

        // Check that the operator is not over-paying
        // This would cause accounting issues
        uint256 currentBorrowed = _borrowedAmounts[borrowingKey];
        if (currentBorrowed < params_.amount) {
            revert DepositManager_BorrowedAmountExceeded(
                address(params_.asset),
                msg.sender,
                params_.amount,
                currentBorrowed
            );
        }

        // Burn the receipt tokens from the payer
        _RECEIPT_TOKEN_MANAGER.burn(
            params_.payer,
            _RECEIPT_TOKEN_MANAGER.getReceiptTokenId(
                address(this),
                params_.asset,
                params_.depositPeriod,
                msg.sender
            ),
            params_.amount,
            false
        );

        // Update the asset liabilities for the caller (operator)
        _assetLiabilities[_getAssetLiabilitiesKey(params_.asset, msg.sender)] -= params_.amount;

        // Update the borrowed amount
        _borrowedAmounts[borrowingKey] -= params_.amount;

        // Validate operator solvency after borrowed amount change
        _validateOperatorSolvency(params_.asset, msg.sender);

        // No need to update the operator shares, as the balance has already been adjusted upon withdraw/repay

        // Emit event
        emit BorrowingDefault(address(params_.asset), msg.sender, params_.payer, params_.amount);
    }

    /// @inheritdoc IDepositManager
    function getBorrowedAmount(
        IERC20 asset_,
        address operator_
    ) public view returns (uint256 borrowed) {
        return _borrowedAmounts[_getAssetLiabilitiesKey(asset_, operator_)];
    }

    /// @inheritdoc IDepositManager
    function getBorrowingCapacity(
        IERC20 asset_,
        address operator_
    ) public view returns (uint256 capacity) {
        uint256 operatorLiabilities = _assetLiabilities[_getAssetLiabilitiesKey(asset_, operator_)];
        uint256 currentBorrowed = getBorrowedAmount(asset_, operator_);

        // This is unlikely to happen, but included to avoid a revert
        if (currentBorrowed >= operatorLiabilities) {
            return 0;
        }

        return operatorLiabilities - currentBorrowed;
    }

    // ========== RECEIPT TOKEN FUNCTIONS ========== //

    function _setReceiptTokenData(
        IERC20 asset_,
        uint8 depositPeriod_,
        address operator_
    ) internal returns (uint256 tokenId) {
        // Validate that the operator name is set
        string memory operatorName = getOperatorName(operator_);
        if (bytes(operatorName).length == 0) {
            revert DepositManager_OperatorNameNotSet(operator_);
        }

        // Create the receipt token via the factory
        tokenId = _RECEIPT_TOKEN_MANAGER.createToken(
            asset_,
            depositPeriod_,
            operator_,
            operatorName
        );

        // Record this token ID as owned by this contract
        _ownedTokenIds.add(tokenId);

        // Set the asset period data atomically
        _assetPeriods[tokenId] = AssetPeriod({
            isEnabled: true,
            depositPeriod: depositPeriod_,
            reclaimRate: 0, // Start with 0, set separately later
            asset: address(asset_),
            operator: operator_
        });

        return tokenId;
    }

    /// @inheritdoc IDepositManager
    function getReceiptTokenId(
        IERC20 asset_,
        uint8 depositPeriod_,
        address operator_
    ) public view override returns (uint256) {
        return
            _RECEIPT_TOKEN_MANAGER.getReceiptTokenId(
                address(this),
                asset_,
                depositPeriod_,
                operator_
            );
    }

    /// @inheritdoc IDepositManager
    function getReceiptTokenManager() external view override returns (IReceiptTokenManager) {
        return IReceiptTokenManager(address(_RECEIPT_TOKEN_MANAGER));
    }

    /// @inheritdoc IDepositManager
    function getReceiptToken(
        IERC20 asset_,
        uint8 depositPeriod_,
        address operator_
    ) external view override returns (uint256 tokenId, address wrappedToken) {
        tokenId = _RECEIPT_TOKEN_MANAGER.getReceiptTokenId(
            address(this),
            asset_,
            depositPeriod_,
            operator_
        );
        wrappedToken = _RECEIPT_TOKEN_MANAGER.getWrappedToken(tokenId);
        return (tokenId, wrappedToken);
    }

    // ========== ERC165 ========== //

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(BaseAssetManager, PolicyEnabler) returns (bool) {
        return
            interfaceId == type(IDepositManager).interfaceId ||
            BaseAssetManager.supportsInterface(interfaceId) ||
            PolicyEnabler.supportsInterface(interfaceId);
    }

    // ========== ADMIN FUNCTIONS ==========

    /// @notice Rescue any ERC20 token sent to this contract and send it to the TRSRY
    /// @dev    This function is restricted to the admin role and prevents rescue of any managed assets or their vault tokens
    ///         to protect deposited user funds
    /// @param  token_ The address of the ERC20 token to rescue
    function rescue(address token_) external onlyEnabled onlyAdminRole {
        // Validate that the token address is not zero
        if (token_ == address(0)) {
            revert DepositManager_ZeroAddress();
        }

        // Validate that the token is not a managed asset or vault token
        uint256 configuredAssetsLength = _configuredAssets.length;
        for (uint256 i = 0; i < configuredAssetsLength; i++) {
            IERC20 asset = _configuredAssets[i];
            AssetConfiguration memory config = _assetConfigurations[asset];

            // Prevent rescue of the asset itself
            if (token_ == address(asset)) {
                revert DepositManager_CannotRescueAsset(token_);
            }

            // Prevent rescue of the vault token if configured
            if (config.vault != address(0) && token_ == config.vault) {
                revert DepositManager_CannotRescueAsset(token_);
            }
        }

        // Transfer the token balance to TRSRY
        ERC20 token = ERC20(token_);
        uint256 balance = token.balanceOf(address(this));
        if (balance > 0) {
            token.safeTransfer(address(TRSRY), balance);
            emit TokenRescued(token_, balance);
        }
    }
}
