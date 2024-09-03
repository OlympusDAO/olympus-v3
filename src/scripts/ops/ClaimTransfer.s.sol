// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {ClaimTransfer} from "../../external/ClaimTransfer.sol";
import {pOLY} from "../../policies/pOLY.sol";

contract ClaimTransferScript is Script {
    using stdJson for string;

    string internal _env;

    function _loadEnv() internal {
        _env = vm.readFile("./src/scripts/env.json");
    }

    /// @dev Assumes that the RPC URL has been set
    function splitClaim(address user_, address recipient_) public {
        _loadEnv();

        console2.log("User: ", user_);
        console2.log("Recipient: ", recipient_);
        console2.log("");

        ClaimTransfer claimTransferContract = ClaimTransfer(
            _env.readAddress(".current.mainnet.olympus.claim.ClaimTransfer")
        );
        pOLY pOLYContract = pOLY(_env.readAddress(".current.mainnet.olympus.policies.pOLY"));

        (uint256 percent, uint256 gClaimed, uint256 max) = pOLYContract.terms(user_);
        console2.log("pOLY Percent (1e6):", percent);
        console2.log("pOLY gClaimed (1e18):", gClaimed);
        console2.log("pOLY Max (1e9):", max);

        uint256 claimed = pOLYContract.getAccountClaimed(user_);
        console2.log("Claimed (1e9):", claimed);

        vm.startPrank(user_);
        // Owner needs to authorise the claim transfer contract to pull the claim
        pOLYContract.pushWalletChange(address(claimTransferContract));

        // Fractionalize the claim
        claimTransferContract.fractionalizeClaim();
        vm.stopPrank();

        // Check the new terms
        (uint256 newPercent, uint256 newgClaimed, uint256 newMax) = pOLYContract.terms(user_);
        console2.log("pOLY Percent After (1e6):", newPercent);
        console2.log("pOLY gClaimed After (1e18):", newgClaimed);
        console2.log("pOLY Max After (1e9):", newMax);

        // Check the new terms on ClaimTransfer
        (
            uint256 fractionalizedPercent,
            uint256 fractionalizedgClaimed,
            uint256 fractionalizedMax
        ) = claimTransferContract.fractionalizedTerms(user_);
        console2.log("ClaimTransfer Percent After (1e6):", fractionalizedPercent);
        console2.log("ClaimTransfer gClaimed After (1e18):", fractionalizedgClaimed);
        console2.log("ClaimTransfer Max After (1e9):", fractionalizedMax);

        // Split the claim in half
        vm.startPrank(user_);
        claimTransferContract.transfer(recipient_, fractionalizedPercent / 2);
        vm.stopPrank();

        console2.log("");
        console2.log("After transfer:");
        console2.log("");

        // Check the user's terms on ClaimTransfer
        (fractionalizedPercent, fractionalizedgClaimed, fractionalizedMax) = claimTransferContract
            .fractionalizedTerms(user_);
        console2.log("ClaimTransfer Percent User (1e6):", fractionalizedPercent);
        console2.log("ClaimTransfer gClaimed User (1e18):", fractionalizedgClaimed);
        console2.log("ClaimTransfer Max User (1e9):", fractionalizedMax);

        // Check the recipient's terms on ClaimTransfer
        (fractionalizedPercent, fractionalizedgClaimed, fractionalizedMax) = claimTransferContract
            .fractionalizedTerms(recipient_);
        console2.log("ClaimTransfer Percent Recipient (1e6):", fractionalizedPercent);
        console2.log("ClaimTransfer gClaimed Recipient (1e18):", fractionalizedgClaimed);
        console2.log("ClaimTransfer Max Recipient (1e9):", fractionalizedMax);
    }
}
