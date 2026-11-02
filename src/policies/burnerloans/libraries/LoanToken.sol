// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";

// Libraries
import {SafeCallDecoder} from "src/libraries/SafeCallDecoder.sol";
import {LoanParameters} from "src/policies/burnerloans/libraries/LoanParameters.sol";

/// @notice Shared token precision validation for Burner Loans debt and collateral assets.
library LoanToken {
    /// @notice Reads token decimals within the precision supported by Burner Loans accounting.
    /// @dev Bounds copied return data and rejects missing code, failed reads and noncanonical lengths.
    /// @param token_ Token whose decimals are being validated.
    /// @return bool Whether the token reports a supported precision.
    /// @return uint8 Supported token decimals, or zero on failure.
    function readDecimals(address token_) internal view returns (bool, uint8) {
        if (token_.code.length == 0) return (false, 0);
        (bool success, uint256 value) = SafeCallDecoder.safeReadUint256(
            token_,
            IERC20.decimals.selector
        );
        if (!success || value > LoanParameters._MAX_TOKEN_DECIMALS) return (false, 0);
        // The supported precision is at most 36, so this conversion cannot truncate.
        // forge-lint: disable-next-line(unsafe-typecast)
        return (true, uint8(value));
    }
}
