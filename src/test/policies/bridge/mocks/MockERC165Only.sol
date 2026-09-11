// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

/// @notice Well-behaved ERC165 responder that advertises no interface beyond ERC165 itself.
/// @dev    Answers true for the ERC165 identifier, false for the invalid identifier
///         `0xffffffff` and false for everything else, so an `ERC165Checker` probe reads the
///         contract as a valid ERC165 responder that does not advertise the queried interface.
contract MockERC165Only {
    function supportsInterface(bytes4 interfaceId_) external pure returns (bool) {
        return interfaceId_ == 0x01ffc9a7;
    }
}
