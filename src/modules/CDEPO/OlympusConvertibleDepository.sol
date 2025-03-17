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

contract OlympusConvertibleDepository is CDEPOv1 {
    using SafeTransferLib for ERC20;
    using SafeTransferLib for ERC4626;
    using ClonesWithImmutableArgs for address;

    // ========== STATE VARIABLES ========== //

    address private immutable _TOKEN_IMPLEMENTATION;

    /// @notice List of supported input tokens
    address[] private _tokens;

    /// @notice Mapping of input token to clone address
    mapping(address => address) private _tokenToClone;

    /// @notice Mapping of input token to reclaim rate
    mapping(address => uint16) private _reclaimRates;

    /// @notice Mapping of input token to borrower to debt
    mapping(address => mapping(address => uint256)) private _debt;

    /// @notice Mapping of input token to total shares
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

    /// @notice Ensures the input token has been created
    modifier onlyCreatedToken(IERC20 inputToken_) {
        if (_tokenToClone[address(inputToken_)] == address(0)) revert CDEPO_UnsupportedToken();
        _;
    }

    // ========== MINT/BURN ========== //

    /// @inheritdoc IConvertibleDepository
    /// @dev        This function performs the following:
    ///             - Calls `mintFor` with the caller as the recipient
    function mint(IERC20 inputToken_, uint256 amount_) external override {
        mintFor(inputToken_, msg.sender, amount_);
    }

    /// @inheritdoc IConvertibleDepository
    /// @dev        This function performs the following:
    ///             - Transfers the input token from the `account_` address to the contract
    ///             - Deposits the input token into the ERC4626 vault
    ///             - Mints the corresponding amount of convertible deposit tokens to `account_`
    ///             - Emits a `Transfer` event
    ///
    ///             This function reverts if:
    ///             - The input token is not supported
    ///             - The amount is zero
    ///             - The `account_` address has not approved this contract to spend `asset`
    function mintFor(
        IERC20 inputToken_,
        address account_,
        uint256 amount_
    ) public override onlyCreatedToken(inputToken_) {
        // Validate that the amount is greater than zero
        if (amount_ == 0) revert CDEPO_InvalidArgs("amount");

        address cdToken = _tokenToClone[address(inputToken_)];
        ERC20 asset = ERC20(address(inputToken_));
        IERC4626 vault = ConvertibleDepositTokenClone(cdToken).vault();

        // Transfer asset from account
        asset.safeTransferFrom(account_, address(this), amount_);

        // Deposit the underlying asset into the vault and update the total shares
        asset.safeApprove(address(vault), amount_);
        _totalShares[address(inputToken_)] += vault.deposit(amount_, address(this));

        // Mint cdTokens to account
        ConvertibleDepositTokenClone(cdToken).mintFor(account_, amount_);
    }

    /// @inheritdoc IConvertibleDepository
    /// @dev        CD tokens are minted 1:1 with input token, so this function returns the amount of input token
    function previewMint(
        IERC20, // inputToken_
        uint256 amount_
    ) external view override returns (uint256 tokensOut) {
        // Validate that the amount is greater than zero
        if (amount_ == 0) revert CDEPO_InvalidArgs("amount");

        // Return the same amount of CD tokens
        return amount_;
    }

    /// @inheritdoc IConvertibleDepository
    /// @dev        This function performs the following:
    ///             - Validates that the input token is supported
    ///             - Burns the corresponding amount of convertible deposit tokens from the caller
    function burn(
        IERC20 inputToken_,
        uint256 amount_
    ) external override onlyCreatedToken(inputToken_) {
        address cdToken = _tokenToClone[address(inputToken_)];

        ConvertibleDepositTokenClone(cdToken).burnFrom(msg.sender, amount_);
    }

    // ========== RECLAIM/REDEEM ========== //

    /// @inheritdoc IConvertibleDepository
    /// @dev        This function performs the following:
    ///             - Calls `reclaimFor` with the caller as the address to reclaim the tokens to
    function reclaim(
        IERC20 inputToken_,
        uint256 amount_
    ) external override returns (uint256 tokensOut) {
        return reclaimFor(inputToken_, msg.sender, amount_);
    }

    /// @inheritdoc IConvertibleDepository
    /// @dev        This function performs the following:
    ///             - Validates that the input token is supported
    ///             - Validates that the `account_` address has approved this contract to spend the convertible deposit tokens
    ///             - Burns the CD tokens from the `account_` address
    ///             - Calculates the quantity of underlying asset to withdraw and return
    ///             - Returns the underlying asset to the caller
    ///
    ///             This function reverts if:
    ///             - The input token is not supported
    ///             - The amount is zero
    ///             - The `account_` address has not approved this contract to spend the convertible deposit tokens
    ///             - The quantity of vault shares for the amount is zero
    function reclaimFor(
        IERC20 inputToken_,
        address account_,
        uint256 amount_
    ) public override onlyCreatedToken(inputToken_) returns (uint256 tokensOut) {
        // Validate that the amount is greater than zero
        if (amount_ == 0) revert CDEPO_InvalidArgs("amount");

        address cdToken = _tokenToClone[address(inputToken_)];
        IERC4626 vault = ConvertibleDepositTokenClone(cdToken).vault();

        // Calculate the quantity of input token to withdraw and return
        // This will create a difference between the quantity of input tokens and the vault shares, which will be swept as yield
        uint256 discountedAssetsOut = previewReclaim(inputToken_, amount_);
        uint256 sharesOut = vault.previewWithdraw(discountedAssetsOut);
        _totalShares[address(inputToken_)] -= sharesOut;

        // We want to avoid situations where the amount is low enough to be < 1 share, as that would enable users to manipulate the accounting with many small calls
        // Although the ERC4626 vault will typically round up the number of shares withdrawn, if `discountedAssetsOut` is low enough, it will round down to 0 and `sharesOut` will be 0
        if (sharesOut == 0) revert CDEPO_InvalidArgs("shares");

        // Burn the CD tokens from `account_`
        // It will revert if the caller does not have enough CD tokens
        ConvertibleDepositTokenClone(cdToken).burnFrom(account_, amount_);

        // Return the underlying asset to the caller
        vault.withdraw(discountedAssetsOut, msg.sender, address(this));

        return discountedAssetsOut;
    }

    /// @inheritdoc IConvertibleDepository
    /// @dev        This function reverts if:
    ///             - The input token is not supported
    ///             - The amount is zero
    function previewReclaim(
        IERC20 inputToken_,
        uint256 amount_
    ) public view override onlyCreatedToken(inputToken_) returns (uint256 assetsOut) {
        if (amount_ == 0) revert CDEPO_InvalidArgs("amount");

        uint16 tokenReclaimRate = _reclaimRates[address(inputToken_)];

        // This is rounded down to keep assets in the vault, otherwise the contract may end up
        // in a state where there are not enough of the assets in the vault to redeem/reclaim
        assetsOut = FullMath.mulDiv(amount_, tokenReclaimRate, ONE_HUNDRED_PERCENT);

        // If the reclaimed amount is 0, revert
        if (assetsOut == 0) revert CDEPO_InvalidArgs("reclaimed amount");

        return assetsOut;
    }

    /// @inheritdoc IConvertibleDepository
    /// @dev        This function performs the following:
    ///             - Calls `redeemFor` with the caller as the address to redeem the tokens to
    function redeem(
        IERC20 inputToken_,
        uint256 amount_
    ) external override permissioned returns (uint256 tokensOut) {
        return redeemFor(inputToken_, msg.sender, amount_);
    }

    /// @inheritdoc IConvertibleDepository
    /// @dev        This function performs the following:
    ///             - Validates that the input token is supported
    ///             - Validates that the caller is permissioned
    ///             - Validates that the `account_` address has approved this contract to spend the convertible deposit tokens
    ///             - Burns the CD tokens from the `account_` address
    ///             - Calculates the quantity of underlying asset to withdraw and return
    ///             - Returns the underlying asset to the caller
    ///
    ///             This function reverts if:
    ///             - The input token is not supported
    ///             - The amount is zero
    ///             - The quantity of vault shares for the amount is zero
    ///             - The `account_` address has not approved this contract to spend the convertible deposit tokens
    function redeemFor(
        IERC20 inputToken_,
        address account_,
        uint256 amount_
    ) public override onlyCreatedToken(inputToken_) permissioned returns (uint256 tokensOut) {
        // Validate that the amount is greater than zero
        if (amount_ == 0) revert CDEPO_InvalidArgs("amount");

        address cdToken = _tokenToClone[address(inputToken_)];
        IERC4626 vault = ConvertibleDepositTokenClone(cdToken).vault();

        // Calculate the quantity of shares to transfer
        uint256 sharesOut = vault.previewWithdraw(amount_);
        _totalShares[address(inputToken_)] -= sharesOut;

        // We want to avoid situations where the amount is low enough to be < 1 share, as that would enable users to manipulate the accounting with many small calls
        // This is unlikely to happen, as the vault will typically round up the number of shares withdrawn
        // However a different ERC4626 vault implementation may trigger the condition
        if (sharesOut == 0) revert CDEPO_InvalidArgs("shares");

        // Burn the CD tokens from the `account_` address
        ConvertibleDepositTokenClone(cdToken).burnFrom(account_, amount_);

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
        IERC20 inputToken_,
        uint256 amount_
    ) external view override onlyCreatedToken(inputToken_) returns (uint256 tokensOut) {
        if (amount_ == 0) revert CDEPO_InvalidArgs("amount");

        tokensOut = amount_;
        return tokensOut;
    }

    // ========== LENDING ========== //

    /// @inheritdoc CDEPOv1
    function incurDebt(
        IERC20 inputToken_,
        uint256 amount_
    ) external override onlyCreatedToken(inputToken_) permissioned {
        // Validate that the amount is greater than zero
        if (amount_ == 0) revert CDEPO_InvalidArgs("amount");

        address cdToken = _tokenToClone[address(inputToken_)];

        // Validate that the amount is within the vault balance
        if (_totalShares[address(inputToken_)] < amount_) revert CDEPO_InsufficientBalance();

        // Update the debt
        _debt[address(inputToken_)][msg.sender] += amount_;

        // Transfer the vault asset to the caller
        ERC4626(address(ConvertibleDepositTokenClone(cdToken).vault())).safeTransfer(
            msg.sender,
            amount_
        );

        // Emit the event
        emit DebtIncurred(address(inputToken_), msg.sender, amount_);
    }

    /// @inheritdoc CDEPOv1
    /// @dev        This function performs the following:
    ///             - Validates that the input token is supported
    ///             - Validates that the caller is permissioned
    ///             - Validates that the amount is greater than zero
    ///             - Cap the repaid amount to the borrowed amount
    ///             - Reduces the debt
    ///             - Emits an event
    ///             - Returns the amount of vault asset that was repaid
    ///
    ///             This function reverts if:
    ///             - The input token is not supported
    ///             - The amount is zero
    ///             - The caller is not permissioned
    function repayDebt(
        IERC20 inputToken_,
        uint256 amount_
    )
        external
        virtual
        override
        onlyCreatedToken(inputToken_)
        permissioned
        returns (uint256 repaidAmount)
    {
        // Validate that the amount is greater than zero
        if (amount_ == 0) revert CDEPO_InvalidArgs("amount");

        address cdToken = _tokenToClone[address(inputToken_)];

        // Cap the repaid amount to the borrowed amount
        repaidAmount = _debt[address(inputToken_)][msg.sender] < amount_
            ? _debt[address(inputToken_)][msg.sender]
            : amount_;

        // Update the borrowed amount
        _debt[address(inputToken_)][msg.sender] -= repaidAmount;

        // Transfer the vault asset from the caller to the contract
        ERC4626(address(ConvertibleDepositTokenClone(cdToken).vault())).safeTransferFrom(
            msg.sender,
            address(this),
            repaidAmount
        );

        // Emit the event
        emit DebtRepaid(address(inputToken_), msg.sender, repaidAmount);

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
        IERC20 inputToken_,
        uint256 amount_
    )
        external
        virtual
        override
        onlyCreatedToken(inputToken_)
        permissioned
        returns (uint256 actualAmount)
    {
        // Validate that the amount is greater than zero
        if (amount_ == 0) revert CDEPO_InvalidArgs("amount");

        // Cap the reduced amount to the borrowed amount
        actualAmount = _debt[address(inputToken_)][msg.sender] < amount_
            ? _debt[address(inputToken_)][msg.sender]
            : amount_;

        // Update the debt
        _debt[address(inputToken_)][msg.sender] -= actualAmount;

        // Emit the event
        emit DebtReduced(address(inputToken_), msg.sender, actualAmount);

        // Return the amount of vault asset that was reduced
        return actualAmount;
    }

    // ========== YIELD MANAGER ========== //

    /// @inheritdoc CDEPOv1
    function sweepAllYield(address recipient_) external override permissioned {
        // Iterate over all supported tokens
        address[] memory tokens = _tokens;
        for (uint256 i; i < tokens.length; ++i) {
            sweepYield(IERC20(tokens[i]), recipient_);
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
        IERC20 inputToken_,
        address recipient_
    )
        public
        override
        permissioned
        onlyCreatedToken(inputToken_)
        returns (uint256 yieldReserve, uint256 yieldSReserve)
    {
        // Validate that the recipient_ address is not the zero address
        if (recipient_ == address(0)) revert CDEPO_InvalidArgs("recipient");

        address cdToken = _tokenToClone[address(inputToken_)];

        // Get vault from CDToken
        ERC4626 vault = ERC4626(address(ConvertibleDepositTokenClone(cdToken).vault()));

        (yieldReserve, yieldSReserve) = previewSweepYield(inputToken_);

        // Skip if there is no yield to sweep
        if (yieldSReserve == 0) return (0, 0);

        // Reduce the shares tracked by the contract
        _totalShares[address(inputToken_)] -= yieldSReserve;

        // Transfer the yield to the recipient
        vault.safeTransfer(recipient_, yieldSReserve);

        // Emit the event
        emit YieldSwept(address(inputToken_), recipient_, yieldReserve, yieldSReserve);

        return (yieldReserve, yieldSReserve);
    }

    /// @inheritdoc CDEPOv1
    function previewSweepYield(
        IERC20 inputToken_
    ) public view override returns (uint256 yieldReserve, uint256 yieldSReserve) {
        address cdToken = _tokenToClone[address(inputToken_)];

        // Get vault from CDToken
        IERC4626 vault = ConvertibleDepositTokenClone(cdToken).vault();

        // Calculate total assets in vault
        uint256 totalAssets = vault.convertToAssets(vault.balanceOf(address(this)));

        // Calculate total liabilities (outstanding cdTokens)
        uint256 totalLiabilities = ConvertibleDepositTokenClone(cdToken).totalSupply();

        // Calculate yield (assets in excess of liabilities)
        // The yield is the difference between the quantity of underlying assets in the vault and the quantity of CD tokens issued
        yieldReserve = totalAssets > totalLiabilities ? totalAssets - totalLiabilities : 0;

        // The yield in sReserve terms is the quantity of vault shares that would be burnt if yieldReserve was redeemed
        if (yieldReserve > 0) {
            yieldSReserve = vault.previewWithdraw(yieldReserve);
        }

        return (yieldReserve, yieldSReserve);
    }

    // ========== ADMIN ========== //

    function _setReclaimRate(IERC20 inputToken_, uint16 newReclaimRate_) internal {
        if (newReclaimRate_ > ONE_HUNDRED_PERCENT) revert CDEPO_InvalidArgs("Greater than 100%");

        _reclaimRates[address(inputToken_)] = newReclaimRate_;
        emit ReclaimRateUpdated(address(inputToken_), newReclaimRate_);
    }

    /// @inheritdoc CDEPOv1
    /// @dev        This function reverts if:
    ///             - The new reclaim rate is not within bounds
    ///             - The input token is not supported
    ///             - The caller is not permissioned
    function setReclaimRate(
        IERC20 inputToken_,
        uint16 newReclaimRate_
    ) external override permissioned onlyCreatedToken(inputToken_) {
        _setReclaimRate(inputToken_, newReclaimRate_);
    }

    /// @inheritdoc CDEPOv1
    /// @dev        This function reverts if:
    ///             - The reclaim rate is not within bounds
    ///             - The input token is already supported
    ///             - The caller is not permissioned
    function createToken(
        IERC4626 vault_,
        uint16 reclaimRate_
    ) external override permissioned returns (address) {
        // Get the input token from the vault
        address inputToken = vault_.asset();

        if (_tokenToClone[inputToken] != address(0)) revert CDEPO_InvalidArgs("Token exists");
        if (reclaimRate_ > ONE_HUNDRED_PERCENT) revert CDEPO_InvalidArgs("Rate exceeds 100%");

        // Get token name and symbol
        IERC20 inputTokenContract = IERC20(inputToken);
        string memory name = string(
            abi.encodePacked("Convertible Deposit ", inputTokenContract.name())
        );
        string memory symbol = string(abi.encodePacked("cd", inputTokenContract.symbol()));

        // Deploy clone with immutable args
        bytes memory data = abi.encode(
            name, // TODO check max length of name
            symbol, // TODO check max length of symbol
            inputTokenContract.decimals(),
            address(this),
            inputToken,
            address(vault_)
        );

        address cdToken = _TOKEN_IMPLEMENTATION.clone(data);

        _tokenToClone[inputToken] = cdToken;
        _tokens.push(inputToken);
        emit TokenAdded(inputToken, cdToken);

        _setReclaimRate(inputTokenContract, reclaimRate_);

        return cdToken;
    }

    // ========== VIEW FUNCTIONS ========== //

    /// @inheritdoc IConvertibleDepository
    function getTokens() external view override returns (address[] memory) {
        return _tokens;
    }

    /// @inheritdoc IConvertibleDepository
    ///
    /// @return     cdToken The address of the clone for the input token, or the zero address
    function getToken(IERC20 inputToken_) external view override returns (address cdToken) {
        cdToken = _tokenToClone[address(inputToken_)];

        return cdToken;
    }

    /// @inheritdoc IConvertibleDepository
    function isSupported(IERC20 inputToken_) external view override returns (bool) {
        return _tokenToClone[address(inputToken_)] != address(0);
    }

    /// @inheritdoc IConvertibleDepository
    ///
    /// @return     tokenReclaimRate The reclaim rate for the input token, or 0
    function reclaimRate(
        IERC20 inputToken_
    ) external view override onlyCreatedToken(inputToken_) returns (uint16 tokenReclaimRate) {
        tokenReclaimRate = _reclaimRates[address(inputToken_)];

        return tokenReclaimRate;
    }

    /// @inheritdoc CDEPOv1
    ///
    /// @return     tokenDebt The amount of debt owed by the borrower, or 0
    function debt(
        IERC20 inputToken_,
        address borrower_
    ) external view override onlyCreatedToken(inputToken_) returns (uint256 tokenDebt) {
        tokenDebt = _debt[address(inputToken_)][borrower_];

        return tokenDebt;
    }

    /// @inheritdoc CDEPOv1
    function getVaultShares(IERC20 inputToken_) external view override returns (uint256 shares) {
        shares = _totalShares[address(inputToken_)];

        return shares;
    }
}
