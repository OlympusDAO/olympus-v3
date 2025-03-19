// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

// Interfaces
import {IConvertibleDepository} from "./IConvertibleDepository.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";

// Libraries
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {FullMath} from "src/libraries/FullMath.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ClonesWithImmutableArgs} from "@clones-with-immutable-args-1.1.2/ClonesWithImmutableArgs.sol";

// Bophades
import {Kernel, Module, Keycode, toKeycode} from "src/Kernel.sol";
import {CDEPOv1} from "./CDEPO.v1.sol";
import {ConvertibleDepositTokenClone} from "./ConvertibleDepositTokenClone.sol";
import {IConvertibleDepositERC20} from "./IConvertibleDepositERC20.sol";

contract OlympusConvertibleDepository is CDEPOv1 {
    using SafeTransferLib for ERC20;
    using SafeTransferLib for ERC4626;
    using ClonesWithImmutableArgs for address;

    // ========== STATE VARIABLES ========== //

    address private immutable _TOKEN_IMPLEMENTATION;

    /// @notice List of supported deposit tokens
    IERC20[] private _depositTokens;

    /// @notice List of supported CD tokens
    IConvertibleDepositERC20[] private _cdTokens;

    /// @notice Mapping of deposit token to CD token
    mapping(address => address) private _depositToConvertible;

    /// @notice Mapping of CD token to deposit token
    mapping(address => address) private _convertibleToDeposit;

    /// @notice Mapping of CD token to reclaim rate
    mapping(address => uint16) private _reclaimRates;

    /// @notice Mapping of deposit token to borrower to debt
    mapping(address => mapping(address => uint256)) private _debt;

    /// @notice Mapping of deposit token to total shares
    mapping(address => uint256) private _totalShares;

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

    /// @notice Ensures the deposit token has been created
    modifier onlyDepositToken(IERC20 depositToken_) {
        if (_depositToConvertible[address(depositToken_)] == address(0))
            revert CDEPO_UnsupportedToken();
        _;
    }

    /// @notice Ensures the CD token has been created
    modifier onlyCDToken(IConvertibleDepositERC20 cdToken_) {
        if (_convertibleToDeposit[address(cdToken_)] == address(0)) revert CDEPO_UnsupportedToken();
        _;
    }

    // ========== MINT/BURN ========== //

    /// @inheritdoc IConvertibleDepository
    /// @dev        This function performs the following:
    ///             - Calls `mintFor` with the caller as the recipient
    function mint(IConvertibleDepositERC20 cdToken_, uint256 amount_) external override {
        mintFor(cdToken_, msg.sender, amount_);
    }

    /// @inheritdoc IConvertibleDepository
    /// @dev        This function performs the following:
    ///             - Transfers the deposit token from the `account_` address to the contract
    ///             - Deposits the deposit token into the ERC4626 vault
    ///             - Mints the corresponding amount of convertible deposit tokens to `account_`
    ///             - Emits a `Transfer` event
    ///
    ///             This function reverts if:
    ///             - The CD token is not supported
    ///             - The amount is zero
    ///             - The `account_` address has not approved this contract to spend the deposit token
    function mintFor(
        IConvertibleDepositERC20 cdToken_,
        address account_,
        uint256 amount_
    ) public override onlyCDToken(cdToken_) {
        // Validate that the amount is greater than zero
        if (amount_ == 0) revert CDEPO_InvalidArgs("amount");

        ERC20 asset = ERC20(address(cdToken_.asset()));
        IERC4626 vault = cdToken_.vault();

        // Transfer asset from account
        asset.safeTransferFrom(account_, address(this), amount_);

        // Deposit the underlying asset into the vault and update the total shares
        asset.safeApprove(address(vault), amount_);
        _totalShares[_convertibleToDeposit[address(cdToken_)]] += vault.deposit(
            amount_,
            address(this)
        );

        // Mint cdTokens to account
        cdToken_.mintFor(account_, amount_);
    }

    /// @inheritdoc IConvertibleDepository
    /// @dev        CD tokens are minted 1:1 with deposit token, so this function returns the amount of deposit token
    function previewMint(
        IConvertibleDepositERC20 cdToken_,
        uint256 amount_
    ) external view override onlyCDToken(cdToken_) returns (uint256 tokensOut) {
        // Validate that the amount is greater than zero
        if (amount_ == 0) revert CDEPO_InvalidArgs("amount");

        // Return the same amount of CD tokens
        return amount_;
    }

    /// @inheritdoc IConvertibleDepository
    /// @dev        This function performs the following:
    ///             - Validates that the CD token token is supported
    ///             - Burns the corresponding amount of CD tokens from the caller
    function burn(
        IConvertibleDepositERC20 cdToken_,
        uint256 amount_
    ) external override onlyCDToken(cdToken_) {
        address depositToken = _convertibleToDeposit[address(cdToken_)];

        // Decrease the total shares
        _totalShares[address(depositToken)] -= cdToken_.vault().previewWithdraw(amount_);

        // Burn the CD tokens from the caller
        cdToken_.burnFrom(msg.sender, amount_);
    }

    // ========== RECLAIM/REDEEM ========== //

    /// @inheritdoc IConvertibleDepository
    /// @dev        This function performs the following:
    ///             - Calls `reclaimFor` with the caller as the address to reclaim the tokens to
    function reclaim(
        IConvertibleDepositERC20 cdToken_,
        uint256 amount_
    ) external override returns (uint256 tokensOut) {
        return reclaimFor(cdToken_, msg.sender, amount_);
    }

    /// @inheritdoc IConvertibleDepository
    /// @dev        This function performs the following:
    ///             - Validates that the CD token is supported
    ///             - Validates that the `account_` address has approved this contract to spend the convertible deposit tokens
    ///             - Burns the CD tokens from the `account_` address
    ///             - Calculates the quantity of underlying asset to withdraw and return
    ///             - Returns the underlying asset to the caller
    ///
    ///             This function reverts if:
    ///             - The CD token is not supported
    ///             - The amount is zero
    ///             - The `account_` address has not approved this contract to spend the convertible deposit tokens
    ///             - The quantity of vault shares for the amount is zero
    function reclaimFor(
        IConvertibleDepositERC20 cdToken_,
        address account_,
        uint256 amount_
    ) public override onlyCDToken(cdToken_) returns (uint256 tokensOut) {
        // Validate that the amount is greater than zero
        if (amount_ == 0) revert CDEPO_InvalidArgs("amount");

        IERC4626 vault = cdToken_.vault();

        // Calculate the quantity of deposit token to withdraw and return
        // This will create a difference between the quantity of deposit tokens and the vault shares, which will be swept as yield
        uint256 discountedAssetsOut = previewReclaim(cdToken_, amount_);
        uint256 sharesOut = vault.previewWithdraw(discountedAssetsOut);
        _totalShares[_convertibleToDeposit[address(cdToken_)]] -= sharesOut;

        // We want to avoid situations where the amount is low enough to be < 1 share, as that would enable users to manipulate the accounting with many small calls
        // Although the ERC4626 vault will typically round up the number of shares withdrawn, if `discountedAssetsOut` is low enough, it will round down to 0 and `sharesOut` will be 0
        if (sharesOut == 0) revert CDEPO_InvalidArgs("shares");

        // Burn the CD tokens from `account_`
        // It will revert if the caller does not have enough CD tokens
        cdToken_.burnFrom(account_, amount_);

        // Return the underlying asset to the caller
        vault.withdraw(discountedAssetsOut, msg.sender, address(this));

        return discountedAssetsOut;
    }

    /// @inheritdoc IConvertibleDepository
    /// @dev        This function reverts if:
    ///             - The CD token is not supported
    ///             - The amount is zero
    function previewReclaim(
        IConvertibleDepositERC20 cdToken_,
        uint256 amount_
    ) public view override onlyCDToken(cdToken_) returns (uint256 assetsOut) {
        if (amount_ == 0) revert CDEPO_InvalidArgs("amount");

        uint16 tokenReclaimRate = _reclaimRates[address(cdToken_)];

        // This is rounded down to keep assets in the vault, otherwise the contract may end up
        // in a state where there are not enough of the assets in the vault to redeem/reclaim
        assetsOut = FullMath.mulDiv(amount_, tokenReclaimRate, ONE_HUNDRED_PERCENT);

        // If the reclaimed amount is 0, revert
        if (assetsOut == 0) revert CDEPO_InvalidArgs("reclaimed amount");

        return assetsOut;
    }

    /// @inheritdoc IConvertibleDepository
    /// @dev        This function performs the following:
    ///             - Validates that the CD token is supported
    ///             - Validates that the caller is permissioned
    ///             - Validates that the `account_` address has approved this contract to spend the convertible deposit tokens
    ///             - Burns the CD tokens from the `account_` address
    ///             - Calculates the quantity of underlying asset to withdraw and return
    ///             - Returns the underlying asset to the caller
    ///
    ///             This function reverts if:
    ///             - The CD token is not supported
    ///             - The amount is zero
    ///             - The quantity of vault shares for the amount is zero
    ///             - The `account_` address has not approved this contract to spend the convertible deposit tokens
    function redeemFor(
        IConvertibleDepositERC20 cdToken_,
        address account_,
        uint256 amount_
    ) public override onlyCDToken(cdToken_) permissioned returns (uint256 tokensOut) {
        // Validate that the amount is greater than zero
        if (amount_ == 0) revert CDEPO_InvalidArgs("amount");

        IERC4626 vault = cdToken_.vault();

        // Calculate the quantity of shares to transfer
        uint256 sharesOut = vault.previewWithdraw(amount_);
        _totalShares[_convertibleToDeposit[address(cdToken_)]] -= sharesOut;

        // We want to avoid situations where the amount is low enough to be < 1 share, as that would enable users to manipulate the accounting with many small calls
        // This is unlikely to happen, as the vault will typically round up the number of shares withdrawn
        // However a different ERC4626 vault implementation may trigger the condition
        if (sharesOut == 0) revert CDEPO_InvalidArgs("shares");

        // Burn the CD tokens from the `account_` address
        cdToken_.burnFrom(account_, amount_);

        // Return the underlying asset to the caller
        vault.withdraw(amount_, msg.sender, address(this));

        return amount_;
    }

    /// @inheritdoc IConvertibleDepository
    /// @dev        This function reverts if:
    ///             - The amount is zero
    ///
    ///             This function returns the same amount of underlying asset that would be redeemed, as the redeem function does not apply a discount.
    function previewRedeem(
        IConvertibleDepositERC20 cdToken_,
        uint256 amount_
    ) external view override onlyCDToken(cdToken_) returns (uint256 tokensOut) {
        if (amount_ == 0) revert CDEPO_InvalidArgs("amount");

        tokensOut = amount_;
        return tokensOut;
    }

    // ========== LENDING ========== //

    /// @inheritdoc CDEPOv1
    function incurDebt(
        IERC20 depositToken_,
        uint256 amount_
    ) external override onlyDepositToken(depositToken_) permissioned {
        // Validate that the amount is greater than zero
        if (amount_ == 0) revert CDEPO_InvalidArgs("amount");

        // Validate that the amount is within the vault balance
        if (_totalShares[address(depositToken_)] < amount_) revert CDEPO_InsufficientBalance();

        // Update the debt
        _debt[address(depositToken_)][msg.sender] += amount_;

        // Transfer the vault asset to the caller
        ERC4626(
            address(IConvertibleDepositERC20(_depositToConvertible[address(depositToken_)]).vault())
        ).safeTransfer(msg.sender, amount_);

        // Emit the event
        emit DebtIncurred(address(depositToken_), msg.sender, amount_);
    }

    /// @inheritdoc CDEPOv1
    /// @dev        This function performs the following:
    ///             - Validates that the deposit token is supported
    ///             - Validates that the caller is permissioned
    ///             - Validates that the amount is greater than zero
    ///             - Cap the repaid amount to the borrowed amount
    ///             - Reduces the debt
    ///             - Emits an event
    ///             - Returns the amount of vault asset that was repaid
    ///
    ///             This function reverts if:
    ///             - The deposit token is not supported
    ///             - The amount is zero
    ///             - The caller is not permissioned
    function repayDebt(
        IERC20 depositToken_,
        uint256 amount_
    )
        external
        virtual
        override
        onlyDepositToken(depositToken_)
        permissioned
        returns (uint256 repaidAmount)
    {
        // Validate that the amount is greater than zero
        if (amount_ == 0) revert CDEPO_InvalidArgs("amount");

        // Cap the repaid amount to the borrowed amount
        repaidAmount = _debt[address(depositToken_)][msg.sender] < amount_
            ? _debt[address(depositToken_)][msg.sender]
            : amount_;

        // Update the borrowed amount
        _debt[address(depositToken_)][msg.sender] -= repaidAmount;

        // Transfer the vault asset from the caller to the contract
        ERC4626(
            address(IConvertibleDepositERC20(_depositToConvertible[address(depositToken_)]).vault())
        ).safeTransferFrom(msg.sender, address(this), repaidAmount);

        // Emit the event
        emit DebtRepaid(address(depositToken_), msg.sender, repaidAmount);

        return repaidAmount;
    }

    /// @inheritdoc CDEPOv1
    /// @dev        This function performs the following:
    ///             - Validates that the amount is greater than zero
    ///             - Cap the reduced amount to the borrowed amount
    ///             - Reduces the debt
    ///             - Emits an event
    ///             - Returns the amount of vault asset that was reduced
    function reduceDebt(
        IERC20 depositToken_,
        uint256 amount_
    )
        external
        virtual
        override
        onlyDepositToken(depositToken_)
        permissioned
        returns (uint256 actualAmount)
    {
        // Validate that the amount is greater than zero
        if (amount_ == 0) revert CDEPO_InvalidArgs("amount");

        // Cap the reduced amount to the borrowed amount
        actualAmount = _debt[address(depositToken_)][msg.sender] < amount_
            ? _debt[address(depositToken_)][msg.sender]
            : amount_;

        // Update the debt
        _debt[address(depositToken_)][msg.sender] -= actualAmount;

        // Emit the event
        emit DebtReduced(address(depositToken_), msg.sender, actualAmount);

        // Return the amount of vault asset that was reduced
        return actualAmount;
    }

    // ========== YIELD MANAGER ========== //

    /// @inheritdoc CDEPOv1
    function sweepAllYield(address recipient_) external override permissioned {
        // Iterate over all supported tokens
        IERC20[] memory tokens = _depositTokens;
        for (uint256 i; i < tokens.length; ++i) {
            sweepYield(tokens[i], recipient_);
        }
    }

    /// @inheritdoc CDEPOv1
    /// @dev        This function performs the following:
    ///             - Validates that the caller has the correct role
    ///             - Computes the amount of yield that would be swept
    ///             - Reduces the shares tracked by the contract
    ///             - Transfers the yield to the caller
    ///             - Emits an event
    ///
    ///             This function reverts if:
    ///             - The caller is not permissioned
    ///             - The recipient_ address is the zero address
    function sweepYield(
        IERC20 depositToken_,
        address recipient_
    )
        public
        override
        permissioned
        onlyDepositToken(depositToken_)
        returns (uint256 yieldReserve, uint256 yieldSReserve)
    {
        // Validate that the recipient_ address is not the zero address
        if (recipient_ == address(0)) revert CDEPO_InvalidArgs("recipient");

        address cdToken = _depositToConvertible[address(depositToken_)];

        // Get vault from CDToken
        ERC4626 vault = ERC4626(address(ConvertibleDepositTokenClone(cdToken).vault()));

        (yieldReserve, yieldSReserve) = previewSweepYield(depositToken_);

        // Skip if there is no yield to sweep
        if (yieldSReserve == 0) return (0, 0);

        // Reduce the shares tracked by the contract
        _totalShares[address(depositToken_)] -= yieldSReserve;

        // Transfer the yield to the recipient
        vault.safeTransfer(recipient_, yieldSReserve);

        // Emit the event
        emit YieldSwept(address(depositToken_), recipient_, yieldReserve, yieldSReserve);

        return (yieldReserve, yieldSReserve);
    }

    /// @inheritdoc CDEPOv1
    /// @dev        This function reverts if:
    ///             - The deposit token is not supported
    function previewSweepYield(
        IERC20 depositToken_
    )
        public
        view
        override
        onlyDepositToken(depositToken_)
        returns (uint256 yieldReserve, uint256 yieldSReserve)
    {
        IConvertibleDepositERC20 cdToken = IConvertibleDepositERC20(
            _depositToConvertible[address(depositToken_)]
        );

        // Get vault from CDToken
        IERC4626 vault = cdToken.vault();

        // The yield is the difference between the quantity of underlying assets in the vault and the quantity of CD tokens issued
        yieldReserve =
            vault.previewRedeem(_totalShares[address(depositToken_)]) -
            cdToken.totalSupply();

        // The yield in sReserve terms is the quantity of vault shares that would be burnt if yieldReserve was redeemed
        if (yieldReserve > 0) {
            yieldSReserve = vault.previewWithdraw(yieldReserve);
        }

        return (yieldReserve, yieldSReserve);
    }

    // ========== ADMIN ========== //

    function _setReclaimRate(IConvertibleDepositERC20 cdToken_, uint16 newReclaimRate_) internal {
        if (newReclaimRate_ > ONE_HUNDRED_PERCENT) revert CDEPO_InvalidArgs("Greater than 100%");

        _reclaimRates[address(cdToken_)] = newReclaimRate_;
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
    ///             - The deposit token is already supported
    ///             - The caller is not permissioned
    function create(
        IERC4626 vault_,
        uint16 reclaimRate_
    ) external override permissioned returns (IConvertibleDepositERC20) {
        // Get the deposit token from the vault
        address depositToken = vault_.asset();

        if (_depositToConvertible[depositToken] != address(0)) revert CDEPO_InvalidArgs("exists");
        if (reclaimRate_ > ONE_HUNDRED_PERCENT) revert CDEPO_InvalidArgs("reclaimRate");

        // Get token name and symbol
        IERC20 depositTokenContract = IERC20(depositToken);

        // Deploy clone with immutable args
        bytes memory data = abi.encodePacked(
            _concatenateAndTruncate("Convertible ", depositTokenContract.name()), // Name
            _concatenateAndTruncate("cd", depositTokenContract.symbol()), // Symbol
            depositTokenContract.decimals(), // Decimals
            address(this), // Owner
            depositToken, // Asset
            address(vault_) // Vault
        );

        address cdToken = _TOKEN_IMPLEMENTATION.clone(data);

        _depositToConvertible[depositToken] = cdToken;
        _convertibleToDeposit[cdToken] = depositToken;
        _depositTokens.push(depositTokenContract);
        _cdTokens.push(IConvertibleDepositERC20(cdToken));
        emit TokenAdded(depositToken, cdToken);

        _setReclaimRate(IConvertibleDepositERC20(cdToken), reclaimRate_);

        return IConvertibleDepositERC20(cdToken);
    }

    function _concatenateAndTruncate(
        string memory a_,
        string memory b_
    ) internal pure returns (string memory) {
        bytes32 nameBytes = bytes32(abi.encodePacked(a_, b_));

        return string(abi.encodePacked(nameBytes));
    }

    // ========== VIEW FUNCTIONS ========== //

    /// @inheritdoc IConvertibleDepository
    function getDepositTokens() external view override returns (IERC20[] memory) {
        return _depositTokens;
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
        address depositToken_
    ) external view override returns (IConvertibleDepositERC20 cdToken) {
        cdToken = IConvertibleDepositERC20(_depositToConvertible[depositToken_]);

        return cdToken;
    }

    /// @inheritdoc IConvertibleDepository
    ///
    /// @return     depositToken    The address of the deposit token, or the zero address
    function getDepositToken(
        address cdToken_
    ) external view override returns (IERC20 depositToken) {
        depositToken = IERC20(_convertibleToDeposit[cdToken_]);

        return depositToken;
    }

    /// @inheritdoc IConvertibleDepository
    function isDepositToken(address depositToken_) external view override returns (bool) {
        return _depositToConvertible[depositToken_] != address(0);
    }

    function isConvertibleDepositToken(address cdToken_) external view override returns (bool) {
        return _convertibleToDeposit[cdToken_] != address(0);
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
        tokenReclaimRate = _reclaimRates[cdToken_];

        return tokenReclaimRate;
    }

    /// @inheritdoc CDEPOv1
    ///
    /// @return     tokenDebt The amount of debt owed by the borrower, or 0
    function debt(
        IERC20 depositToken_,
        address borrower_
    ) external view override onlyDepositToken(depositToken_) returns (uint256 tokenDebt) {
        tokenDebt = _debt[address(depositToken_)][borrower_];

        return tokenDebt;
    }

    /// @inheritdoc CDEPOv1
    function getVaultShares(IERC20 depositToken_) external view override returns (uint256 shares) {
        shares = _totalShares[address(depositToken_)];

        return shares;
    }
}
