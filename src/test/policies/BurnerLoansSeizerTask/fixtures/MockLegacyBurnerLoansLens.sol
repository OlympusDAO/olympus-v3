// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.7.0/utils/introspection/IERC165.sol";

/// @dev Same-Core old scan helper: combined discovery only, no expired/unhealthy capabilities.
contract MockLegacyBurnerLoansLens is IERC165 {
    address private immutable _CORE;

    constructor(address core_) {
        _CORE = core_;
    }

    function core() external view returns (address) {
        return _CORE;
    }

    function supportsInterface(bytes4 interfaceId_) external pure returns (bool) {
        return interfaceId_ == type(IERC165).interfaceId;
    }

    function getSeizableBorrowersBoundedFor(
        address,
        address,
        uint256 start_,
        uint256,
        uint256
    ) external pure returns (address[] memory, uint256, uint256) {
        return (new address[](0), start_, 0);
    }
}
