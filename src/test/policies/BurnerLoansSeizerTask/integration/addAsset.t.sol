// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Contracts
import {BurnerLoansSeizerTaskProgressTest} from "../fixtures/BurnerLoansSeizerTaskProgressTest.sol";

contract BurnerLoansSeizerTaskAddAssetRegistrationTest is BurnerLoansSeizerTaskProgressTest {
    // Scenarios: BLSEIZ-ADD-ASSET-P04.
    function test_givenOriginationsDisabled_whenRegisteredAssetAdded() public {
        _config.setAssetOriginationsEnabled(address(_asset), false);
        _task.addAsset(address(_asset));
        assertTrue(_task.isAssetManaged(address(_asset)), "Existing debt remains manageable");
    }
}
