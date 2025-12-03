// SPDX-License-Identifier: AGPL-3.0-or-later
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
// solhint-disable custom-errors
pragma solidity >=0.8.15;

import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";
import {console2} from "@forge-std-1.9.6/console2.sol";
import {ChainUtils} from "src/scripts/ops/lib/ChainUtils.sol";

import {IBondAuctioneer} from "src/interfaces/IBondAuctioneer.sol";

/// @notice This batch script enables the EmissionManager policy to use a callback when creating a market with the BondFixedTermAuctioneer.
/// @dev    The script must be run by a signer of the {BOND_OWNER} contract.
contract EmissionManagerCallbackAuthStatus is BatchScriptV2 {
    address public constant BOND_OWNER = 0x007BD11FCa0dAaeaDD455b51826F9a015f2f0969;

    function setCallbackAuthStatus(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_,
        bytes calldata signature_
    ) external {
        _validateArgsFileEmpty(argsFile_);

        // Validate that useDaoMS_ is true
        if (useDaoMS_ == false) {
            revert("useDaoMS_ must be true for this script");
        }

        // Run the setUp() modifier manually, with an override value for the owner
        console2.log("Setting up batch script");
        _loadEnv(ChainUtils._getChainName(block.chainid));
        // No args
        _setUpBatchScript(signOnly_, BOND_OWNER, ledgerDerivationPath_, signature_);

        // Get addresses
        address bondFixedTermAuctioneer = _envAddressNotZero(
            "external.bond-protocol.BondFixedTermAuctioneer"
        );
        address emissionManager = _envAddressNotZero("olympus.policies.EmissionManager");

        // Skip if not needed
        if (IBondAuctioneer(bondFixedTermAuctioneer).callbackAuthorized(emissionManager)) {
            console2.log(
                "EmissionManager is already authorized to use callbacks in markets. Skipping."
            );
            return;
        }

        console2.log("Authorizing EmissionManager as callback on BondFixedTermAuctioneer");

        addToBatch(
            bondFixedTermAuctioneer,
            abi.encodeWithSelector(
                IBondAuctioneer.setCallbackAuthStatus.selector,
                emissionManager,
                true
            )
        );

        proposeBatch();
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
