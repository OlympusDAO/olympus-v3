// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

library ERC165Helper {
    error ERC165Helper_SupportsInterfaceFailed();
    error ERC165Helper_SupportsInterfaceFalse();

    /// @notice Validates that the contract supports the IERC165 interface using the recommended staticcall approach
    /// @dev    This function will revert if the contract does not support the IERC165 interface
    ///         The approach to detect support for ERC-165 is documented here: https://eips.ethereum.org/EIPS/eip-165#how-to-detect-if-a-contract-implements-erc-165
    function validateSupportsInterface(address contract_) internal view {
        (bool success, bytes memory data) = contract_.staticcall(abi.encodeWithSelector(bytes4(0x01ffc9a7), bytes4(0x01ffc9a7)));

        if (!success) revert ERC165Helper_SupportsInterfaceFailed();

        // Decode the result
        bool supportsInterface = abi.decode(data, (bool));

        if (!supportsInterface) revert ERC165Helper_SupportsInterfaceFalse();
    }
}
