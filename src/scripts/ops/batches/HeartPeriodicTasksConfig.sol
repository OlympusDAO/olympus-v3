// SPDX-License-Identifier: AGPL-3.0-or-later
// solhint-disable custom-errors
pragma solidity >=0.8.15;

import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";

// Interfaces
import {IPeriodicTaskManager} from "src/bases/interfaces/IPeriodicTaskManager.sol";
import {IReserveMigrator} from "src/policies/interfaces/IReserveMigrator.sol";
import {IOperator} from "src/policies/interfaces/IOperator.sol";
import {IYieldRepo} from "src/policies/interfaces/IYieldRepo.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

import {console2} from "@forge-std-1.9.6/console2.sol";

/// @notice Configures the Heart with periodic tasks for reserve operations
/// @dev    This is designed for use with Heart v1.7, and is mainly intended for configuring the Heart on testnets. The production contract will be configured through an OCG proposal.
contract HeartPeriodicTasksConfig is BatchScriptV2 {
    /// @notice Configure Heart with periodic tasks in the specified order
    /// @dev    This is for testing purposes only. The production contract will be configured through an OCG proposal.
    ///         Run this after ConvertibleDepositInstall.install()
    function configurePeriodicTasks(
        bool useDaoMS_,
        string calldata argsFile_
    ) external setUpWithChainIdAndArgsFile(useDaoMS_, argsFile_) {
        _validateArgsFileEmpty(argsFile_);

        // Load contract addresses
        address heart = _envAddressNotZero("olympus.policies.OlympusHeart");
        address reserveMigrator = _envAddressNotZero("olympus.policies.ReserveMigrator");
        address reserveWrapper = _envAddressNotZero("olympus.policies.ReserveWrapper");
        address operator = _envAddressNotZero("olympus.policies.Operator");
        address yieldRepo = _envAddressNotZero("olympus.policies.YieldRepurchaseFacility");

        // Assumes that the Heart has been activated in the Kernel

        // Assumes that there are no existing tasks
        // solhint-disable-next-line gas-custom-errors
        require(
            IPeriodicTaskManager(heart).getPeriodicTaskCount() == 0,
            "Heart already has periodic tasks configured"
        );

        // Add periodic tasks to Heart in the specified order:
        // 1. reserveMigrator.migrate();
        console2.log("Adding ReserveMigrator.migrate() task to Heart");
        addToBatch(
            heart,
            abi.encodeWithSelector(
                IPeriodicTaskManager.addPeriodicTaskAtIndex.selector,
                reserveMigrator,
                IReserveMigrator.migrate.selector,
                0 // First task
            )
        );

        // 2. reserveWrapper.execute();
        console2.log("Adding ReserveWrapper.execute() task to Heart");
        addToBatch(
            heart,
            abi.encodeWithSelector(IPeriodicTaskManager.addPeriodicTask.selector, reserveWrapper)
        );

        // 3. operator.operate();
        console2.log("Adding Operator.operate() task to Heart");
        addToBatch(
            heart,
            abi.encodeWithSelector(
                IPeriodicTaskManager.addPeriodicTaskAtIndex.selector,
                operator,
                IOperator.operate.selector,
                2 // Third task
            )
        );

        // 4. yieldRepo.endEpoch();
        console2.log("Adding YieldRepo.endEpoch() task to Heart");
        addToBatch(
            heart,
            abi.encodeWithSelector(
                IPeriodicTaskManager.addPeriodicTaskAtIndex.selector,
                yieldRepo,
                IYieldRepo.endEpoch.selector,
                3 // Fourth task
            )
        );

        // 5. Enable the Heart
        console2.log("Enabling Heart");
        addToBatch(
            heart,
            abi.encodeWithSelector(
                IEnabler.enable.selector,
                "" // No enable data needed for Heart
            )
        );

        // Run
        proposeBatch();
    }
}
