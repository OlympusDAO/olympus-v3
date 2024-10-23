// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {console2} from "forge-std/console2.sol";

import {LoanConsolidator} from "../../policies/LoanConsolidator.sol";
import {Cooler} from "../../external/cooler/Cooler.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

contract LoanConsolidatorScript is Test {
    using stdJson for string;

    string internal _env;
    ERC20 internal _gohm;
    ERC20 internal _dai;

    function _loadEnv() internal {
        _env = vm.readFile("./src/scripts/env.json");
        _gohm = ERC20(_env.readAddress(".current.mainnet.olympus.legacy.gOHM"));
        _dai = ERC20(_env.readAddress(".current.mainnet.external.tokens.DAI"));
    }

    /// @dev Call in the form:
    ///      forge script ./src/scripts/ops/LoanConsolidator.s.sol:LoanConsolidatorScript --chain mainnet --sig "consolidate(address,address,address,uint256[])()" --rpc-url <YOUR RPC> <owner> <clearinghouse> <cooler> "[<loanIdOne>,<loanIdTwo>,<etc...>]"
    function consolidate(
        address owner_,
        address clearinghouseFrom_,
        address clearinghouseTo_,
        address coolerFrom_,
        address coolerTo_,
        uint256[] memory loanIds_
    ) public {
        _loadEnv();

        console2.log("Consolidating loans for", owner_);
        console2.log("Clearinghouse From:", clearinghouseFrom_);
        console2.log("Clearinghouse To:", clearinghouseTo_);
        console2.log("Cooler From:", coolerFrom_);
        console2.log("Cooler To:", coolerTo_);

        // // NOTE: Couldn't figure out how to pass an array to the function using forge script. Hard-coding.
        // uint256[] memory loanIds_ = new uint256[](3);
        // loanIds_[0] = 0;
        // loanIds_[1] = 1;
        // loanIds_[2] = 2;

        Cooler coolerFrom = Cooler(coolerFrom_);
        LoanConsolidator utils = LoanConsolidator(
            _env.readAddress(".current.mainnet.olympus.policies.LoanConsolidator")
        );

        // Determine the approvals required
        (, uint256 gohmApproval, uint256 totalDebtWithFee, , ) = utils.requiredApprovals(
            clearinghouseFrom_,
            coolerFrom_,
            loanIds_
        );

        // Determine the interest payable
        uint256 interestPayable;
        uint256 collateral;
        for (uint256 i = 0; i < loanIds_.length; i++) {
            Cooler.Loan memory loan = coolerFrom.getLoan(loanIds_[i]);
            interestPayable += loan.interestDue;
            collateral += loan.collateral;
        }
        console2.log("Interest payable:", interestPayable);
        console2.log("Collateral:", collateral);

        // Determine if there is an additional amount of collateral to be paid
        uint256 additionalCollateral;
        if (gohmApproval > collateral) {
            additionalCollateral = gohmApproval - collateral;
        }

        // Provide the additional collateral
        if (additionalCollateral > 0) {
            console2.log("Providing additional collateral:", additionalCollateral);
            deal(address(_gohm), owner_, additionalCollateral);
        }

        // Grant approvals
        vm.startPrank(owner_);
        _gohm.approve(address(utils), gohmApproval);
        _dai.approve(address(utils), totalDebtWithFee);
        vm.stopPrank();

        console2.log("---");
        console2.log("gOHM balance before:", _gohm.balanceOf(owner_));
        console2.log("DAI balance before:", _dai.balanceOf(owner_));

        console2.log("Consolidating loans...");
        // Consolidate the loans
        vm.startPrank(owner_);
        utils.consolidateWithFlashLoan(
            clearinghouseFrom_,
            clearinghouseTo_,
            coolerFrom_,
            coolerTo_,
            loanIds_,
            0,
            false
        );
        vm.stopPrank();

        console2.log("gOHM balance after:", _gohm.balanceOf(owner_));
        console2.log("DAI balance after:", _dai.balanceOf(owner_));

        uint256 lastLoanId;

        // Check the previous loans
        for (uint256 i = 0; i < loanIds_.length; i++) {
            Cooler.Loan memory loan = coolerFrom.getLoan(loanIds_[i]);

            console2.log("---");
            console2.log("Loan ID:", loanIds_[i]);
            console2.log("Principal Due:", loan.principal);
            console2.log("Interest Due:", loan.interestDue);

            lastLoanId = loanIds_[i];
        }

        uint256 consolidatedLoanId = lastLoanId + 1;

        // Check the consolidated loan
        Cooler coolerTo = Cooler(coolerTo_);
        Cooler.Loan memory consolidatedLoan = coolerTo.getLoan(consolidatedLoanId);
        console2.log("---");
        console2.log("Consolidated Loan ID:", consolidatedLoanId);
        console2.log("Consolidated Principal Due:", consolidatedLoan.principal);
        console2.log("Consolidated Interest Due:", consolidatedLoan.interestDue);
    }
}
