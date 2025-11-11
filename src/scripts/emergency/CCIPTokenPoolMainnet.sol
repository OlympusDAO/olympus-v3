// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.15;

import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";
import {IEmergencyBatch} from "src/scripts/emergency/IEmergencyBatch.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {console2} from "@forge-std-1.9.6/console2.sol";

interface ILockReleaseTokenPool {
    function withdrawLiquidity(uint256 amount) external;
}

/// @notice Withdraws all liquidity from the mainnet CCIP LockRelease token pool
/// @dev    Requires DAO multisig ownership (rebalancer role)
contract CCIPTokenPoolMainnet is BatchScriptV2, IEmergencyBatch {
    function _isChainCanonical(string memory chain_) internal pure returns (bool) {
        return
            keccak256(abi.encodePacked(chain_)) == keccak256(abi.encodePacked("mainnet")) ||
            keccak256(abi.encodePacked(chain_)) == keccak256(abi.encodePacked("sepolia"));
    }

    function run(
        bool signOnly_,
        string memory argsFilePath_,
        string memory ledgerDerivationPath_,
        bytes memory signature_
    )
        external
        override
        setUp(
            true, // Runs as DAO MS
            signOnly_,
            argsFilePath_,
            ledgerDerivationPath_,
            signature_
        )
    {
        _validateArgsFileEmpty(argsFilePath_);

        if (!_isChainCanonical(chain)) {
            revert("CCIPTokenPoolMainnet: only canonical chains");
        }

        console2.log("\n");
        console2.log("Withdrawing all liquidity from CCIP LockRelease token pool");

        address tokenPoolAddress = _envAddressNotZero("olympus.periphery.CCIPLockReleaseTokenPool");
        address ohmToken = _envAddressNotZero("olympus.legacy.OHM");

        uint256 liquidity = IERC20(ohmToken).balanceOf(tokenPoolAddress);
        console2.log("  Liquidity detected", liquidity);

        if (liquidity == 0) {
            console2.log("  No liquidity to withdraw");
        } else {
            addToBatch(
                tokenPoolAddress,
                abi.encodeWithSelector(ILockReleaseTokenPool.withdrawLiquidity.selector, liquidity)
            );
        }

        proposeBatch();

        console2.log("Completed");
    }
}
