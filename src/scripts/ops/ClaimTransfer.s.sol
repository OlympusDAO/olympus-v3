// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {Script} from "forge-std/Script.sol";
import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {ClaimTransfer} from "../../external/ClaimTransfer.sol";
import {pOLY} from "../../policies/pOLY.sol";
import {ERC20} from "../../external/OlympusERC20.sol";

contract ClaimTransferScript is Script, Test {
    using stdJson for string;

    string internal _env;
    address internal ohm;
    address internal dai;

    function _loadEnv() internal {
        _env = vm.readFile("./src/scripts/env.json");

        ohm = _env.readAddress(".current.mainnet.olympus.legacy.OHM");
        dai = _env.readAddress(".current.mainnet.external.tokens.DAI");
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

        {
            (uint256 percent, uint256 gClaimed, uint256 max) = pOLYContract.terms(user_);
            console2.log("pOLY Percent (1e6):", percent);
            console2.log("pOLY gClaimed (1e18):", gClaimed);
            console2.log("pOLY Max (1e9):", max);
        }

        {
            uint256 claimed = pOLYContract.getAccountClaimed(user_);
            console2.log("Claimed (1e9):", claimed);
        }

        vm.startPrank(user_);
        // Owner needs to authorise the claim transfer contract to pull the claim
        pOLYContract.pushWalletChange(address(claimTransferContract));

        // Fractionalize the claim
        claimTransferContract.fractionalizeClaim();
        vm.stopPrank();

        // Check the new terms
        {
            (uint256 newPercent, uint256 newgClaimed, uint256 newMax) = pOLYContract.terms(user_);
            console2.log("pOLY Percent User (1e6):", newPercent);
            console2.log("pOLY gClaimed User (1e18):", newgClaimed);
            console2.log("pOLY Max User (1e9):", newMax);

            // Check the ClaimTransfer claim
            (newPercent, newgClaimed, newMax) = pOLYContract.terms(address(claimTransferContract));
            console2.log("pOLY Percent ClaimTransfer (1e6):", newPercent);
            console2.log("pOLY gClaimed ClaimTransfer (1e18):", newgClaimed);
            console2.log("pOLY Max ClaimTransfer (1e9):", newMax);
        }

        // Check the new terms on ClaimTransfer
        (
            uint256 fractionalizedPercent,
            uint256 fractionalizedgClaimed,
            uint256 fractionalizedMax
        ) = claimTransferContract.fractionalizedTerms(user_);
        console2.log("ClaimTransfer Percent After (1e6):", fractionalizedPercent);
        console2.log("ClaimTransfer gClaimed After (1e18):", fractionalizedgClaimed);
        console2.log("ClaimTransfer Max After (1e9):", fractionalizedMax);

        uint256 accountClaimed = pOLYContract.getAccountClaimed(address(claimTransferContract));
        console2.log("Claimed: ", accountClaimed);
        uint256 circulatingSupply = pOLYContract.getCirculatingSupply();
        console2.log("Circulating Supply:", circulatingSupply);

        {
            uint256 max = (circulatingSupply * fractionalizedPercent) / 1_000_000;
            console2.log("Max:", max);
            console2.log("Account Terms Max:", fractionalizedMax);
            console2.log("Max > Account Terms Max:", max > fractionalizedMax);
            console2.log("Max > accountClaimed:", max > accountClaimed);
        }

        uint256 modifiedCirculatingSupply = 100_000_000e9;
        {
            uint256 modifiedMax = (modifiedCirculatingSupply * fractionalizedPercent) / 1_000_000;
            modifiedMax = modifiedMax > fractionalizedMax ? fractionalizedMax : modifiedMax;
            console2.log("Max (modified) > accountClaimed:", modifiedMax > accountClaimed);
        }

        // Mock a higher total supply
        vm.mockCall(
            _env.readAddress(".current.mainnet.olympus.legacy.OHM"),
            abi.encodeWithSelector(ERC20.totalSupply.selector),
            abi.encode(modifiedCirculatingSupply)
        );

        console2.log("Modified Circulating Supply:", pOLYContract.getCirculatingSupply());

        // Check redeemable amount
        {
            (uint256 redeemableOHM, uint256 daiRequired) = claimTransferContract.redeemableFor(
                user_
            );
            console2.log("Redeemable OHM:", redeemableOHM);
            console2.log("DAI Required:", daiRequired);
        }

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

        // Check redeemable amount
        {
            (uint256 redeemableOHM, uint256 daiRequired) = claimTransferContract.redeemableFor(
                user_
            );
            console2.log("User: Redeemable OHM:", redeemableOHM);
            console2.log("User: DAI Required:", daiRequired);
        }

        // Check the recipient's terms on ClaimTransfer
        (fractionalizedPercent, fractionalizedgClaimed, fractionalizedMax) = claimTransferContract
            .fractionalizedTerms(recipient_);
        console2.log("ClaimTransfer Percent Recipient (1e6):", fractionalizedPercent);
        console2.log("ClaimTransfer gClaimed Recipient (1e18):", fractionalizedgClaimed);
        console2.log("ClaimTransfer Max Recipient (1e9):", fractionalizedMax);

        // Check redeemable amount
        {
            (uint256 redeemableOHM, uint256 daiRequired) = claimTransferContract.redeemableFor(
                recipient_
            );
            console2.log("Recipient: Redeemable OHM:", redeemableOHM);
            console2.log("Recipient: DAI Required:", daiRequired);

            // Provide DAI
            deal(dai, recipient_, daiRequired);

            vm.startPrank(recipient_);
            ERC20(address(dai)).approve(address(claimTransferContract), daiRequired);
            vm.stopPrank();

            // Perform claim
            vm.startPrank(recipient_);
            console2.log("");
            console2.log("Claiming using DAI:", daiRequired);
            claimTransferContract.claim(daiRequired);
            vm.stopPrank();

            // Make sure the DAI has been used
            {
                console2.log("Recipient: DAI Balance:", ERC20(dai).balanceOf(recipient_));
                console2.log("Recipient: OHM Balance:", ERC20(ohm).balanceOf(recipient_));
            }

            // Check the recipient's terms on ClaimTransfer
            (
                fractionalizedPercent,
                fractionalizedgClaimed,
                fractionalizedMax
            ) = claimTransferContract.fractionalizedTerms(recipient_);
            console2.log("ClaimTransfer Percent Recipient (1e6):", fractionalizedPercent);
            console2.log("ClaimTransfer gClaimed Recipient (1e18):", fractionalizedgClaimed);
            console2.log("ClaimTransfer Max Recipient (1e9):", fractionalizedMax);
        }
    }
}
