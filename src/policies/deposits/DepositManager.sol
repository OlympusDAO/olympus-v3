// SPDX-License-Identifier: AGPL-3.0
/// forge-lint: disable-start(asm-keccak256, mixed-case-function)
pragma solidity ^0.8.20;

// Interfaces
import {IERC165} from "@openzeppelin-5.7.0/interfaces/IERC165.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IDepositManagerV1_1} from "src/policies/interfaces/deposits/IDepositManagerV1_1.sol";
import {IReceiptTokenManager} from "src/policies/interfaces/deposits/IReceiptTokenManager.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";

// Libraries
import {EnumerableSet} from "@openzeppelin-5.7.0/utils/structs/EnumerableSet.sol";
import {ReentrancyGuardTransient} from "@openzeppelin-5.7.0/utils/ReentrancyGuardTransient.sol";
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";
import {TransferHelper} from "src/libraries/TransferHelper.sol";

// Bophades
import {Kernel, Keycode, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/OlympusRoles.sol";
import {EnablerV2} from "src/bases/EnablerV2.sol";
import {ReEnablerGracePeriod} from "src/bases/ReEnablerGracePeriod.sol";
import {BaseAssetManager} from "src/bases/BaseAssetManager.sol";
import {ReceiptTokenManager} from "src/policies/deposits/ReceiptTokenManager.sol";
import {ConfigOperatorSingleStep} from "src/policies/utils/ConfigOperatorSingleStep.sol";
import {PolicyEnablerV2} from "src/policies/utils/PolicyEnablerV2.sol";
import {ADMIN_ROLE, DEPOSIT_MANAGER_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

/// @title Deposit Manager
/// @notice This policy manages deposits and withdrawals for Olympus protocol contracts
/// @dev    Key Features:
///         - ERC6909 receipt tokens with optional ERC20 wrapping, using ReceiptTokenManager
///         - Operator isolation preventing cross-operator fund access
///         - Borrowing functionality
///         - Configurable reclaim rates for risk management
contract DepositManager is
    Policy,
    ReEnablerGracePeriod,
    PolicyEnablerV2,
    ConfigOperatorSingleStep,
    IDepositManagerV1_1,
    IVersioned,
    BaseAssetManager,
    ReentrancyGuardTransient
{
    using TransferHelper for ERC20;
    using EnumerableSet for EnumerableSet.UintSet;

    // ========== CONSTANTS ========== //

    /// @notice The role that is allowed to deposit and withdraw funds
    bytes32 public constant ROLE_DEPOSIT_OPERATOR = "deposit_operator";

    /// @notice The required number of characters in an operator name
    uint256 internal constant _OPERATOR_NAME_LENGTH = 3;

    /// @notice The receipt token manager for creating receipt tokens
    ReceiptTokenManager internal immutable _RECEIPT_TOKEN_MANAGER;

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

    /// @notice Window after a disable during which governance or `deposit_manager_admin` may recover it.
    uint32 public constant REENABLE_GRACE_PERIOD = 7 days;

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

    function _getAssetPeriodTokenId(
        IERC20 asset_,
        uint8 depositPeriod_,
        address operator_
    ) internal view returns (uint256 tokenId) {
        tokenId = getReceiptTokenId(asset_, depositPeriod_, operator_);
        if (address(_assetPeriods[tokenId].asset) == address(0)) {
            revert DepositManager_InvalidAssetPeriod(address(asset_), depositPeriod_, operator_);
        }
    }

    function _onlyAssetPeriodEnabled(
        IERC20 asset_,
        uint8 depositPeriod_,
        address operator_
    ) internal view {
        uint256 tokenId = _getAssetPeriodTokenId(asset_, depositPeriod_, operator_);
        if (!_assetPeriods[tokenId].isEnabled) {
            revert DepositManager_AssetPeriodDisabled(address(asset_), depositPeriod_, operator_);
        }
    }

    // ========== CONSTRUCTOR ========== //

    constructor(
        address kernel_,
        address tokenManager_
    ) Policy(Kernel(kernel_)) ReEnablerGracePeriod(REENABLE_GRACE_PERIOD) {
        // Validate that the token manager implements IReceiptTokenManager
        if (!IERC165(tokenManager_).supportsInterface(type(IReceiptTokenManager).interfaceId)) {
            revert DepositManager_InvalidParams("token manager");
        }

        _RECEIPT_TOKEN_MANAGER = ReceiptTokenManager(tokenManager_);

        // Disabled by default by EnablerV2
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
        pure
        override
        returns (Permissions[] memory permissions)
    {
        permissions = new Permissions[](0);
    }

    /// @inheritdoc IVersioned
    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 1;

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
    ///             - The credited principal would exceed the asset's aggregate deposit cap
    ///             - The depositor has not approved the DepositManager to spend the asset tokens
    ///             - The depositor has insufficient asset token balance
    ///             - The asset is a fee-on-transfer token
    ///             - Zero shares would be received from the vault
    function deposit(
        DepositParams calldata params_
    )
        external
        nonReentrant
        givenEnabled
        onlyRole(ROLE_DEPOSIT_OPERATOR)
        returns (uint256 receiptTokenId, uint256 actualAmount)
    {
        _onlyAssetPeriodEnabled(params_.asset, params_.depositPeriod, msg.sender);
        return _deposit(params_);
    }

    /// @notice Executes a deposit after external entry-point validation.
    function _deposit(
        DepositParams calldata params_
    ) internal returns (uint256 receiptTokenId, uint256 actualAmount) {
        // Deposit into vault
        // This will revert if the asset is not configured
        // This takes place before any state changes to avoid ERC777 re-entrancy
        (actualAmount, ) = _depositAsset(
            params_.asset,
            params_.depositor,
            params_.amount,
            true // Enforce minimum deposit
        );

        // Mint the receipt token to the caller
        receiptTokenId = getReceiptTokenId(params_.asset, params_.depositPeriod, msg.sender);
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
    /// @dev        Notes:
    ///             - This function is only callable by addresses with the deposit operator role
    ///             - The actions of the calling deposit operator are restricted to its own namespace, preventing the operator from accessing funds of other operators.
    ///             - Given a low enough amount, the actual amount withdrawn may be 0. This function will not revert in such a case.
    ///
    ///             This function reverts if:
    ///             - The contract is not enabled
    ///             - The caller does not have the deposit operator role
    ///             - The requested amount is zero
    ///             - The recipient is the zero address or this contract
    ///             - The asset is not configured in BaseAssetManager
    ///             - The operator becomes insolvent after the withdrawal (assets + borrowed < liabilities)
    function claimYield(
        IERC20 asset_,
        address recipient_,
        uint256 amount_
    )
        external
        nonReentrant
        givenEnabled
        onlyRole(ROLE_DEPOSIT_OPERATOR)
        onlyConfiguredAsset(asset_)
        returns (uint256 actualAmount)
    {
        (, actualAmount) = _claimYield(asset_, recipient_, amount_, false);
        return actualAmount;
    }

    /// @inheritdoc IDepositManagerV1_1
    /// @dev This function reverts if:
    ///      - The contract is disabled
    ///      - The caller lacks the deposit operator role
    ///      - The requested amount is zero
    ///      - The recipient is the zero address or this contract
    ///      - The asset is not configured
    ///      - Share output is requested without a configured vault
    ///      - Underlying output is requested for an asset that requires share withdrawal
    ///      - The claim would make the operator insolvent
    function claimYield(
        IERC20 asset_,
        address recipient_,
        uint256 amount_,
        bool withdrawAsShares_
    )
        external
        nonReentrant
        givenEnabled
        onlyRole(ROLE_DEPOSIT_OPERATOR)
        onlyConfiguredAsset(asset_)
        returns (IERC20 tokenOut, uint256 amountOut)
    {
        return _claimYield(asset_, recipient_, amount_, withdrawAsShares_);
    }

    /// @notice Executes an operator yield claim after external entry-point validation.
    function _claimYield(
        IERC20 asset_,
        address recipient_,
        uint256 amount_,
        bool withdrawAsShares_
    ) internal returns (IERC20 tokenOut, uint256 amountOut) {
        _validateWithdrawalInput(recipient_, amount_);
        _validateWithdrawalMode(asset_, withdrawAsShares_);

        // Withdraw the funds from the vault
        // The value returned can also be zero
        (, tokenOut, amountOut) = _withdrawAsset(asset_, recipient_, amount_, withdrawAsShares_);

        // The receipt token supply is not adjusted here, as there is no minting/burning of receipt tokens

        // Validate operator solvency after withdrawal
        _validateOperatorSolvency(asset_, msg.sender);

        // Emit exactly one claim event matching the selected output mode, including zero output.
        if (withdrawAsShares_) {
            emit OperatorYieldClaimed(
                address(asset_),
                recipient_,
                msg.sender,
                amount_,
                address(tokenOut),
                amountOut
            );
        } else {
            emit OperatorYieldClaimed(address(asset_), recipient_, msg.sender, amountOut);
        }

        return (tokenOut, amountOut);
    }

    /// @inheritdoc IDepositManager
    /// @dev        Notes:
    ///             - This function is only callable by addresses with the deposit operator role
    ///             - The actions of the calling deposit operator are restricted to its own namespace, preventing the operator from accessing funds of other operators.
    ///             - Given a low enough amount, the actual amount withdrawn may be 0. This function will not revert in such a case.
    ///
    ///             This function will revert if:
    ///             - The contract is not enabled
    ///             - The caller does not have the deposit operator role
    ///             - The requested amount is zero
    ///             - The recipient is the zero address or this contract
    ///             - The asset/deposit period/operator combination is not configured
    ///             - The depositor has insufficient receipt token balance
    ///             - For wrapped tokens: depositor has not approved ReceiptTokenManager to spend the wrapped ERC20 token
    ///             - For unwrapped tokens: depositor has not approved the caller to spend ERC6909 tokens
    ///             - The operator becomes insolvent after the withdrawal (assets + borrowed < liabilities)
    function withdraw(
        WithdrawParams calldata params_
    )
        external
        nonReentrant
        givenEnabled
        onlyRole(ROLE_DEPOSIT_OPERATOR)
        returns (uint256 actualAmount)
    {
        (, actualAmount) = _withdraw(params_, false);
        return actualAmount;
    }

    /// @inheritdoc IDepositManagerV1_1
    /// @dev This function reverts if:
    ///      - The contract is disabled
    ///      - The caller lacks the deposit operator role
    ///      - The requested amount is zero
    ///      - The recipient is the zero address or this contract
    ///      - The asset, deposit period or operator is not configured
    ///      - Receipt token authorization or balance is insufficient
    ///      - Share output is requested without a configured vault
    ///      - Underlying output is requested for an asset that requires share withdrawal
    ///      - The withdrawal would make the operator insolvent
    function withdraw(
        WithdrawParams calldata params_,
        bool withdrawAsShares_
    )
        external
        nonReentrant
        givenEnabled
        onlyRole(ROLE_DEPOSIT_OPERATOR)
        returns (IERC20 tokenOut, uint256 amountOut)
    {
        return _withdraw(params_, withdrawAsShares_);
    }

    /// @notice Executes a receipt-backed withdrawal after external entry-point validation.
    function _withdraw(
        WithdrawParams calldata params_,
        bool withdrawAsShares_
    ) internal returns (IERC20 tokenOut, uint256 amountOut) {
        _validateWithdrawalInput(params_.recipient, params_.amount);
        _validateWithdrawalMode(params_.asset, withdrawAsShares_);

        // Burn the receipt token from the depositor
        // Will revert if the asset configuration is not valid/invalid receipt token ID
        _RECEIPT_TOKEN_MANAGER.burn(
            params_.depositor,
            getReceiptTokenId(params_.asset, params_.depositPeriod, msg.sender),
            params_.amount,
            params_.isWrapped
        );

        // Update the asset liabilities for the caller (operator)
        _assetLiabilities[_getAssetLiabilitiesKey(params_.asset, msg.sender)] -= params_.amount;
        _decreaseAssetDepositCapUtilization(params_.asset, params_.amount);

        // Withdraw the funds from the vault to the recipient
        // This will revert if the asset is not configured
        (, tokenOut, amountOut) = _withdrawAsset(
            params_.asset,
            params_.recipient,
            params_.amount,
            withdrawAsShares_
        );

        // Validate operator solvency after state updates
        _validateOperatorSolvency(params_.asset, msg.sender);

        return (tokenOut, amountOut);
    }

    /// @inheritdoc IDepositManagerV1_1
    /// @dev Conversion and current-cap estimate only, not a reservation or guarantee of credit or
    ///      successful execution. A zero-credit estimate returns zero. A positive estimate is
    ///      checked against aggregate credited principal, including lent-out principal. Vault
    ///      state, the cap, or utilization can change before execution; permissions, enabled
    ///      state, minimum deposits, and balances are not checked. Reverts if the asset is not
    ///      configured or the positive estimated credit exceeds current aggregate headroom.
    function previewDeposit(
        IERC20 asset_,
        uint256 assetAmount_
    ) external view returns (uint256 estimatedCreditedAssets, uint256 estimatedCustodyShares) {
        _onlyConfiguredAsset(asset_);
        AssetConfiguration memory configuration = _assetConfigurations[asset_];
        if (configuration.vault == address(0)) {
            estimatedCreditedAssets = assetAmount_;
            estimatedCustodyShares = assetAmount_;
        } else {
            IERC4626 vault = IERC4626(configuration.vault);
            estimatedCustodyShares = vault.previewDeposit(assetAmount_);
            estimatedCreditedAssets = estimatedCustodyShares == 0
                ? 0
                : _convertSharesToAssets(vault, estimatedCustodyShares);
        }

        if (estimatedCreditedAssets != 0) {
            _validateAssetDepositCap(asset_, estimatedCreditedAssets);
        }
    }

    /// @inheritdoc IDepositManagerV1_1
    /// @dev Conversion estimate only, not a guarantee of delivery or successful execution.
    ///      Later vault state, redemption restrictions, permissions, balances, and solvency
    ///      can change the result or cause execution to revert. Reverts if the asset is not
    ///      configured, share output is requested without a configured vault, or underlying
    ///      output is requested for an asset that requires share withdrawal.
    function previewWithdraw(
        IERC20 asset_,
        uint256 assetAmount_,
        bool withdrawAsShares_
    ) external view returns (IERC20 tokenOut, uint256 amountOut) {
        AssetConfiguration memory configuration = _assetConfigurations[asset_];
        if (!configuration.isConfigured) revert AssetManager_NotConfigured();
        tokenOut = _validateWithdrawalMode(asset_, configuration, withdrawAsShares_);
        if (configuration.vault == address(0)) {
            return (tokenOut, assetAmount_);
        }

        IERC4626 vault = IERC4626(configuration.vault);
        uint256 sharesOut = vault.convertToShares(assetAmount_);
        if (withdrawAsShares_) return (tokenOut, sharesOut);
        if (sharesOut == 0) return (tokenOut, 0);

        uint256 sharesInAssets = _convertSharesToAssets(vault, sharesOut);
        return (tokenOut, sharesInAssets);
    }

    /// @inheritdoc BaseAssetManager
    function _emitShareWithdrawal(
        IERC20 asset_,
        address recipient_,
        uint256 requestedAmount_,
        IERC20 tokenOut_,
        uint256 amountOut_
    ) internal override {
        emit AssetWithdrawn(
            address(asset_),
            recipient_,
            msg.sender,
            requestedAmount_,
            address(tokenOut_),
            amountOut_
        );
    }

    /// @notice Validates common withdrawal-style inputs.
    function _validateWithdrawalInput(address recipient_, uint256 amount_) internal view {
        if (recipient_ == address(0)) revert DepositManager_ZeroAddress();
        if (recipient_ == address(this)) revert DepositManager_InvalidRecipient(recipient_);
        if (amount_ == 0) revert AssetManager_ZeroAmount();
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
    ///
    ///         Notes:
    ///         - The solvency checks assume that the value of each vault share is increasing, and will not reduce.
    ///         - In a situation where the assets per share reduces below 1 (at the appropriate decimal scale), the solvency check will fail.
    ///
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
    ///             - The caller does not have the admin role
    ///             - The operator's name is already set
    ///             - The name is already in use by another operator
    ///             - The operator name is empty
    ///             - The operator name is not exactly 3 characters long
    ///             - The operator name contains characters that are not a-z or 0-9
    function setOperatorName(
        address operator_,
        string calldata name_
    ) external givenEnabled onlyAdminRole {
        // Validate that the name is not already set for the operator
        if (_operatorToName[operator_] != bytes3(0)) {
            revert DepositManager_OperatorNameSet(operator_);
        }

        // Validate that the name contains 3 characters
        if (bytes(name_).length != _OPERATOR_NAME_LENGTH) {
            revert DepositManager_OperatorNameInvalid();
        }
        // Validate that the characters are a-z, 0-9
        if (!_isValidOperatorName(bytes(name_))) revert DepositManager_OperatorNameInvalid();

        /// forge-lint: disable-next-line(unsafe-typecast)
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

    /// @notice Returns whether every operator-name character is lowercase alphanumeric ASCII.
    function _isValidOperatorName(bytes memory name_) internal pure returns (bool) {
        for (uint256 i = 0; i < _OPERATOR_NAME_LENGTH; i++) {
            bytes1 character = name_[i];
            bool isLowercaseLetter = character >= 0x61 && character <= 0x7A;
            bool isNumber = character >= 0x30 && character <= 0x39;
            if (!isLowercaseLetter && !isNumber) return false;
        }

        return true;
    }

    /// @inheritdoc IDepositManager
    function getOperatorName(address operator_) public view returns (string memory) {
        bytes3 operatorName = _operatorToName[operator_];
        if (operatorName == bytes3(0)) {
            return "";
        }
        // Convert bytes to string
        return string(abi.encodePacked(operatorName));
    }

    // ========== ASSET PERIOD ========== //

    /// @inheritdoc IDepositManager
    function isAssetPeriod(
        IERC20 asset_,
        uint8 depositPeriod_,
        address operator_
    ) public view override returns (AssetPeriodStatus memory status) {
        uint256 receiptTokenId = getReceiptTokenId(asset_, depositPeriod_, operator_);
        AssetPeriod storage assetPeriod = _assetPeriods[receiptTokenId];
        status.isConfigured = address(assetPeriod.asset) != address(0);
        status.isEnabled = assetPeriod.isEnabled;
        return status;
    }

    /// @inheritdoc IDepositManager
    /// @dev        This function reverts if:
    ///             - The contract is not enabled
    ///             - The caller does not have the admin role
    ///             - asset_ is the zero address
    ///             - minimumDeposit_ > depositCap_
    ///
    ///             Notes:
    ///             - A limitation of the current implementation is that the vault is assumed to be monotonically-increasing in value.
    ///             - The pairing of the asset and vault is immutable, to prevent a governance attack on user deposits.
    function addAsset(
        IERC20 asset_,
        IERC4626 vault_,
        uint256 depositCap_,
        uint256 minimumDeposit_
    ) external givenEnabled onlyAdminRole {
        _addAsset(asset_, vault_, depositCap_, minimumDeposit_);
    }

    /// @inheritdoc IDepositManagerV1_1
    /// @dev The explicit requirement supports vaults such as sUSDe that restrict synchronous
    ///      redemption without advertising ERC-7540 asynchronous redemption.
    function addAsset(
        IERC20 asset_,
        IERC4626 vault_,
        uint256 depositCap_,
        uint256 minimumDeposit_,
        bool requiresShareWithdrawal_
    ) external givenEnabled onlyAdminRole {
        _addAsset(asset_, vault_, depositCap_, minimumDeposit_);
        _setAssetShareWithdrawalRequired(asset_, requiresShareWithdrawal_);
    }

    /// @inheritdoc IDepositManagerV1_1
    /// @dev This function reverts if:
    ///      - The contract is disabled.
    ///      - The caller is neither admin nor the configured config operator.
    ///      - The asset is not configured.
    ///      - Share withdrawal is required for idle custody.
    ///      - Share withdrawal is not required for a vault advertising asynchronous redemption.
    function setAssetShareWithdrawalRequired(
        IERC20 asset_,
        bool required_
    ) external givenEnabled onlyConfigAuthority(false) {
        _setAssetShareWithdrawalRequired(asset_, required_);
    }

    /// @inheritdoc IDepositManager
    /// @dev        This function reverts if:
    ///             - The contract is not enabled
    ///             - The caller is neither admin nor the configured config operator
    ///             - asset_ is not configured
    ///             - The existing minimum deposit > depositCap_
    function setAssetDepositCap(
        IERC20 asset_,
        uint256 depositCap_
    ) external givenEnabled onlyConfigAuthority(false) {
        _setAssetDepositCap(asset_, depositCap_);
    }

    /// @inheritdoc IDepositManager
    /// @dev        This function reverts if:
    ///             - The contract is not enabled
    ///             - The caller is neither admin nor the configured config operator
    ///             - asset_ is not configured
    ///             - minimumDeposit_ > the existing deposit cap
    function setAssetMinimumDeposit(
        IERC20 asset_,
        uint256 minimumDeposit_
    ) external givenEnabled onlyConfigAuthority(false) {
        _setAssetMinimumDeposit(asset_, minimumDeposit_);
    }

    /// @inheritdoc IDepositManager
    /// @dev        This function is only callable by the admin role.
    ///
    ///             This function reverts if:
    ///             - The contract is not enabled
    ///             - The caller does not have the admin role
    ///             - The asset has not been added via addAsset()
    ///             - The operator is the zero address
    ///             - The deposit period is 0
    ///             - The asset/deposit period/operator combination is already configured
    ///             - The operator name has not been set
    ///             - Receipt token creation fails (invalid parameters in ReceiptTokenManager)
    function addAssetPeriod(
        IERC20 asset_,
        uint8 depositPeriod_,
        address operator_
    )
        external
        givenEnabled
        onlyAdminRole
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

        // Emit event
        emit AssetPeriodConfigured(receiptTokenId, address(asset_), operator_, depositPeriod_);

        return receiptTokenId;
    }

    /// @inheritdoc IDepositManager
    /// @dev        This function is only callable by admin or the configured config operator.
    ///
    ///             This function reverts if:
    ///             - The contract is not enabled
    ///             - The caller is neither admin nor the configured config operator
    ///             - The asset/deposit period/operator combination does not exist
    ///             - The asset period is already enabled
    function enableAssetPeriod(
        IERC20 asset_,
        uint8 depositPeriod_,
        address operator_
    ) external givenEnabled onlyConfigAuthority(false) {
        uint256 tokenId = _getAssetPeriodTokenId(asset_, depositPeriod_, operator_);
        if (_assetPeriods[tokenId].isEnabled) {
            revert DepositManager_AssetPeriodEnabled(address(asset_), depositPeriod_, operator_);
        }
        _assetPeriods[tokenId].isEnabled = true;

        // Emit event
        emit AssetPeriodEnabled(tokenId, address(asset_), operator_, depositPeriod_);
    }

    /// @inheritdoc IDepositManager
    /// @dev        This function is callable by admin, the configured config operator, or emergency.
    ///
    ///             This function reverts if:
    ///             - The contract is not enabled
    ///             - The caller is neither admin, the configured config operator, nor emergency
    ///             - The asset/deposit period/operator combination does not exist
    ///             - The asset period is already disabled
    function disableAssetPeriod(
        IERC20 asset_,
        uint8 depositPeriod_,
        address operator_
    ) external givenEnabled onlyConfigAuthority(true) {
        uint256 tokenId = _getAssetPeriodTokenId(asset_, depositPeriod_, operator_);
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

    // ========== BORROWING FUNCTIONS ========== //

    /// @inheritdoc IDepositManager
    /// @dev        Notes:
    ///             - This function is only callable by addresses with the deposit operator role
    ///             - Given a low enough amount, the actual amount withdrawn may be 0. This function will not revert in such a case.
    ///
    ///             This function reverts if:
    ///             - The contract is not enabled
    ///             - The caller does not have the deposit operator role
    ///             - The requested amount is zero
    ///             - The recipient is the zero address or this contract
    ///             - The asset has not been added via addAsset()
    ///             - The amount exceeds the operator's available borrowing capacity
    ///             - The operator becomes insolvent after the withdrawal (assets + borrowed < liabilities)
    function borrowingWithdraw(
        BorrowingWithdrawParams calldata params_
    )
        external
        nonReentrant
        givenEnabled
        onlyRole(ROLE_DEPOSIT_OPERATOR)
        returns (uint256 actualAmount)
    {
        (, actualAmount) = _borrowingWithdraw(params_, false);
        return actualAmount;
    }

    /// @inheritdoc IDepositManagerV1_1
    /// @dev This function reverts if:
    ///      - The contract is disabled
    ///      - The caller lacks the deposit operator role
    ///      - The requested amount is zero
    ///      - The recipient is the zero address or this contract
    ///      - The asset is not configured
    ///      - Share output is requested without a configured vault
    ///      - Underlying output is requested for an asset that requires share withdrawal
    ///      - Borrowing capacity is insufficient
    ///      - The withdrawal would make the operator insolvent
    ///      - Conversion produces zero output
    function borrowingWithdraw(
        BorrowingWithdrawParams calldata params_,
        bool withdrawAsShares_
    )
        external
        nonReentrant
        givenEnabled
        onlyRole(ROLE_DEPOSIT_OPERATOR)
        returns (IERC20 tokenOut, uint256 amountOut)
    {
        (tokenOut, amountOut) = _borrowingWithdraw(params_, withdrawAsShares_);
        // Preserve legacy zero-output borrowing while the V1.1 overload requires delivery.
        // Reverting here also rolls back all accounting and events from the shared implementation.
        if (amountOut == 0) revert DepositManager_ZeroOutput();
        return (tokenOut, amountOut);
    }

    /// @notice Executes a borrowing withdrawal after external entry-point validation.
    function _borrowingWithdraw(
        BorrowingWithdrawParams calldata params_,
        bool withdrawAsShares_
    ) internal returns (IERC20 tokenOut, uint256 amountOut) {
        _validateWithdrawalInput(params_.recipient, params_.amount);
        _validateWithdrawalMode(params_.asset, withdrawAsShares_);

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

        // Record the requested debt before interacting with the share token or vault.
        bytes32 borrowingKey = _getAssetLiabilitiesKey(params_.asset, msg.sender);
        _borrowedAmounts[borrowingKey] += params_.amount;

        // Withdraw the funds from the vault to the recipient
        // The value returned can also be zero
        (, tokenOut, amountOut) = _withdrawAsset(
            params_.asset,
            params_.recipient,
            params_.amount,
            withdrawAsShares_
        );

        // Validate operator solvency after state updates
        _validateOperatorSolvency(params_.asset, msg.sender);

        // Emit event
        if (withdrawAsShares_) {
            emit BorrowingWithdrawal(
                address(params_.asset),
                msg.sender,
                params_.recipient,
                params_.amount,
                address(tokenOut),
                amountOut
            );
        } else {
            emit BorrowingWithdrawal(
                address(params_.asset),
                msg.sender,
                params_.recipient,
                amountOut
            );
        }

        return (tokenOut, amountOut);
    }

    /// @inheritdoc IDepositManager
    /// @dev        Notes:
    ///             - This function is only callable by addresses with the deposit operator role
    ///             - This function does not check for over-payment. It is expected to be handled by the calling contract.
    ///             - If the actual amount repaid is greater than the maximum amount provided, updates to the state variables are capped at the maximum amount.
    ///
    ///             This function reverts if:
    ///             - The contract is not enabled
    ///             - The caller does not have the deposit operator role
    ///             - The asset has not been added via addAsset()
    ///             - The payer has not approved DepositManager to spend the asset tokens
    ///             - The payer has insufficient asset token balance
    ///             - The asset is a fee-on-transfer token
    ///             - Zero shares would be deposited into the vault
    ///             - The operator becomes insolvent after the repayment (assets + borrowed < liabilities)
    function borrowingRepay(
        BorrowingRepayParams calldata params_
    )
        external
        nonReentrant
        givenEnabled
        onlyRole(ROLE_DEPOSIT_OPERATOR)
        returns (uint256 actualAmount)
    {
        // Validate that the asset is configured
        if (!_isConfiguredAsset(params_.asset)) revert AssetManager_NotConfigured();

        // Get the borrowing key
        bytes32 borrowingKey = _getAssetLiabilitiesKey(params_.asset, msg.sender);

        // Transfer funds from payer to this contract
        // This takes place before any state changes to avoid ERC777 re-entrancy
        // This purposefully does not check for over-payment, as it is expected to be handled by the calling contract
        (actualAmount, ) = _depositAsset(
            params_.asset,
            params_.payer,
            params_.amount,
            false // Do not enforce minimum deposit
        );

        // Update borrowed amount
        // Reduce by the actual amount, to avoid leakage
        // But cap at the max amount, to avoid an underflow for other loans
        _borrowedAmounts[borrowingKey] -= params_.maxAmount < actualAmount
            ? params_.maxAmount
            : actualAmount;

        // Validate operator solvency after borrowed amount change
        _validateOperatorSolvency(params_.asset, msg.sender);

        // Emit event
        emit BorrowingRepayment(address(params_.asset), msg.sender, params_.payer, actualAmount);

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
    ///             - The payer has insufficient receipt token balance
    ///             - The payer has not approved the caller to spend ERC6909 tokens
    ///             - The operator becomes insolvent after the default (assets + borrowed < liabilities)
    function borrowingDefault(
        BorrowingDefaultParams calldata params_
    ) external nonReentrant givenEnabled onlyRole(ROLE_DEPOSIT_OPERATOR) {
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

        // Update the asset liabilities for the caller (operator)
        _assetLiabilities[borrowingKey] -= params_.amount;
        // Default burns the matching receipt-backed claim, so this principal is no longer an
        // outstanding deposit even though the borrowed custody is not repaid.
        _decreaseAssetDepositCapUtilization(params_.asset, params_.amount);

        // Update the borrowed amount
        _borrowedAmounts[borrowingKey] -= params_.amount;

        // Validate operator solvency after borrowed amount change
        _validateOperatorSolvency(params_.asset, msg.sender);

        // Burn the receipt tokens from the payer after applying accounting effects. Any failure
        // reverts the complete transaction, including the preceding accounting updates.
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
        bytes32 assetLiabilitiesKey = _getAssetLiabilitiesKey(asset_, operator_);
        uint256 operatorLiabilities = _assetLiabilities[assetLiabilitiesKey];
        uint256 currentBorrowed = _borrowedAmounts[assetLiabilitiesKey];

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

        // The immutable ReceiptTokenManager is a trusted protocol dependency, and addAssetPeriod
        // requires admin authority. The token ID is unavailable until this call returns.
        // forge-lint: disable-start(reentrancy-no-eth)
        tokenId = _RECEIPT_TOKEN_MANAGER.createToken(
            asset_,
            depositPeriod_,
            operator_,
            operatorName
        );
        // forge-lint: disable-end(reentrancy-no-eth)

        // Record this token ID as owned by this contract
        _ownedTokenIds.add(tokenId);

        // Set the asset period data atomically
        _assetPeriods[tokenId] = AssetPeriod({
            isEnabled: true,
            depositPeriod: depositPeriod_,
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
    function getReceiptTokenIds() external view override returns (uint256[] memory) {
        return _ownedTokenIds.values();
    }

    /// @inheritdoc IDepositManager
    function getReceiptToken(
        IERC20 asset_,
        uint8 depositPeriod_,
        address operator_
    ) external view override returns (uint256 tokenId, address wrappedToken) {
        tokenId = getReceiptTokenId(asset_, depositPeriod_, operator_);
        wrappedToken = _RECEIPT_TOKEN_MANAGER.getWrappedToken(tokenId);
        return (tokenId, wrappedToken);
    }

    // ========== ERC165 ========== //

    /// @inheritdoc IERC165
    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        virtual
        override(EnablerV2, ReEnablerGracePeriod, BaseAssetManager)
        returns (bool)
    {
        return
            interfaceId == type(IDepositManager).interfaceId ||
            interfaceId == type(IDepositManagerV1_1).interfaceId ||
            interfaceId == type(IConfigOperator).interfaceId ||
            interfaceId == type(IVersioned).interfaceId ||
            BaseAssetManager.supportsInterface(interfaceId) ||
            ReEnablerGracePeriod.supportsInterface(interfaceId);
    }

    // ========== ADMIN FUNCTIONS ==========

    /// @notice Rescue an unmanaged ERC20 token sent to this contract and send it to TRSRY
    /// @dev    This function reverts if:
    ///         - The caller has neither the admin nor deposit_manager_admin role
    ///         - token_ is a configured asset, vault entry point, or stored share token
    ///         - token_ is the zero address
    ///
    ///         This function remains available while the contract is disabled because it cannot
    ///         move managed custody and always sends rescued tokens to TRSRY.
    ///
    /// @param  token_ The address of the ERC20 token to rescue
    function rescue(address token_) external nonReentrant {
        _requireDepositManagerAdminAuthority();

        if (_isManagedToken(token_)) revert DepositManager_CannotRescueAsset(token_);

        // Transfer the token balance to TRSRY
        // This will revert if the token is not a valid ERC20 or the zero address
        uint256 balance = ERC20(token_).balanceOf(address(this));
        address treasury = getModuleAddress(toKeycode("TRSRY"));
        if (balance > 0 && treasury != address(0)) {
            ERC20(token_).safeTransfer(treasury, balance);
            emit TokenRescued(token_, balance);
        }
    }

    // ========== CONFIGURATION AUTHORIZATION ========== //

    /// @notice Restricts mutable configuration to governance or the delegated timelock, with an
    ///         optional one-way emergency path for disabling asset periods.
    modifier onlyConfigAuthority(bool emergencyAllowed_) {
        _onlyConfigAuthority(emergencyAllowed_);
        _;
    }

    function _onlyConfigAuthority(bool emergencyAllowed_) internal view {
        if (
            !_isAdmin(msg.sender) &&
            !_isConfigOperator(msg.sender) &&
            (!emergencyAllowed_ || !_isEmergency(msg.sender))
        ) {
            revert ConfigOperator_Unauthorized(msg.sender);
        }
    }

    /// @inheritdoc ConfigOperatorSingleStep
    function _authorizeSetConfigOperator() internal view override returns (bool authorized) {
        _requireEnabled();
        _requireRole(msg.sender, ADMIN_ROLE);
        return true;
    }

    /// @notice Authorizes bounded re-enablement by governance or `deposit_manager_admin`.
    function _authorizeReEnable() internal view override {
        _requireDepositManagerAdminAuthority();
    }

    /// @notice Restricts operational administration to governance or `deposit_manager_admin`.
    function _requireDepositManagerAdminAuthority() internal view {
        _requireAuthorized(
            !_isAdmin(msg.sender) && !_hasRole(msg.sender, DEPOSIT_MANAGER_ADMIN_ROLE)
        );
    }

    /// @inheritdoc ReEnablerGracePeriod
    function _authorizeSetGracePeriod() internal view override onlyAdminRole {}
}
/// forge-lint: disable-end(asm-keccak256, mixed-case-function)
