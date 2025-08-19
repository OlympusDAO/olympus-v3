// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.20;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";

// Libraries
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";
import {EnumerableSet} from "@openzeppelin-5.3.0/utils/structs/EnumerableSet.sol";
import {TransferHelper} from "src/libraries/TransferHelper.sol";
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
    using TransferHelper for ERC20;
    using String for string;
    using EnumerableSet for EnumerableSet.UintSet;

    // ========== CONSTANTS ========== //

    /// @notice The role that is allowed to deposit and withdraw funds
    bytes32 public constant ROLE_DEPOSIT_OPERATOR = "deposit_operator";

    // Tasks
    // [X] Rename to DepositManager
    // [X] Idle/vault strategy for deposited tokens
    // [X] ERC6909 migration
    // [X] Rename to receipt tokens
    // [X] ReceiptTokenSupply to depositor supply
    // [X] borrowing and repayment of deposited funds
    // [X] consider shifting away from policy
    // [X] consider if asset configuration should require a different role

    // ========== STATE VARIABLES ========== //

    /// @notice Maps asset liabilities key to the number of receipt tokens that have been minted
    /// @dev    This is used to ensure that the receipt tokens are solvent
    ///         As with the BaseAssetManager, deposited asset tokens with different deposit periods are co-mingled.
    mapping(bytes32 key => uint256 receiptTokenSupply) internal _assetLiabilities;

    /// @notice Maps token ID to the asset period
    mapping(uint256 tokenId => AssetPeriod) internal _assetPeriods;

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
        if (
            address(_assetPeriods[getReceiptTokenId(asset_, depositPeriod_, operator_)].asset) ==
            address(0)
        ) {
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
        AssetPeriod memory assetPeriod = _assetPeriods[
            getReceiptTokenId(asset_, depositPeriod_, operator_)
        ];
        if (assetPeriod.asset == address(0)) {
            revert DepositManager_InvalidAssetPeriod(address(asset_), depositPeriod_, operator_);
        }

        if (!assetPeriod.isEnabled) {
            revert DepositManager_AssetPeriodDisabled(address(asset_), depositPeriod_, operator_);
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
    ///
    ///             The actions of the calling deposit operator are restricted to its own namespace, preventing the operator from accessing funds of other operators.
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
        receiptTokenId = getReceiptTokenId(params_.asset, params_.depositPeriod, msg.sender);
        _mint(params_.depositor, receiptTokenId, actualAmount, params_.shouldWrap);

        // Update the asset liabilities for the caller (operator)
        _assetLiabilities[_getAssetLiabilitiesKey(params_.asset, msg.sender)] += actualAmount;

        return (receiptTokenId, actualAmount);
    }

    /// @inheritdoc IDepositManager
    ///
    /// @dev        The actions of the calling deposit operator are restricted to its own namespace, preventing the operator from accessing funds of other operators.
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
    function withdraw(
        WithdrawParams calldata params_
    ) external onlyEnabled onlyRole(ROLE_DEPOSIT_OPERATOR) returns (uint256 actualAmount) {
        // Validate that the recipient is not the zero address
        if (params_.recipient == address(0)) revert DepositManager_ZeroAddress();

        // Burn the receipt token from the depositor
        // Will revert if the asset configuration is not valid/invalid receipt token ID
        _burn(
            params_.depositor,
            getReceiptTokenId(params_.asset, params_.depositPeriod, msg.sender),
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
            revert DepositManager_Insolvent(address(asset_), operatorLiabilities);
        }
    }

    // ========== OPERATOR NAMES ========== //

    /// @inheritdoc IDepositManager
    /// @dev        Note that once set, an operator name cannot be changed.
    ///
    ///             This function reverts if:
    ///             - the caller is not the admin or manager role
    ///             - the operator's name is already set
    ///             - the name is already in use
    ///             - the operator name is empty
    ///             - the operator name is not 3 characters long
    ///             - the operator name contains characters that are not a-z or 0-9
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
        uint256 receiptTokenId = getReceiptTokenId(asset_, depositPeriod_, operator_);
        status.isConfigured = address(_assetPeriods[receiptTokenId].asset) != address(0);
        status.isEnabled = _assetPeriods[receiptTokenId].isEnabled;

        return status;
    }

    /// @inheritdoc IDepositManager
    /// @dev        This function is only callable by the manager or admin role
    function addAsset(
        IERC20 asset_,
        IERC4626 vault_,
        uint256 depositCap_
    ) external onlyEnabled onlyManagerOrAdminRole {
        _addAsset(asset_, vault_, depositCap_);
    }

    /// @inheritdoc IDepositManager
    /// @dev        This function is only callable by the manager or admin role
    function setAssetDepositCap(
        IERC20 asset_,
        uint256 depositCap_
    ) external onlyEnabled onlyManagerOrAdminRole {
        _setAssetDepositCap(asset_, depositCap_);
    }

    /// @inheritdoc IDepositManager
    /// @dev        This function is only callable by the manager or admin role
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
        // Validate that the deposit period is not 0
        if (depositPeriod_ == 0) revert DepositManager_OutOfBounds();

        // Validate that the asset and deposit period combination is not already configured
        if (isAssetPeriod(asset_, depositPeriod_, operator_).isConfigured) {
            revert DepositManager_AssetPeriodExists(address(asset_), depositPeriod_, operator_);
        }

        // Configure the ERC6909 receipt token
        receiptTokenId = _setReceiptTokenData(asset_, depositPeriod_, operator_);

        // Set the asset period
        _assetPeriods[receiptTokenId] = AssetPeriod({
            isEnabled: true,
            depositPeriod: depositPeriod_,
            reclaimRate: 0,
            asset: address(asset_),
            operator: operator_
        });

        // Set the reclaim rate (which does validation and emits an event)
        _setAssetPeriodReclaimRate(asset_, depositPeriod_, operator_, reclaimRate_);

        // Emit event
        emit AssetPeriodConfigured(receiptTokenId, address(asset_), operator_, depositPeriod_);

        return receiptTokenId;
    }

    /// @inheritdoc IDepositManager
    /// @dev        This function is only callable by the manager or admin role
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
        // Validate that the asset period is disabled
        uint256 tokenId = getReceiptTokenId(asset_, depositPeriod_, operator_);
        if (_assetPeriods[tokenId].isEnabled) {
            revert DepositManager_AssetPeriodEnabled(address(asset_), depositPeriod_, operator_);
        }

        // Enable the asset period
        _assetPeriods[getReceiptTokenId(asset_, depositPeriod_, operator_)].isEnabled = true;

        // Emit event
        emit AssetPeriodEnabled(tokenId, address(asset_), operator_, depositPeriod_);
    }

    /// @inheritdoc IDepositManager
    /// @dev        This function is only callable by the manager or admin role
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
        // Validate that the asset period is enabled
        uint256 tokenId = getReceiptTokenId(asset_, depositPeriod_, operator_);
        if (!_assetPeriods[tokenId].isEnabled) {
            revert DepositManager_AssetPeriodDisabled(address(asset_), depositPeriod_, operator_);
        }

        // Disable the asset period
        _assetPeriods[getReceiptTokenId(asset_, depositPeriod_, operator_)].isEnabled = false;

        // Emit event
        emit AssetPeriodDisabled(tokenId, address(asset_), operator_, depositPeriod_);
    }

    /// @inheritdoc IDepositManager
    function getAssetPeriods() external view returns (AssetPeriod[] memory) {
        uint256 tokenIdsLength = _wrappableTokenIds.length();
        AssetPeriod[] memory depositAssets = new AssetPeriod[](tokenIdsLength);
        for (uint256 i; i < tokenIdsLength; ++i) {
            depositAssets[i] = _assetPeriods[_wrappableTokenIds.at(i)];
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

        _assetPeriods[getReceiptTokenId(asset_, depositPeriod_, operator_)]
            .reclaimRate = reclaimRate_;
        emit AssetPeriodReclaimRateSet(address(asset_), operator_, depositPeriod_, reclaimRate_);
    }

    /// @inheritdoc IDepositManager
    /// @dev        This function is only callable by the manager or admin role
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
        return _assetPeriods[getReceiptTokenId(asset_, depositPeriod_, operator_)].reclaimRate;
    }

    // ========== BORROWING FUNCTIONS ========== //

    /// @inheritdoc IDepositManager
    /// @dev        This function is only callable by addresses with the deposit operator role
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
        // This is done after the withdraw, as the actual amount is not known ahead of time
        _borrowedAmounts[_getAssetLiabilitiesKey(params_.asset, msg.sender)] += actualAmount;

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

        // Emit event
        emit BorrowingRepayment(address(params_.asset), msg.sender, params_.payer, params_.amount);

        return params_.amount;
    }

    /// @inheritdoc IDepositManager
    /// @dev        This function is only callable by addresses with the deposit operator role
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
        _burn(
            params_.payer,
            getReceiptTokenId(params_.asset, params_.depositPeriod, msg.sender),
            params_.amount,
            false
        );

        // Update the asset liabilities for the caller (operator)
        _assetLiabilities[_getAssetLiabilitiesKey(params_.asset, msg.sender)] -= params_.amount;

        // Update the borrowed amount
        _borrowedAmounts[borrowingKey] -= params_.amount;

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

        // Generate a unique token ID for the token, deposit period and operator combination
        tokenId = getReceiptTokenId(asset_, depositPeriod_, operator_);

        // Create the receipt token
        _createWrappableToken(
            tokenId,
            string
                .concat(operatorName, asset_.name(), " - ", uint2str(depositPeriod_), " months")
                .truncate32(),
            string
                .concat(operatorName, asset_.symbol(), "-", uint2str(depositPeriod_), "m")
                .truncate32(),
            asset_.decimals(),
            abi.encodePacked(
                address(this), // Owner
                address(asset_), // Asset
                depositPeriod_, // Deposit Period
                operator_ // Operator
            ),
            false
        );

        return tokenId;
    }

    /// @inheritdoc IDepositManager
    function getReceiptTokenId(
        IERC20 asset_,
        uint8 depositPeriod_,
        address operator_
    ) public pure override returns (uint256) {
        return uint256(keccak256(abi.encode(asset_, depositPeriod_, operator_)));
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

    /// @inheritdoc IDepositManager
    function getReceiptTokenOperator(uint256 tokenId_) external view override returns (address) {
        return _assetPeriods[tokenId_].operator;
    }

    // ========== ERC165 ========== //

    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        virtual
        override(ERC6909Wrappable, BaseAssetManager, PolicyEnabler)
        returns (bool)
    {
        return
            interfaceId == type(IDepositManager).interfaceId ||
            ERC6909Wrappable.supportsInterface(interfaceId) ||
            BaseAssetManager.supportsInterface(interfaceId) ||
            PolicyEnabler.supportsInterface(interfaceId);
    }
}
