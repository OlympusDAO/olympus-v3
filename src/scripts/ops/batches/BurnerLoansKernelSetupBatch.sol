// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Contracts
import {console2} from "@forge-std-1.16.2/console2.sol";
import {Actions, Kernel, Policy, toKeycode} from "src/Kernel.sol";
import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";

/// @notice Prepare Kernel membership; initial configuration and enablement require governance.
contract BurnerLoansKernelSetupBatch is BatchScriptV2 {
    // Fixed deployment entries are checked and simulated sequentially.
    // forge-lint: disable-next-item(calls-loop)
    function setupKernel(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        Kernel kernel = Kernel(_envAddressNotZero("olympus.Kernel"));
        address floan = _envAddressNotZero("olympus.modules.OlympusFixedTermLoan");
        address installed = address(kernel.getModuleForKeycode(toKeycode("FLOAN")));

        if (installed == address(0)) {
            addToBatch(
                address(kernel),
                abi.encodeCall(Kernel.executeAction, (Actions.InstallModule, floan))
            );
        } else {
            console2.log("FLOAN already installed", installed);
        }
        // BurnerLoansAuth is periphery: OCG selects it on Core; it is not a Kernel policy.
        string[15] memory names = [
            "BurnerLoansInventory",
            "BurnerLoansPayout",
            "BurnerLoansRisk",
            "BurnerLoansCore",
            "BurnerLoansConfig",
            "BurnerLoansCollateral",
            "BurnerLoansDebt",
            "BurnerLoansSeize",
            "BurnerLoansConfigTimelock",
            "BurnerLoansRiskConfigTimelock",
            "BurnerLoansPayoutConfigTimelock",
            "BurnerLoansInventoryConfigTimelock",
            "BurnerLoansSeizerTask",
            "BurnerLoansYieldClaimerTask",
            "PriceCache"
        ];
        for (uint256 i; i < names.length; ++i) {
            address target = _envAddressNotZero(string.concat("olympus.policies.", names[i]));

            if (kernel.isPolicyActive(Policy(target))) {
                console2.log("Policy already active", target);
            } else {
                addToBatch(
                    address(kernel),
                    abi.encodeCall(Kernel.executeAction, (Actions.ActivatePolicy, target))
                );
            }
        }
        proposeBatch();
    }
}
