// SPDX-License-Identifier: AGPL-3.0
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.15;

// Interfaces
import {IERC7726Oracle} from "src/policies/interfaces/price/IERC7726Oracle.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IERC165} from "@openzeppelin-4.8.0/interfaces/IERC165.sol";
import {IERC20} from "src/interfaces/IERC20.sol";

// Libraries
import {FullMath} from "src/libraries/FullMath.sol";

// Bophades
import {Kernel, Policy, Module, Keycode, toKeycode, Permissions} from "src/Kernel.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

/// @title  ERC7726Oracle
/// @author OlympusDAO
/// @notice Oracle contract that implements the IERC7726Oracle interface
/// @dev    This contract uses the PRICE v1.2+ module to get the price of the base and quote tokens.
contract ERC7726Oracle is Policy, PolicyEnabler, IERC7726Oracle, IVersioned {
    using FullMath for uint256;

    // ========== ERRORS ========== //

    /// @notice Thrown when the PRICE module version is not supported (must be v1.2+ or v2+)
    error ERC7726Oracle_UnsupportedPRICEVersion(uint8 major, uint8 minor);

    /// @notice Thrown when the PRICE module does not support the IPRICEv2 interface
    error ERC7726Oracle_PRICEInterfaceNotSupported();

    // ========== STATE ========== //

    /// @notice The PRICE module
    IPRICEv2 public PRICE;

    /// @notice The PRICE module decimals
    uint8 public PRICE_DECIMALS;

    // ========== CONSTRUCTOR ========== //

    /// @notice Constructs a new ERC7726Oracle
    ///
    /// @param kernel_ The Kernel address
    constructor(Kernel kernel_) Policy(kernel_) {
        // Disabled by default from PolicyEnabler
    }

    // ========== POLICY SETUP ========== //

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](2);
        dependencies[0] = toKeycode("PRICE");
        dependencies[1] = toKeycode("ROLES");

        address priceModule = getModuleAddress(dependencies[0]);

        // Require PRICE v1.2+ (major=1, minor>=2) or v2+ (major>=2)
        // Cast to Module to access VERSION() function
        (uint8 major, uint8 minor) = Module(priceModule).VERSION();
        if (major == 1 && minor < 2) {
            revert ERC7726Oracle_UnsupportedPRICEVersion(major, minor);
        }

        // Verify the PRICE module supports IPRICEv2 interface
        if (!IERC165(priceModule).supportsInterface(type(IPRICEv2).interfaceId)) {
            revert ERC7726Oracle_PRICEInterfaceNotSupported();
        }

        PRICE = IPRICEv2(priceModule);
        PRICE_DECIMALS = PRICE.decimals();

        // Set ROLES module (required by PolicyEnabler)
        ROLES = ROLESv1(getModuleAddress(dependencies[1]));
    }

    /// @inheritdoc Policy
    function requestPermissions() external pure override returns (Permissions[] memory requests) {
        // No permissions needed - only reading from PRICE module
        requests = new Permissions[](0);
    }

    /// @inheritdoc IVersioned
    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        return (1, 0);
    }

    // ========== ERC7726 FUNCTIONS ========== //

    /// @inheritdoc IERC7726Oracle
    function name() external pure override returns (string memory) {
        return "ERC7726Oracle";
    }

    function _getQuote(
        uint256 inAmount,
        address base,
        address quote
    ) internal view returns (uint256) {
        // Get prices in USD
        uint256 basePriceUsd = PRICE.getPrice(base);
        uint256 quotePriceUsd = PRICE.getPrice(quote);

        // Calculate the out amount in terms of the quote token
        uint256 baseTokenScale = 10 ** IERC20(base).decimals();
        uint256 quoteTokenScale = 10 ** IERC20(quote).decimals();

        // Scale the prices to the correct decimals
        // The prices are in terms of PRICE decimals, and cancel each other out
        // inAmount is in terms of the base token decimals, so we need to scale it to the quote token decimals
        return inAmount.mulDiv(basePriceUsd * quoteTokenScale, quotePriceUsd * baseTokenScale);
    }

    /// @inheritdoc IERC7726Oracle
    /// @dev        This function will revert if:
    ///             - The contract is not enabled
    ///             - The base or quote token is not configured in the PRICE module
    ///             - The base or quote token price is zero
    function getQuote(
        uint256 inAmount,
        address base,
        address quote
    ) external view override onlyEnabled returns (uint256) {
        return _getQuote(inAmount, base, quote);
    }

    /// @inheritdoc IERC7726Oracle
    /// @dev        This function will revert if:
    ///             - The contract is not enabled
    ///             - The base or quote token is not configured in the PRICE module
    ///             - The base or quote token price is zero
    ///
    ///             This implementation returns the same amount for both bid and ask.
    function getQuotes(
        uint256 inAmount,
        address base,
        address quote
    ) external view override onlyEnabled returns (uint256, uint256) {
        uint256 outAmount = _getQuote(inAmount, base, quote);
        return (outAmount, outAmount);
    }

    // ========== ERC165 FUNCTIONS ========== //

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return
            interfaceId == type(IERC7726Oracle).interfaceId ||
            interfaceId == type(IERC165).interfaceId ||
            interfaceId == type(IVersioned).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
