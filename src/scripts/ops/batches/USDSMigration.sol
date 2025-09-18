// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {OlyBatch} from "src/scripts/ops/OlyBatch.sol";

// Bophades
import {Kernel, Actions} from "src/Kernel.sol";

// Bophades policies
import {Operator} from "src/policies/Operator.sol";
import {Clearinghouse} from "src/policies/Clearinghouse.sol";
import {BondCallback} from "src/policies/BondCallback.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";
import {IYieldRepo} from "src/policies/interfaces/IYieldRepo.sol";
import {IHeart} from "src/policies/interfaces/IHeart_v1_6.sol";

/// @notice
/// @dev Deactivates old heart, operator, yield repo, and clearinghouse contracts.
///      Installs new versions that references USDS instead of DAI. Also, adds the ReserveMigrator contract.
// solhint-disable max-states-count
contract USDSMigration is OlyBatch {
    // 1. Deactivate existing contracts that are being replaced locally (i.e. on the contract itself) - DAO MS
    //    + Clearinghouse v2
    //      - Defund to send any reserves back to TRSRY
    //      - Deactivate
    //    + YieldRepurchaseFacility v1
    //      - shutdown to send any reserves back to TRSRY
    //      - make sure that bond market is ended
    //    + Operator v1.4
    //      - Deactivate to prevent swaps and bond markets
    //    + Heart v1.5
    //      - Deactivate so it will not beat

    // 2. Deactivate policies that are being replaced on the Kernel - DAO MS
    //    + Clearinghouse v2
    //    + YieldRepurchaseFacility v1
    //    + Operator v1.4
    //    + Heart v1.5

    // 3. Activate new policies on the Kernel - DAO MS
    //    + Clearinghouse v2.1
    //    + Operator v1.5
    //    + YieldRepurchaseFacility v1.1
    //    + ReserveMigrator v1
    //    + Heart v1.6

    // 4. Initialize new policies and update certain configs - DAO MS
    //    + Set Operator on BondCallback to Operator v1.5
    //    + Set sUSDS as the wrapped token for USDS on BondCallback
    //    + Activate Clearinghouse v2.1
    //    + Initialize YieldRepurchaseFacility v1.1

    // Initial YRF values
    uint256 public initialReserveBalance = 63056043132270355364383714;
    uint256 public initialConversionRate = 1011853995861235596;
    uint256 public initialYield = 121674750000000000000000;

    address public kernel;
    address public oldHeart;
    address public oldOperator;
    address public oldYieldRepo;
    address public oldClearinghouse;
    address public newHeart;
    address public newOperator;
    address public newYieldRepo;
    address public newClearinghouse;
    address public reserveMigrator;
    address public emissionManager;
    address public bondCallback;
    address public usds;
    address public susds;

    function loadEnv() internal override {
        // Load contract addresses from the environment file
        kernel = envAddress("current", "olympus.Kernel");
        oldHeart = envAddress("last", "olympus.policies.OlympusHeart");
        oldOperator = envAddress("last", "olympus.policies.Operator");
        oldYieldRepo = envAddress("last", "olympus.policies.YieldRepurchaseFacility");
        oldClearinghouse = envAddress("last", "olympus.policies.Clearinghouse");
        newHeart = envAddress("current", "olympus.policies.OlympusHeart");
        newOperator = envAddress("current", "olympus.policies.Operator");
        newYieldRepo = envAddress("current", "olympus.policies.YieldRepurchaseFacility");
        newClearinghouse = envAddress("current", "olympus.policies.Clearinghouse");
        reserveMigrator = envAddress("current", "olympus.policies.ReserveMigrator");
        emissionManager = envAddress("current", "olympus.policies.EmissionManager");
        bondCallback = envAddress("current", "olympus.policies.BondCallback");
        usds = envAddress("current", "external.tokens.USDS");
        susds = envAddress("current", "external.tokens.sUSDS");
    }

    // Entry point for the script
    function run(bool send_) external isDaoBatch(send_) {
        // 1. Deactivate existing contracts that are being replaced locally
        // 1a. Deactivate OlympusHeart
        addToBatch(oldHeart, abi.encodeWithSelector(IHeart.deactivate.selector));
        // 1b. Deactivate Operator
        addToBatch(oldOperator, abi.encodeWithSelector(Operator.deactivate.selector));
        // 1c. Shutdown YieldRepurchaseFacility
        address[] memory tokensToTransfer = new address[](2);
        tokensToTransfer[0] = envAddress("current", "external.tokens.DAI");
        tokensToTransfer[1] = envAddress("current", "external.tokens.sDAI");
        addToBatch(
            oldYieldRepo,
            abi.encodeWithSelector(PolicyEnabler.disable.selector, abi.encode(tokensToTransfer))
        );
        // 1d. Shutdown the old Clearinghouse
        addToBatch(
            oldClearinghouse,
            abi.encodeWithSelector(Clearinghouse.emergencyShutdown.selector)
        );

        // 2. Deactivate policies that are being replaced on the Kernel
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.DeactivatePolicy,
                oldHeart
            )
        );
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.DeactivatePolicy,
                oldOperator
            )
        );
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.DeactivatePolicy,
                oldYieldRepo
            )
        );
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.DeactivatePolicy,
                oldClearinghouse
            )
        );

        // 3. Activate new policies on the Kernel
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.ActivatePolicy,
                newOperator
            )
        );
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.ActivatePolicy,
                newYieldRepo
            )
        );
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.ActivatePolicy,
                newClearinghouse
            )
        );
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.ActivatePolicy,
                reserveMigrator
            )
        );
        addToBatch(
            kernel,
            abi.encodeWithSelector(Kernel.executeAction.selector, Actions.ActivatePolicy, newHeart)
        );

        // STEP 4: Policy initialization steps
        // 4a. Set `BondCallback.operator()` to the new Operator policy
        addToBatch(
            bondCallback,
            abi.encodeWithSelector(BondCallback.setOperator.selector, newOperator)
        );

        // 4b. Set sUSDS as the wrapped token for USDS on BondCallback
        addToBatch(
            bondCallback,
            abi.encodeWithSelector(BondCallback.useWrappedVersion.selector, usds, susds)
        );

        // 4c. Activate the new Clearinghouse policy
        addToBatch(newClearinghouse, abi.encodeWithSelector(Clearinghouse.activate.selector));

        // 4d. Initialize the new YRF
        addToBatch(
            newYieldRepo,
            abi.encodeWithSelector(
                PolicyEnabler.enable.selector,
                abi.encode(
                    IYieldRepo.EnableParams({
                        initialReserveBalance: initialReserveBalance,
                        initialConversionRate: initialConversionRate,
                        initialYield: initialYield
                    })
                )
            )
        );

        // 4e. Initialize the new Operator
        addToBatch(newOperator, abi.encodeWithSelector(Operator.initialize.selector));
    }
}
