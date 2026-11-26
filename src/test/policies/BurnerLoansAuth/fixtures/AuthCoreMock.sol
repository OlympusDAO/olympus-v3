// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.7.0/utils/introspection/IERC165.sol";
import {IBurnerLoansAuthTarget} from "src/policies/interfaces/burnerloans/IBurnerLoansAuthTarget.sol";

contract AuthCoreMock {
    function supportsInterface(bytes4 interfaceId_) external pure returns (bool) {
        return
            interfaceId_ == type(IERC165).interfaceId ||
            interfaceId_ == type(IBurnerLoansAuthTarget).interfaceId;
    }

    address public immutable kernel;
    bool public isEnabled = true;
    address private _auth;
    uint256 private _authEpoch;
    mapping(address => bool) public isAssetRegistered;

    // Controlled test bindings/callers intentionally retain zero-address cases where applicable.
    // forge-lint: disable-start(missing-zero-check)
    constructor(address kernel_) {
        kernel = kernel_;
    }

    // forge-lint: disable-end(missing-zero-check)

    function setEnabled(bool enabled_) external {
        isEnabled = enabled_;
    }

    function setAsset(address asset_, bool registered_) external {
        isAssetRegistered[asset_] = registered_;
    }

    // Controlled test bindings/callers intentionally retain zero-address cases where applicable.
    // forge-lint: disable-start(missing-zero-check)
    function select(address auth_) external {
        _auth = auth_;
        ++_authEpoch;
    }

    // forge-lint: disable-end(missing-zero-check)

    function authConfig() external view returns (address, uint256) {
        return (_auth, _authEpoch);
    }
}
