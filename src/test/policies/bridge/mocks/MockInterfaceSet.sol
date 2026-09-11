// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

/// @notice Well-behaved ERC165 responder that advertises a constructor-supplied set of
///         interface identifiers.
/// @dev    Answers true for the ERC165 identifier, false for the invalid identifier
///         `0xffffffff` and otherwise true exactly for the identifiers supplied at
///         construction, so an `ERC165Checker` probe reads the contract as a valid ERC165
///         responder advertising precisely that set.
contract MockInterfaceSet {
    mapping(bytes4 => bool) internal _advertised;

    constructor(bytes4[] memory interfaceIds_) {
        for (uint256 i; i < interfaceIds_.length; ++i) {
            _advertised[interfaceIds_[i]] = true;
        }
    }

    function supportsInterface(bytes4 interfaceId_) external view returns (bool) {
        if (interfaceId_ == 0x01ffc9a7) return true;
        if (interfaceId_ == 0xffffffff) return false;
        return _advertised[interfaceId_];
    }
}
