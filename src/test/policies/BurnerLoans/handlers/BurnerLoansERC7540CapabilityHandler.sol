// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Contracts
import {MockERC7540ExternalShareVault} from "src/test/policies/DepositManager/fixtures/MockERC7540ExternalShareVault.sol";

/// @notice Mutates the live redemption capability during Burner Loans invariant runs.
contract BurnerLoansERC7540CapabilityHandler {
    MockERC7540ExternalShareVault internal immutable _VAULT;

    constructor(MockERC7540ExternalShareVault vault_) {
        _VAULT = vault_;
    }

    function setAsyncRedeem(bool asyncRedeem_) external {
        _VAULT.setCapabilities(false, asyncRedeem_, true, true);
    }
}
