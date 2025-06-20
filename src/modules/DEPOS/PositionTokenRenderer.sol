// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

// Interfaces
import {IPositionTokenRenderer} from "src/modules/DEPOS/IPositionTokenRenderer.sol";
import {IDepositPositionManager} from "src/modules/DEPOS/IDepositPositionManager.sol";

// Libraries
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";
import {Strings} from "@openzeppelin-5.3.0/utils/Strings.sol";
import {Base64} from "@openzeppelin-5.3.0/utils/Base64.sol";
import {Timestamp} from "src/libraries/Timestamp.sol";
import {DecimalString} from "src/libraries/DecimalString.sol";

// solhint-disable quotes

/// @title  Position Token Renderer
/// @notice Implementation of the IPositionTokenRenderer interface
///         This contract implements a custom token renderer
///         for the Olympus Deposit Position Manager
contract PositionTokenRenderer is IPositionTokenRenderer {
    // ========== STATE VARIABLES ========== //

    /// @notice The number of decimal places to display when rendering values as decimal strings
    uint8 public constant DISPLAY_DECIMALS = 2;

    /// @notice The address of the position manager contract
    IDepositPositionManager internal immutable _POSITION_MANAGER;

    /// @notice Constructor
    ///
    /// @param positionManager_ The address of the position manager contract
    constructor(address positionManager_) {
        // Validate that the position manager contract is not zero address
        if (positionManager_ == address(0)) {
            revert PositionTokenRenderer_ZeroAddress();
        }

        // Set the position manager contract
        _POSITION_MANAGER = IDepositPositionManager(positionManager_);
    }

    // ========== FUNCTIONS ========== //

    /// @inheritdoc IPositionTokenRenderer
    function getPositionManager() external view returns (address) {
        return address(_POSITION_MANAGER);
    }

    /// @inheritdoc IPositionTokenRenderer
    function tokenURI(uint256 positionId_) external view override returns (string memory) {
        // Get the position data from the position manager
        IDepositPositionManager.Position memory position = _POSITION_MANAGER.getPosition(
            positionId_
        );

        // Get the decimals of the deposit token
        uint8 depositDecimals = ERC20(position.asset).decimals();
        string memory cdSymbol = ERC20(position.asset).symbol();

        // Check if the position is convertible
        bool positionIsConvertible = _POSITION_MANAGER.isConvertible(positionId_);

        // Generate the JSON metadata
        string memory jsonContent = string.concat(
            "{",
            '"name": "Olympus Deposit Position",',
            '"symbol": "ODP",',
            '"attributes": [',
            string.concat(
                '{"trait_type": "Position ID", "value": ',
                Strings.toString(positionId_),
                "},"
            ),
            string.concat(
                '{"trait_type": "Deposit Asset", "value": "',
                Strings.toHexString(position.asset),
                '"},'
            ),
            string.concat(
                '{"trait_type": "Deposit Period", "value": ',
                Strings.toString(position.periodMonths),
                "},"
            ),
            string.concat(
                '{"trait_type": "Expiry", "display_type": "date", "value": ',
                Strings.toString(position.expiry),
                "},"
            ),
            positionIsConvertible
                ? string.concat(
                    '{"trait_type": "Conversion Price", "value": ',
                    DecimalString.toDecimalString(
                        position.conversionPrice,
                        depositDecimals,
                        DISPLAY_DECIMALS
                    ),
                    "},"
                )
                : "",
            string.concat(
                '{"trait_type": "Remaining Deposit", "value": ',
                DecimalString.toDecimalString(
                    position.remainingDeposit,
                    depositDecimals,
                    DISPLAY_DECIMALS
                ),
                "}"
            ),
            "],",
            string.concat(
                '"image": "',
                "data:image/svg+xml;base64,",
                Base64.encode(bytes(_renderSVG(position, cdSymbol, positionIsConvertible))),
                '"'
            ),
            "}"
        );

        return string.concat("data:application/json;base64,", Base64.encode(bytes(jsonContent)));
    }

    // ========== INTERNAL FUNCTIONS ========== //

    function _getTimeString(uint48 time_) internal pure returns (string memory) {
        (string memory year, string memory month, string memory day) = Timestamp.toPaddedString(
            time_
        );

        return string.concat(year, "-", month, "-", day);
    }

    function _renderSVG(
        IDepositPositionManager.Position memory position_,
        string memory cdSymbol_,
        bool positionIsConvertible_
    ) internal view returns (string memory) {
        return
            string.concat(
                '<svg width="500" height="600" viewBox="0 0 500 600" fill="none" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"><rect width="500" height="600" rx="18" fill="#141722" /><rect x="73.0154" y="63" width="353" height="353" rx="176.5" fill="#708B96" /><path id="Vector" d="M233.546 286.32C213.544 281.175 197.413 260.273 197.413 236.476C197.413 209.142 221.287 185.346 249.676 185.346C280.002 185.989 301.617 209.464 301.617 236.476C301.617 260.273 287.1 278.924 265.807 286.32V317.513H324.523V294.36H284.196V298.862C310.65 290.501 324.845 263.81 324.845 236.476C324.845 195.958 291.939 162.193 249.676 162.193C208.705 162.193 174.185 195.958 174.185 236.476C174.185 263.81 188.057 289.214 213.544 299.183L214.189 294.36H174.185V317.513H233.546V286.32Z" fill="#EEE9E2" />',
                string.concat(
                    '<text xml:space="preserve" class="heading"><tspan x="32" y="465.504">',
                    positionIsConvertible_
                        ? string.concat(cdSymbol_, "-OHM Convertible Deposit")
                        : string.concat(cdSymbol_, " Yield-Bearing Deposit"),
                    "</tspan></text>"
                ),
                '<rect x="33" y="480" width="434" height="110" rx="9" fill="#2C2E37" />',
                string.concat(
                    '<text xml:space="preserve" class="standard-text"><tspan x="42" y="503">Expiry</tspan><tspan x="457" y="503" text-anchor="end">',
                    _getTimeString(position_.expiry),
                    "</tspan></text>"
                ),
                string.concat(
                    '<text xml:space="preserve" class="standard-text"><tspan x="42" y="527">Deposit Period</tspan><tspan x="457" y="527" text-anchor="end">',
                    Strings.toString(position_.periodMonths),
                    " months",
                    "</tspan></text>"
                ),
                string.concat(
                    '<text xml:space="preserve" class="standard-text"><tspan x="42" y="551">',
                    positionIsConvertible_ ? "Remaining Deposit" : "Deposit",
                    '</tspan><tspan x="457" y="551" text-anchor="end">',
                    DecimalString.toDecimalString(
                        position_.remainingDeposit,
                        ERC20(position_.asset).decimals(),
                        DISPLAY_DECIMALS
                    ),
                    " ",
                    cdSymbol_,
                    "</tspan></text>"
                ),
                positionIsConvertible_
                    ? string.concat(
                        '<text xml:space="preserve" class="standard-text"><tspan x="42" y="575">Convertible To</tspan><tspan x="457" y="575" text-anchor="end">',
                        DecimalString.toDecimalString(
                            (position_.remainingDeposit * 1e9) / position_.conversionPrice,
                            9,
                            2
                        ),
                        " OHM</tspan></text>"
                    )
                    : "",
                '<defs><style type="text/css">.heading{fill:#F8CC82;font-family:"Helvetica Neue",Helvetica,-apple-system,BlinkMacSystemFont,Ubuntu,Jost,"DM Sans",sans-serif;font-size:24px;font-weight:500;letter-spacing:0em;white-space:pre;}.standard-text{fill:#EEE9E2;font-family:"Helvetica Neue",Helvetica,-apple-system,BlinkMacSystemFont,Ubuntu,Jost,"DM Sans",sans-serif;font-size:15px;font-weight:500;letter-spacing:0em;white-space:pre;}</style></defs></svg>'
            );
    }

    // ========== ERC165 SUPPORT ========== //

    function supportsInterface(bytes4 interfaceId_) external pure returns (bool) {
        return interfaceId_ == type(IPositionTokenRenderer).interfaceId;
    }
}
