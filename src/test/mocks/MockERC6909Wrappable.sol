// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import {ERC6909Wrappable} from "src/libraries/ERC6909Wrappable.sol";

contract MockERC6909Wrappable is ERC6909Wrappable {
    constructor(address erc20Implementation_) ERC6909Wrappable(erc20Implementation_) {}

    function setTokenMetadata(
        uint256 tokenId_,
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        bytes memory additionalMetadata_
    ) external {
        _createWrappableToken(tokenId_, name_, symbol_, decimals_, additionalMetadata_, false);
    }

    function createWrappedToken(uint256 tokenId_) external returns (address) {
        return address(_getWrappedToken(tokenId_));
    }

    function mint(address to_, uint256 tokenId_, uint256 amount_, bool shouldWrap_) external {
        _mint(to_, tokenId_, amount_, shouldWrap_);
    }

    function burn(address from_, uint256 tokenId_, uint256 amount_, bool wrapped_) external {
        _burn(from_, tokenId_, amount_, wrapped_);
    }
}
