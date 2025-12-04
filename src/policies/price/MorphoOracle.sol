// SPDX-License-Identifier: AGPL-3.0
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.15;

// Interfaces
import {IOracle} from "src/interfaces/morpho/IOracle.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IERC165} from "@openzeppelin-4.8.0/interfaces/IERC165.sol";

// Libraries
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";
import {FullMath} from "src/libraries/FullMath.sol";

// Bophades
import {Kernel, Policy, Keycode, toKeycode, Permissions, Module} from "src/Kernel.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";

/// @title  MorphoOracle
/// @author OlympusDAO
/// @notice Oracle adapter that implements Morpho's IOracle interface by calling PRICE.getPrice() for collateral and loan tokens
/// @dev    Returns the price of 1 collateral token quoted in loan tokens, scaled by 1e36 as required by Morpho's IOracle interface.
///         The price precision is 36 + loan_token_decimals - collateral_token_decimals.
contract MorphoOracle is Policy, PolicyEnabler, IOracle {
    using FullMath for uint256;

    // ========== STATE ========== //

    /// @notice The PRICE module
    IPRICEv2 public PRICE;

    /// @notice The PRICE module decimals
    uint8 public PRICE_DECIMALS;

    /// @notice The collateral token address
    address public immutable COLLATERAL_TOKEN;

    /// @notice The loan token address
    address public immutable LOAN_TOKEN;

    /// @notice The scale factor for the oracle
    /// @dev    Equivalent to 10 ** (36 + loan token decimals - collateral token decimals)
    uint256 public immutable SCALE_FACTOR;

    /// @notice The Morpho scale factor decimals
    uint8 internal constant MORPHO_DECIMALS = 36;

    // ========== ERRORS ========== //

    /// @notice Thrown when a token address is invalid (zero address or not a contract)
    error MorphoOracle_InvalidToken(address token);

    /// @notice Thrown when PRICE module version is not supported (must be v1.2+ or v2+)
    error MorphoOracle_UnsupportedPRICEVersion(uint8 major, uint8 minor);

    /// @notice Thrown when PRICE module does not support IPRICEv2 interface
    error MorphoOracle_PRICEInterfaceNotSupported();

    // ========== CONSTRUCTOR ========== //

    /// @notice Constructs a new MorphoOracle
    /// @param kernel_          The Kernel address
    /// @param collateralToken_ The collateral token address (must be IERC20-compliant)
    /// @param loanToken_       The loan token address (must be IERC20-compliant)
    constructor(Kernel kernel_, address collateralToken_, address loanToken_) Policy(kernel_) {
        // Validate collateral token
        if (collateralToken_ == address(0) || collateralToken_.code.length == 0) {
            revert MorphoOracle_InvalidToken(collateralToken_);
        }

        // Validate loan token
        if (loanToken_ == address(0) || loanToken_.code.length == 0) {
            revert MorphoOracle_InvalidToken(loanToken_);
        }

        COLLATERAL_TOKEN = collateralToken_;
        LOAN_TOKEN = loanToken_;

        // Check IERC20 compliance by calling decimals() and store as immutable
        uint8 collateralDecimals = ERC20(collateralToken_).decimals();
        uint8 loanDecimals = ERC20(loanToken_).decimals();
        SCALE_FACTOR = 10 ** (MORPHO_DECIMALS + loanDecimals - collateralDecimals);
    }

    // ========== POLICY SETUP ========== //

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("PRICE");

        address priceModule = getModuleAddress(dependencies[0]);

        // Require PRICE v1.2+ (major=1, minor>=2) or v2+ (major>=2)
        // Cast to Module to access VERSION() function
        (uint8 major, uint8 minor) = Module(priceModule).VERSION();
        if (major == 1 && minor < 2) revert MorphoOracle_UnsupportedPRICEVersion(major, minor);

        // Verify the PRICE module supports IPRICEv2 interface
        if (!IERC165(priceModule).supportsInterface(type(IPRICEv2).interfaceId)) {
            revert MorphoOracle_PRICEInterfaceNotSupported();
        }

        PRICE = IPRICEv2(priceModule);
        PRICE_DECIMALS = PRICE.decimals();
    }

    /// @inheritdoc Policy
    function requestPermissions() external pure override returns (Permissions[] memory requests) {
        // No permissions needed - only reading from PRICE module
        requests = new Permissions[](0);
    }

    // ========== MORPHO ORACLE INTERFACE ========== //

    /// @inheritdoc IOracle
    /// @notice Returns the price of 1 collateral token quoted in loan tokens, scaled by 1e36
    /// @dev    This function will revert if:
    ///         - The contract is not enabled
    ///         - Either the collateral or loan token is not configured in the PRICE module
    function price() external view override onlyEnabled returns (uint256) {
        // Get prices in USD
        // Scale: PRICE_DECIMALS
        uint256 collateralPriceUsd = PRICE.getPrice(COLLATERAL_TOKEN);
        uint256 loanPriceUsd = PRICE.getPrice(LOAN_TOKEN);

        // Adjust to the correct scale
        return SCALE_FACTOR.mulDiv(collateralPriceUsd, loanPriceUsd);
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
