// SPDX-License-Identifier: BSD
pragma solidity >=0.8.0;

import {CloneERC20} from "src/external/clones/CloneERC20.sol";

/// @notice EIP-2612 permit extension for CloneERC20 tokens.
/// @author Adapted from Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/tokens/ERC20.sol)
abstract contract CloneERC20Permit is CloneERC20 {
    /*///////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error CloneERC20Permit_PermitDeadlineExpired();
    error CloneERC20Permit_InvalidSigner();
    error CloneERC20Permit_DomainSeparatorAlreadyUpdated();

    /*///////////////////////////////////////////////////////////////
                             EIP-2612 STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(address => uint256) public nonces;

    bytes32 public constant PERMIT_TYPEHASH =
        keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );

    uint256 public chainId;

    bytes32 internal domainSeparator;

    /*///////////////////////////////////////////////////////////////
                              EIP-2612 LOGIC
    //////////////////////////////////////////////////////////////*/

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual {
        if (deadline < block.timestamp) revert CloneERC20Permit_PermitDeadlineExpired();

        // Unchecked because the only math done is incrementing
        // the owner's nonce which cannot realistically overflow.
        unchecked {
            bytes32 digest = keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(
                            PERMIT_TYPEHASH,
                            owner,
                            spender,
                            value,
                            nonces[owner]++,
                            deadline
                        )
                    )
                )
            );

            address recoveredAddress = ecrecover(digest, v, r, s);

            if (recoveredAddress == address(0) || recoveredAddress != owner)
                revert CloneERC20Permit_InvalidSigner();

            allowance[recoveredAddress][spender] = value;
        }

        emit Approval(owner, spender, value);
    }

    function DOMAIN_SEPARATOR() public view virtual returns (bytes32) {
        return block.chainid == chainId ? domainSeparator : computeDomainSeparator();
    }

    function computeDomainSeparator() internal view virtual returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    keccak256(
                        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                    ),
                    keccak256(bytes(name())),
                    keccak256("1"),
                    block.chainid,
                    address(this)
                )
            );
    }

    function updateDomainSeparator() external {
        if (block.chainid == chainId) revert CloneERC20Permit_DomainSeparatorAlreadyUpdated();

        chainId = block.chainid;

        domainSeparator = computeDomainSeparator();
    }
}
