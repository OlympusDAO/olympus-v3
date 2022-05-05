// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {Auth, Authority} from "solmate/auth/Auth.sol";
import {ERC1155} from "solmate/tokens/ERC1155.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";

import {TransferHelper} from "../libraries/TransferHelper.sol";
import {IERC20} from "../interfaces/IERC20.sol";

import {Kernel, Module} from "../Kernel.sol";

//import "./OlympusErrors.sol";

/// @title TSY - OlympusTreasury
/// @notice Treasury holds reserves, LP tokens and all other assets under the control
/// of the protocol. Any contracts that need access to treasury assets should
/// be whitelisted by governance.
contract OlympusTreasury is Module, Auth {
    using TransferHelper for IERC20;

    constructor(
        Kernel kernel_,
        address owner_,
        Authority authority_
    ) Module(kernel_) Auth(owner_, authority_) {}

    function KEYCODE() public pure override returns (bytes3) {
        return "TSY";
    }

    function withdraw(
        IERC20 token_,
        address to_,
        uint256 amount_
    ) external onlyPermitted {
        // TODO is this all?? does this properly gate functions?
        token_.safeTransfer(to_, amount_);
    }

    /* TODO overload errors?
    function withdraw(ERC721 token_, address to_, uint256 id_) external requiresAuth {
        token_.safeTransferFrom(address(this), to_, id_);
    }

    function withdraw(ERC1155 token_, address to_, uint256 id_, uint256 amount_) external requiresAuth {
        token_.safeTransferFrom(address(this), to_, id_, amount_);
    }
    */
    // TODO make payable function to receive eth and wrap?
}
