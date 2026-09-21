// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Contracts
import {ConfigOperatorSingleStep} from "src/policies/utils/ConfigOperatorSingleStep.sol";

contract ConfigOperatorSingleStepHarness is ConfigOperatorSingleStep {
    address internal immutable _AUTHORIZED_CALLER;

    // Zero selects the base contract's default-deny authorization behavior in tests.
    // forge-lint: disable-next-line(missing-zero-check)
    constructor(address authorizedCaller_) {
        _AUTHORIZED_CALLER = authorizedCaller_;
    }

    function isConfigOperator(address account_) external view returns (bool authorized) {
        return _isConfigOperator(account_);
    }

    function _authorizeSetConfigOperator() internal view override returns (bool authorized) {
        if (msg.sender != _AUTHORIZED_CALLER) {
            return super._authorizeSetConfigOperator();
        }
        return true;
    }
}
