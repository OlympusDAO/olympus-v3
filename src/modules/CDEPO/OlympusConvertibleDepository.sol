// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

// Interfaces
import {IConvertibleDepository} from "./IConvertibleDepository.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";

// Libraries
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ClonesWithImmutableArgs} from "@clones-with-immutable-args-1.1.2/ClonesWithImmutableArgs.sol";
import {uint2str} from "src/libraries/Uint2Str.sol";

// Bophades
import {Kernel, Module, Keycode, toKeycode} from "src/Kernel.sol";
import {CDEPOv1} from "./CDEPO.v1.sol";
import {ConvertibleDepositTokenClone} from "./ConvertibleDepositTokenClone.sol";
import {IConvertibleDepositERC20} from "./IConvertibleDepositERC20.sol";

/// @title  Olympus Convertible Depository
/// @notice Implementation of the {IConvertibleDepository} interface
///         This contract provides the backend management of CD tokens
contract OlympusConvertibleDepository is CDEPOv1 {
    using SafeTransferLib for ERC20;
    using SafeTransferLib for ERC4626;
    using ClonesWithImmutableArgs for address;

    // ========== STATE VARIABLES ========== //

    /// @notice The address of the implementation of the {ConvertibleDepositTokenClone} contract
    address private immutable _TOKEN_IMPLEMENTATION;

    /// @notice List of supported deposit tokens
    IERC20[] private _depositTokens;

    /// @notice List of supported deposit tokens and their supported periods
    mapping(IERC20 => uint8[]) private _depositTokenPeriods;

    /// @notice List of supported vault tokens
    IERC4626[] private _vaultTokens;

    /// @notice List of supported CD tokens
    IConvertibleDepositERC20[] private _cdTokens;

    /// @notice Mapping of deposit token and period months to CD token
    mapping(IERC20 => mapping(uint8 => IConvertibleDepositERC20)) private _depositToConvertible;

    /// @notice Mapping of CD token to deposit token
    /// @dev    This mapping is required to validate that the CD token is created by the contract
    mapping(IConvertibleDepositERC20 => IERC20) private _convertibleToDeposit;

    /// @notice Mapping of CD token to reclaim rate
    mapping(IConvertibleDepositERC20 => uint16) private _reclaimRates;

    /// @notice Mapping of vault token to borrower to debt
    mapping(IERC4626 => mapping(address => uint256)) private _debt;

    /// @notice Mapping of vault token to total shares
    /// @dev    This is used to track deposited vault shares for each vault token
    mapping(IERC4626 => uint256) private _totalShares;

    // TODO consider tracking the assets for each vault, rather than the shares. Any remaining shares can be swept as yield. Avoids rounding errors.

    // ========== CONSTRUCTOR ========== //

    constructor(Kernel kernel_) Module(kernel_) {
        _TOKEN_IMPLEMENTATION = address(new ConvertibleDepositTokenClone());
    }

    // ========== MODULE FUNCTIONS ========== //

    /// @inheritdoc Module
    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("CDEPO");
    }

    /// @inheritdoc Module
    function VERSION() public pure override returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;
    }

    // ========== MODIFIERS ========== //

    /// @notice Ensures the deposit token has had a CD token created
    modifier onlyDepositToken(IERC20 depositToken_, uint8 periodMonths_) {
        // Checks that the ERC20 deposit token has had a CD token created
        if (address(_depositToConvertible[depositToken_][periodMonths_]) == address(0))
            revert CDEPO_UnsupportedToken();
        _;
    }

    /// @notice Ensures the CD token has been created
    modifier onlyCDToken(IConvertibleDepositERC20 cdToken_) {
        /// Checks that the given CD token has been created
        if (address(_convertibleToDeposit[cdToken_]) == address(0)) revert CDEPO_UnsupportedToken();
        _;
    }

    /// @notice Ensures the vault token has had a CD token created for its underlying asset
    modifier onlyVaultToken(IERC4626 vaultToken_) {
        // Check that the vault token is supported
        bool isSupported = false;
        for (uint256 i; i < _vaultTokens.length; ++i) {
            if (_vaultTokens[i] == vaultToken_) {
                isSupported = true;
                break;
            }
        }
        if (!isSupported) revert CDEPO_UnsupportedToken();
        _;
    }

    // ========== MINT/BURN ========== //

    /// @inheritdoc IConvertibleDepository
    /// @dev        This function performs the following:
    ///             - Mints the corresponding amount of convertible deposit tokens to `account_`
    ///
    ///             This function is permissioned, and the caller is expected to handle
    function mintFor(
        IConvertibleDepositERC20 cdToken_,
        address account_,
        uint256 amount_
    ) external override permissioned onlyCDToken(cdToken_) {
        cdToken_.mintFor(account_, amount_);
    }

    /// @inheritdoc IConvertibleDepository
    /// @dev        This function performs the following:
    ///             - Validates that the CD token token is supported
    ///             - Burns the corresponding amount of CD tokens from the caller
    ///
    ///             This function is permissioned, and the caller is expected to handle
    function burnFrom(
        IConvertibleDepositERC20 cdToken_,
        address account_,
        uint256 amount_
    ) external override permissioned onlyCDToken(cdToken_) {
        cdToken_.burnFrom(account_, amount_);
    }

    // ========== LENDING ========== //

    /// @inheritdoc CDEPOv1
    /// @dev        This function performs the following:
    ///             - Validates that the vault token is supported
    ///             - Validates that the caller is permissioned
    ///             - Validates that the amount is greater than zero
    ///             - Validates that the amount is within the vault balance
    ///             - Updates the debt
    ///             - Transfers the vault asset to the caller
    ///             - Emits an event
    ///
    ///             This function reverts if:
    ///             - The vault token is not supported
    ///             - The amount is zero
    ///             - The caller is not permissioned
    function incurDebt(
        IERC4626 vaultToken_,
        uint256 amount_
    ) external override onlyVaultToken(vaultToken_) permissioned {
        // Validate that the amount is greater than zero
        if (amount_ == 0) revert CDEPO_InvalidArgs("amount");

        // Validate that the amount is within the vault balance
        if (_totalShares[vaultToken_] < amount_) revert CDEPO_InsufficientBalance();

        // Update the debt
        _debt[vaultToken_][msg.sender] += amount_;

        // Transfer the vault asset to the caller
        ERC4626(address(vaultToken_)).safeTransfer(msg.sender, amount_);

        // Emit the event
        emit DebtIncurred(address(vaultToken_), msg.sender, amount_);
    }

    /// @inheritdoc CDEPOv1
    /// @dev        This function performs the following:
    ///             - Validates that the vault token is supported
    ///             - Validates that the caller is permissioned
    ///             - Validates that the amount is greater than zero
    ///             - Caps the repaid amount to the borrowed amount
    ///             - Reduces the debt
    ///             - Emits an event
    ///             - Returns the amount of vault asset that was repaid
    ///
    ///             This function reverts if:
    ///             - The vault token is not supported
    ///             - The amount is zero
    ///             - The caller is not permissioned
    function repayDebt(
        IERC4626 vaultToken_,
        uint256 amount_
    )
        external
        virtual
        override
        onlyVaultToken(vaultToken_)
        permissioned
        returns (uint256 repaidAmount)
    {
        // Validate that the amount is greater than zero
        if (amount_ == 0) revert CDEPO_InvalidArgs("amount");

        // Cap the repaid amount to the borrowed amount
        repaidAmount = _debt[vaultToken_][msg.sender] < amount_
            ? _debt[vaultToken_][msg.sender]
            : amount_;

        // Update the borrowed amount
        _debt[vaultToken_][msg.sender] -= repaidAmount;

        // Transfer the vault asset from the caller to the contract
        ERC4626(address(vaultToken_)).safeTransferFrom(msg.sender, address(this), repaidAmount);

        // Emit the event
        emit DebtRepaid(address(vaultToken_), msg.sender, repaidAmount);

        return repaidAmount;
    }

    /// @inheritdoc CDEPOv1
    /// @dev        This function performs the following:
    ///             - Validates that the vault token is supported
    ///             - Validates that the amount is greater than zero
    ///             - Cap the reduced amount to the borrowed amount
    ///             - Reduces the debt
    ///             - Emits an event
    ///             - Returns the amount of vault asset that was reduced
    ///
    ///             This function reverts if:
    ///             - The vault token is not supported
    ///             - The amount is zero
    function reduceDebt(
        IERC4626 vaultToken_,
        uint256 amount_
    )
        external
        virtual
        override
        onlyVaultToken(vaultToken_)
        permissioned
        returns (uint256 actualAmount)
    {
        // Validate that the amount is greater than zero
        if (amount_ == 0) revert CDEPO_InvalidArgs("amount");

        // Cap the reduced amount to the borrowed amount
        actualAmount = _debt[vaultToken_][msg.sender] < amount_
            ? _debt[vaultToken_][msg.sender]
            : amount_;

        // Update the debt
        _debt[vaultToken_][msg.sender] -= actualAmount;

        // Emit the event
        emit DebtReduced(address(vaultToken_), msg.sender, actualAmount);

        // Return the amount of vault asset that was reduced
        return actualAmount;
    }

    // ========== YIELD MANAGER ========== //

    /// @inheritdoc CDEPOv1
    function sweepAllYield(address recipient_) external override permissioned {
        // Iterate over all supported CD tokens
        IConvertibleDepositERC20[] memory cdTokens = _cdTokens;
        for (uint256 i; i < cdTokens.length; ++i) {
            sweepYield(cdTokens[i], recipient_);
        }
    }

    /// @inheritdoc CDEPOv1
    /// @dev        This function performs the following:
    ///             - Validates that the CD token is supported
    ///             - Validates that the caller is permissioned
    ///             - Computes the amount of yield that would be swept
    ///             - Reduces the shares tracked by the contract
    ///             - Transfers the yield to the recipient
    ///             - Emits an event
    ///
    ///             This function reverts if:
    ///             - The CD token is not supported
    ///             - The caller is not permissioned
    ///             - The recipient_ address is the zero address
    function sweepYield(
        IConvertibleDepositERC20 cdToken_,
        address recipient_
    )
        public
        override
        permissioned
        onlyCDToken(cdToken_)
        returns (uint256 yieldReserve, uint256 yieldSReserve)
    {
        // Validate that the recipient_ address is not the zero address
        if (recipient_ == address(0)) revert CDEPO_InvalidArgs("recipient");

        (yieldReserve, yieldSReserve) = previewSweepYield(cdToken_);

        // Skip if there is no yield to sweep
        if (yieldSReserve == 0) return (0, 0);

        // Reduce the shares tracked by the contract
        _totalShares[cdToken_.vault()] -= yieldSReserve;

        // Transfer the yield to the recipient
        ERC4626(address(cdToken_.vault())).safeTransfer(recipient_, yieldSReserve);

        // Emit the event
        emit YieldSwept(address(cdToken_.vault()), recipient_, yieldReserve, yieldSReserve);

        return (yieldReserve, yieldSReserve);
    }

    /// @inheritdoc CDEPOv1
    /// @dev        This function reverts if:
    ///             - The CD token is not supported
    function previewSweepYield(
        IConvertibleDepositERC20 cdToken_
    )
        public
        view
        override
        onlyCDToken(cdToken_)
        returns (uint256 yieldReserve, uint256 yieldSReserve)
    {
        IERC4626 vaultToken = cdToken_.vault();

        // The yield is the difference between the quantity of underlying assets in the vault and the quantity of CD tokens issued
        yieldReserve = vaultToken.previewRedeem(_totalShares[vaultToken]) - cdToken_.totalSupply();

        // The yield in sReserve terms is the quantity of vault shares that would be burnt if yieldReserve was redeemed
        if (yieldReserve > 0) {
            yieldSReserve = vaultToken.previewWithdraw(yieldReserve);
        }

        return (yieldReserve, yieldSReserve);
    }

    // ========== ADMIN ========== //

    function _setReclaimRate(IConvertibleDepositERC20 cdToken_, uint16 newReclaimRate_) internal {
        if (newReclaimRate_ > ONE_HUNDRED_PERCENT) revert CDEPO_InvalidArgs("Greater than 100%");

        _reclaimRates[cdToken_] = newReclaimRate_;
        emit ReclaimRateUpdated(address(cdToken_), newReclaimRate_);
    }

    /// @inheritdoc CDEPOv1
    /// @dev        This function reverts if:
    ///             - The new reclaim rate is not within bounds
    ///             - The CD token is not supported
    ///             - The caller is not permissioned
    function setReclaimRate(
        IConvertibleDepositERC20 cdToken_,
        uint16 newReclaimRate_
    ) external override permissioned onlyCDToken(cdToken_) {
        _setReclaimRate(cdToken_, newReclaimRate_);
    }

    /// @inheritdoc CDEPOv1
    /// @dev        This function reverts if:
    ///             - The reclaim rate is not within bounds
    ///             - The period months is not greater than 0
    ///             - The deposit token is already supported
    ///             - The caller is not permissioned
    function create(
        IERC4626 vault_,
        uint8 periodMonths_,
        uint16 reclaimRate_
    ) external override permissioned returns (IConvertibleDepositERC20) {
        // Validate that the period months is greater than 0
        if (periodMonths_ == 0) revert CDEPO_InvalidArgs("periodMonths");

        // Get the deposit token from the vault
        IERC20 depositTokenContract = IERC20(vault_.asset());

        if (address(_depositToConvertible[depositTokenContract][periodMonths_]) != address(0))
            revert CDEPO_InvalidArgs("exists");
        if (reclaimRate_ > ONE_HUNDRED_PERCENT) revert CDEPO_InvalidArgs("reclaimRate");

        // Get token name and symbol

        // Deploy clone with immutable args
        bytes memory data = abi.encodePacked(
            _truncate32(
                string.concat(
                    "Convertible ",
                    depositTokenContract.name(),
                    " - ",
                    uint2str(periodMonths_),
                    " months"
                )
            ), // Name
            _truncate32(
                string.concat(
                    "cd",
                    depositTokenContract.symbol(),
                    "-",
                    uint2str(periodMonths_),
                    "m"
                )
            ), // Symbol
            depositTokenContract.decimals(), // Decimals
            address(this), // Owner
            address(depositTokenContract), // Asset
            address(vault_), // Vault
            periodMonths_ // Period Months
        );

        IConvertibleDepositERC20 cdToken = IConvertibleDepositERC20(
            _TOKEN_IMPLEMENTATION.clone(data)
        );

        _depositToConvertible[depositTokenContract][periodMonths_] = cdToken;
        _convertibleToDeposit[cdToken] = depositTokenContract;

        // Add the deposit token and period months to the list of supported deposit tokens
        // We know that the deposit token + period months combo is not supported from the validation check
        _addDepositToken(depositTokenContract);
        _depositTokenPeriods[depositTokenContract].push(periodMonths_);

        // Add the vault token to the list of supported vault tokens
        _addVaultToken(vault_);

        _cdTokens.push(cdToken);
        emit TokenCreated(address(depositTokenContract), periodMonths_, address(cdToken));

        _setReclaimRate(cdToken, reclaimRate_);

        return cdToken;
    }

    function _addDepositToken(IERC20 depositToken_) internal {
        // Add the deposit token to the list of supported deposit tokens, if it doesn't exist
        for (uint256 i; i < _depositTokens.length; ++i) {
            if (_depositTokens[i] == depositToken_) {
                return;
            }
        }

        _depositTokens.push(depositToken_);
    }

    function _addVaultToken(IERC4626 vaultToken_) internal {
        // Add the vault token to the list of supported vault tokens, if it doesn't exist
        for (uint256 i; i < _vaultTokens.length; ++i) {
            if (_vaultTokens[i] == vaultToken_) {
                return;
            }
        }

        _vaultTokens.push(vaultToken_);
    }

    function _truncate32(string memory str_) internal pure returns (string memory) {
        bytes32 nameBytes = bytes32(abi.encodePacked(str_));

        return string(abi.encodePacked(nameBytes));
    }

    /// @inheritdoc CDEPOv1
    /// @dev        This function reverts if:
    ///             - The caller is not permissioned
    ///             - The CD token is not supported
    function withdraw(
        IConvertibleDepositERC20 cdToken_,
        uint256 amount_
    ) external override permissioned onlyCDToken(cdToken_) {
        // Transfer the token from the contract to the caller
        uint256 amountInShares = cdToken_.vault().withdraw(amount_, msg.sender, address(this));

        // Update the total shares
        _totalShares[cdToken_.vault()] -= amountInShares;

        // Emit the event
        emit TokenWithdrawn(address(cdToken_.asset()), msg.sender, amount_);
    }

    // ========== VIEW FUNCTIONS ========== //

    /// @inheritdoc IConvertibleDepository
    function getDepositTokens()
        external
        view
        override
        returns (IConvertibleDepository.DepositToken[] memory depositTokens_)
    {
        depositTokens_ = new IConvertibleDepository.DepositToken[](_depositTokens.length);

        for (uint256 i; i < _depositTokens.length; ++i) {
            IERC20 depositToken = _depositTokens[i];

            depositTokens_[i] = IConvertibleDepository.DepositToken({
                token: depositToken,
                periods: _depositTokenPeriods[depositToken]
            });
        }

        return depositTokens_;
    }

    /// @inheritdoc IConvertibleDepository
    function getDepositTokenPeriods(
        address depositToken_
    ) external view override returns (uint8[] memory periods) {
        periods = _depositTokenPeriods[IERC20(depositToken_)];

        return periods;
    }

    /// @inheritdoc CDEPOv1
    function getVaultTokens() external view override returns (IERC4626[] memory) {
        return _vaultTokens;
    }

    /// @inheritdoc IConvertibleDepository
    function getConvertibleDepositTokens()
        external
        view
        override
        returns (IConvertibleDepositERC20[] memory)
    {
        return _cdTokens;
    }

    /// @inheritdoc IConvertibleDepository
    ///
    /// @return     cdToken The address of the convertible deposit token for the deposit token, or the zero address
    function getConvertibleDepositToken(
        address depositToken_,
        uint8 periodMonths_
    ) external view override returns (IConvertibleDepositERC20 cdToken) {
        cdToken = _depositToConvertible[IERC20(depositToken_)][periodMonths_];

        return cdToken;
    }

    /// @inheritdoc IConvertibleDepository
    ///
    /// @return     depositToken    The address of the deposit token, or the zero address
    function getDepositToken(
        address cdToken_
    ) external view override returns (IERC20 depositToken) {
        depositToken = _convertibleToDeposit[IConvertibleDepositERC20(cdToken_)];

        return depositToken;
    }

    /// @inheritdoc IConvertibleDepository
    function isDepositToken(
        address depositToken_,
        uint8 periodMonths_
    ) external view override returns (bool) {
        return address(_depositToConvertible[IERC20(depositToken_)][periodMonths_]) != address(0);
    }

    /// @inheritdoc IConvertibleDepository
    function isConvertibleDepositToken(address cdToken_) external view override returns (bool) {
        return address(_convertibleToDeposit[IConvertibleDepositERC20(cdToken_)]) != address(0);
    }

    /// @inheritdoc IConvertibleDepository
    ///
    /// @return     tokenReclaimRate The reclaim rate for the input token, or 0
    function reclaimRate(
        address cdToken_
    )
        external
        view
        override
        onlyCDToken(IConvertibleDepositERC20(cdToken_))
        returns (uint16 tokenReclaimRate)
    {
        tokenReclaimRate = _reclaimRates[IConvertibleDepositERC20(cdToken_)];

        return tokenReclaimRate;
    }

    /// @inheritdoc CDEPOv1
    ///
    /// @return     tokenDebt The amount of debt owed by the borrower, or 0
    function getDebt(
        IERC4626 vaultToken_,
        address borrower_
    ) external view override returns (uint256 tokenDebt) {
        tokenDebt = _debt[vaultToken_][borrower_];

        return tokenDebt;
    }

    /// @inheritdoc CDEPOv1
    ///
    /// @return     shares The amount of shares, or 0
    function getVaultShares(IERC4626 vaultToken_) external view override returns (uint256 shares) {
        shares = _totalShares[vaultToken_];

        return shares;
    }
}
