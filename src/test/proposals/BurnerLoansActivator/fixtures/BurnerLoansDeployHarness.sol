// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansActivator} from "src/proposals/interfaces/IBurnerLoansActivator.sol";

// Contracts
import {DeployV3} from "src/scripts/deploy/DeployV3.s.sol";

/// @dev Uses the same sequence argument format and result-key composition as DeployV3.
contract BurnerLoansDeployHarness is DeployV3 {
    function loadSequence(string calldata sequence_) external {
        sequenceFile = sequence_;
    }

    function setDependency(string calldata key_, address value_) external {
        deployedTo[key_] = value_;
    }

    function resolve(string calldata key_) external view returns (address) {
        return _getAddressNotZero(key_);
    }

    function deployNamed(
        string calldata name_
    ) external returns (address deployed, string memory key) {
        (bool success, bytes memory data) = address(this).call(
            abi.encodeWithSignature(string.concat("deploy", name_, "()"))
        );
        if (!success) {
            assembly ("memory-safe") {
                revert(add(data, 32), mload(data))
            }
        }
        string memory prefix;
        (deployed, prefix) = abi.decode(data, (address, string));
        key = string.concat(prefix, ".", name_);
        deployedTo[key] = deployed;
    }

    // Test fixture registry supplies policy membership independently of the production activator API.
    // forge-lint: disable-next-item(calls-loop)
    function policies() external view returns (address[] memory targets) {
        string[19] memory names = [
            "DepositManager",
            "BurnerLoansCore",
            "BurnerLoansConfig",
            "BurnerLoansInventory",
            "BurnerLoansPayout",
            "BurnerLoansRisk",
            "BurnerLoansCollateral",
            "BurnerLoansDebt",
            "BurnerLoansSeize",
            "BurnerLoansSeizerTask",
            "BurnerLoansYieldClaimerTask",
            "BurnerLoansConfigTimelock",
            "BurnerLoansRiskConfigTimelock",
            "BurnerLoansPayoutConfigTimelock",
            "BurnerLoansInventoryConfigTimelock",
            "PriceCache",
            "RevenueDistributor",
            "RevenueDistributorTask",
            "RevenueDistributorConfigTimelock"
        ];
        targets = new address[](names.length);
        for (uint256 j; j < names.length; ++j)
            targets[j] = _getAddressNotZero(string.concat("olympus.policies.", names[j]));
    }

    function deployment() external view returns (IBurnerLoansActivator.Deployment memory) {
        return _burnerLoansDeployment();
    }
}
