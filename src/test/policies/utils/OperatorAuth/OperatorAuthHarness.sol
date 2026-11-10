// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Contracts
import {OperatorAuth} from "src/policies/utils/OperatorAuth.sol";

contract OperatorAuthHarness is OperatorAuth {
    error PermissionsTooLong();
    error CreationDisabled();
    error UseDisabled();
    error InvalidSignatureData();
    bytes32 internal _context;
    bool internal _creationAllowed = true;
    bool internal _useAllowed = true;
    bool internal _signatureDataEnabled;

    constructor() OperatorAuth(15) {}

    function setContext(bytes32 context_) external {
        _context = context_;
    }

    function setCreationAllowed(bool allowed_) external {
        _creationAllowed = allowed_;
    }

    function setUseAllowed(bool allowed_) external {
        _useAllowed = allowed_;
    }

    function enableSignatureData() external {
        _signatureDataEnabled = true;
    }

    function _currentAuthorizationContext(
        address,
        address
    ) internal view override returns (bytes32) {
        return _context;
    }

    function _validatePermissions(IOperatorAuth.Grant calldata grant_) internal pure override {
        if (grant_.permissions.length > 320) revert PermissionsTooLong();
    }

    function _beforeGrantCreation() internal view override {
        if (!_creationAllowed) revert CreationDisabled();
    }

    function _beforeAuthorization() internal view override {
        if (!_useAllowed) revert UseDisabled();
    }

    function _validateSignatureData(
        IOperatorAuth.Grant calldata grant_,
        bytes calldata data_
    ) internal view override {
        if (!_signatureDataEnabled) {
            super._validateSignatureData(grant_, data_);
            return;
        }
        if (data_.length != 32) revert InvalidSignatureData();
    }
}
