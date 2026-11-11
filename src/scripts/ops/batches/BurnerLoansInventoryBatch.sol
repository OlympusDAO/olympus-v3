// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IBurnerLoansInventory} from "src/policies/interfaces/burnerloans/IBurnerLoansInventory.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";

// Contracts
import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";

/// @notice Inventory funding and mint-approval operations, simulated with the provider Safe.
contract BurnerLoansInventoryBatch is BatchScriptV2 {
    function supply(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        uint128 amount = SafeCast.toUint128(_readBatchArgUint256("supply", "amount"));
        address ohm = IBurnerLoansInventory(
            _envAddressNotZero("olympus.policies.BurnerLoansInventory")
        ).ohm();
        addToBatch(
            ohm,
            abi.encodeCall(
                IERC20.approve,
                (_envAddressNotZero("olympus.policies.BurnerLoansInventory"), 0)
            )
        );
        addToBatch(
            ohm,
            abi.encodeCall(
                IERC20.approve,
                (_envAddressNotZero("olympus.policies.BurnerLoansInventory"), amount)
            )
        );
        addToBatch(
            _envAddressNotZero("olympus.policies.BurnerLoansInventory"),
            abi.encodeCall(IBurnerLoansInventory.supply, (amount))
        );
        proposeBatch();
    }

    function withdraw(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        addToBatch(
            _envAddressNotZero("olympus.policies.BurnerLoansInventory"),
            abi.encodeCall(
                IBurnerLoansInventory.withdraw,
                (
                    SafeCast.toUint128(_readBatchArgUint256("withdraw", "amount")),
                    _readBatchArgAddress("withdraw", "recipient")
                )
            )
        );
        proposeBatch();
    }

    function syncMintApproval(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        addToBatch(
            _envAddressNotZero("olympus.policies.BurnerLoansInventory"),
            abi.encodeCall(IBurnerLoansInventory.syncMintApproval, ())
        );
        proposeBatch();
    }
}
