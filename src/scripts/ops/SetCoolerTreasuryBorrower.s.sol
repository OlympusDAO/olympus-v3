// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

import {WithEnvironment} from "src/scripts/WithEnvironment.s.sol";
import {console2} from "forge-std/console2.sol";

import {IMonoCooler} from "src/policies/interfaces/cooler/IMonoCooler.sol";

contract SetCoolerTreasuryBorrower is WithEnvironment {
    function run(string calldata chain) public {
        _loadEnv(chain);

        IMonoCooler coolerV2 = IMonoCooler(_envAddressNotZero("olympus.policies.CoolerV2"));
        address coolerV2TreasuryBorrower = _envAddressNotZero(
            "olympus.policies.CoolerV2TreasuryBorrower"
        );

        // Set the treasury borrower
        // This will revert if the treasury borrower is already set
        vm.startBroadcast();
        coolerV2.setTreasuryBorrower(coolerV2TreasuryBorrower);
        vm.stopBroadcast();

        console2.log("Treasury borrower set");

        // Validate
        if (address(coolerV2.treasuryBorrower()) != coolerV2TreasuryBorrower) {
            console2.log(
                "Treasury borrower is set to incorrect address:",
                address(coolerV2.treasuryBorrower())
            );
            // solhint-disable-next-line gas-custom-errors
            revert("Treasury borrower is set to incorrect address");
        } else {
            console2.log("Treasury borrower is set to correct address:", coolerV2TreasuryBorrower);
        }
    }
}
