// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.15;

import {Script, console2} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {ChainUtils} from "src/scripts/ops/lib/ChainUtils.sol";
import {IsOHM} from "src/interfaces/IsOHM.sol";
import {IgOHM} from "src/interfaces/IgOHM.sol";
import {IStaking} from "src/interfaces/IStaking.sol";

/// @title Verify Legacy Staking Contracts
/// @notice Verifies that deployed legacy contracts (sOHM, gOHM, Staking) are correctly configured
/// @dev This script does NOT deploy contracts - it only verifies existing deployments and updates env.json
/// @dev Usage: forge script VerifyLegacyStaking.s.sol --sig "run(address,address,address)" <SOHM> <GOHM> <STAKING> --rpc-url $RPC_URL
contract VerifyLegacyStaking is Script {
    using stdJson for string;

    uint256 constant EXPECTED_INDEX = 269238508004;

    string chain;
    string env;

    address public ohm;
    address public treasury;

    address public newSOHM;
    address public newGOHM;
    address public newStaking;

    function run(address sOHM_, address gOHM_, address staking_) external {
        chain = ChainUtils._getChainName(block.chainid);
        newSOHM = sOHM_;
        newGOHM = gOHM_;
        newStaking = staking_;

        console2.log("\n=== Verifying Legacy Staking Deployment ===");
        console2.log("Chain:", chain);
        console2.log("sOHM:", newSOHM);
        console2.log("gOHM:", newGOHM);
        console2.log("Staking:", newStaking);

        _loadEnv();
        _verifyContracts();
        _updateEnvJson();
        _printSummary();
    }

    function _loadEnv() internal {
        console2.log("\n=== Loading Environment ===");
        env = vm.readFile("./src/scripts/env.json");

        ohm = _envAddress("olympus.legacy.OHM");
        treasury = _envAddress("olympus.legacy.Treasury");

        console2.log("OHM:", ohm);
        console2.log("Treasury:", treasury);
    }

    function _envAddress(string memory key_) internal view returns (address) {
        string memory fullKey = string.concat(".current.", chain, ".", key_);
        return env.readAddress(fullKey);
    }

    function _verifyContracts() internal view {
        console2.log("\n=== Verifying Contract Configuration ===");

        IsOHM sOHMContract = IsOHM(newSOHM);
        IgOHM gOHMContract = IgOHM(newGOHM);
        IStaking stakingContract = IStaking(newStaking);

        console2.log("\n--- sOHM Verification ---");
        uint256 sOHMIndex = sOHMContract.index();
        console2.log("sOHM.index():", sOHMIndex);
        require(sOHMIndex == EXPECTED_INDEX, "sOHM index not set correctly");
        console2.log("OK: sOHM index matches expected:", EXPECTED_INDEX);

        address sOHM_gOHM = sOHMContract.gOHM();
        console2.log("sOHM.gOHM():", sOHM_gOHM);
        require(sOHM_gOHM == newGOHM, "sOHM gOHM mismatch");
        console2.log("OK: sOHM points to correct gOHM");

        address sOHM_Staking = sOHMContract.stakingContract();
        console2.log("sOHM.stakingContract():", sOHM_Staking);
        require(sOHM_Staking == newStaking, "sOHM staking mismatch");
        console2.log("OK: sOHM points to correct Staking");

        address sOHM_Treasury = sOHMContract.treasury();
        console2.log("sOHM.treasury():", sOHM_Treasury);
        require(sOHM_Treasury == treasury, "sOHM treasury mismatch");
        console2.log("OK: sOHM points to correct Treasury");

        console2.log("\n--- gOHM Verification ---");
        uint256 gOHMIndex = gOHMContract.index();
        console2.log("gOHM.index():", gOHMIndex);
        require(gOHMIndex == EXPECTED_INDEX, "gOHM index not set correctly");
        console2.log("OK: gOHM index matches expected:", EXPECTED_INDEX);

        address gOHM_sOHM = gOHMContract.sOHM();
        console2.log("gOHM.sOHM():", gOHM_sOHM);
        require(gOHM_sOHM == newSOHM, "gOHM sOHM mismatch");
        console2.log("OK: gOHM points to correct sOHM");

        console2.log("\n--- Staking Verification ---");
        address staking_OHM = stakingContract.OHM();
        console2.log("Staking.OHM():", staking_OHM);
        require(staking_OHM == ohm, "Staking OHM mismatch");
        console2.log("OK: Staking points to correct OHM");

        address staking_sOHM = stakingContract.sOHM();
        console2.log("Staking.sOHM():", staking_sOHM);
        require(staking_sOHM == newSOHM, "Staking sOHM mismatch");
        console2.log("OK: Staking points to correct sOHM");

        address staking_gOHM = stakingContract.gOHM();
        console2.log("Staking.gOHM():", staking_gOHM);
        require(staking_gOHM == newGOHM, "Staking gOHM mismatch");
        console2.log("OK: Staking points to correct gOHM");

        uint256 stakingIndex = stakingContract.index();
        console2.log("Staking.index():", stakingIndex);
        require(stakingIndex == EXPECTED_INDEX, "Staking index mismatch");
        console2.log("OK: Staking index matches expected:", EXPECTED_INDEX);

        console2.log("\nAll verifications passed!");
    }

    function _updateEnvJson() internal {
        console2.log("\n=== Updating env.json ===");

        _writeToEnv("olympus.legacy.sOHM", newSOHM);
        console2.log("Updated olympus.legacy.sOHM:", newSOHM);

        _writeToEnv("olympus.legacy.gOHM", newGOHM);
        console2.log("Updated olympus.legacy.gOHM:", newGOHM);

        _writeToEnv("olympus.legacy.Staking", newStaking);
        console2.log("Updated olympus.legacy.Staking:", newStaking);

        console2.log("env.json updated successfully");
    }

    function _writeToEnv(string memory key_, address value_) internal {
        string[] memory inputs = new string[](3);
        inputs[0] = "./src/scripts/deploy/write_deployment.sh";
        inputs[1] = string.concat("current.", chain, ".", key_);
        inputs[2] = vm.toString(value_);
        vm.ffi(inputs);
    }

    function _printSummary() internal view {
        console2.log("\n========================================");
        console2.log("         VERIFICATION SUMMARY");
        console2.log("========================================");
        console2.log("Legacy Contracts Verified:");
        console2.log("  sOHM:    ", newSOHM);
        console2.log("  gOHM:    ", newGOHM);
        console2.log("  Staking: ", newStaking);
        console2.log("\nConfiguration:");
        console2.log("  Index:   ", EXPECTED_INDEX);
        console2.log("  Chain:   ", chain);
        console2.log("\nenv.json has been updated with new addresses.");
        console2.log("========================================");
    }
}
