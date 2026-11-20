// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {IBurnerLoansRiskConfigTimelock} from "src/policies/interfaces/burnerloans/IBurnerLoansRiskConfigTimelock.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";

// Contracts
import {console2} from "@forge-std-1.16.2/console2.sol";
import {TimelockBatchScript} from "src/scripts/ops/lib/TimelockBatchScript.sol";

/// @notice Risk timelock templates. Queue, execute and emergency cancel are separate runs.
/// @dev Target selector admission and execution-time commitments remain enforced by the queue.
contract BurnerLoansRiskConfigTimelockBatch is TimelockBatchScript {
    using SafeCast for uint256;

    /// @notice Queue SetReferralFeeBps using the required args file.
    function queueSetReferralFeeBps(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        console2.log("BurnerLoansRiskConfigTimelockBatch: queueSetReferralFeeBps");
        addToBatch(
            _envAddressNotZero("olympus.policies.BurnerLoansRiskConfigTimelock"),
            abi.encodeCall(
                IBurnerLoansRiskConfigTimelock.queueSetReferralFeeBps,
                (_readBatchArgUint256("queueSetReferralFeeBps", "bps").toUint16())
            )
        );
        proposeBatch();
    }

    /// @notice Queue SetReferrerAllowed using the required args file.
    function queueSetReferrerAllowed(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        console2.log("BurnerLoansRiskConfigTimelockBatch: queueSetReferrerAllowed");
        addToBatch(
            _envAddressNotZero("olympus.policies.BurnerLoansRiskConfigTimelock"),
            abi.encodeCall(
                IBurnerLoansRiskConfigTimelock.queueSetReferrerAllowed,
                (
                    _readBatchArgAddress("queueSetReferrerAllowed", "referrer"),
                    _readBatchArgBool("queueSetReferrerAllowed", "allowed")
                )
            )
        );
        proposeBatch();
    }

    /// @notice Queue SetPriceCacheMaxAge using the required args file.
    function queueSetPriceCacheMaxAge(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        console2.log("BurnerLoansRiskConfigTimelockBatch: queueSetPriceCacheMaxAge");
        addToBatch(
            _envAddressNotZero("olympus.policies.BurnerLoansRiskConfigTimelock"),
            abi.encodeCall(
                IBurnerLoansRiskConfigTimelock.queueSetPriceCacheMaxAge,
                (_readBatchArgUint256("queueSetPriceCacheMaxAge", "age").toUint48())
            )
        );
        proposeBatch();
    }

    /// @notice Queue Batch using the required args file.
    function queueBatch(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        console2.log("BurnerLoansRiskConfigTimelockBatch: queueBatch");
        addToBatch(
            _envAddressNotZero("olympus.policies.BurnerLoansRiskConfigTimelock"),
            abi.encodeCall(
                IBurnerLoansRiskConfigTimelock.queueBatch,
                (
                    abi.decode(
                        vm.parseBytes(_readBatchArgString("queueBatch", "encodedActions")),
                        (ITimelockBatchQueue.BatchAction[])
                    )
                )
            )
        );
        proposeBatch();
    }

    function _timelockKey() internal pure override returns (string memory) {
        return "olympus.policies.BurnerLoansRiskConfigTimelock";
    }
}
