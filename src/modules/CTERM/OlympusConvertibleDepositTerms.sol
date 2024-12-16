// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {ERC721} from "solmate/tokens/ERC721.sol";
import {CTERMv1} from "./CTERM.v1.sol";
import {Kernel, Module} from "src/Kernel.sol";

contract OlympusConvertibleDepositTerms is CTERMv1 {
    constructor(
        address kernel_
    ) Module(Kernel(kernel_)) ERC721("Olympus Convertible Deposit Terms", "OCDT") {}

    // ========== WRAPPING ========== //

    /// @inheritdoc CTERMv1
    /// @dev        This function reverts if:
    ///             - The term ID is invalid
    ///             - The caller is not the owner of the term
    ///             - The term is already wrapped
    function wrap(
        uint256 termId_
    ) external virtual override onlyValidTerm(termId_) onlyTermOwner(termId_) {
        // Does not need to check for invalid term ID because the modifier already ensures that
        ConvertibleDepositTerm storage term = _terms[termId_];

        // Validate that the term is not already wrapped
        if (term.wrapped) revert CTERM_AlreadyWrapped(termId_);

        // Mark the term as wrapped
        term.wrapped = true;

        // Mint the ERC721 token
        _mint(msg.sender, termId_);

        emit TermWrapped(termId_);
    }

    /// @inheritdoc CTERMv1
    /// @dev        This function reverts if:
    ///             - The term ID is invalid
    ///             - The caller is not the owner of the term
    ///             - The term is not wrapped
    function unwrap(
        uint256 termId_
    ) external virtual override onlyValidTerm(termId_) onlyTermOwner(termId_) {
        // Does not need to check for invalid term ID because the modifier already ensures that
        ConvertibleDepositTerm storage term = _terms[termId_];

        // Validate that the term is wrapped
        if (!term.wrapped) revert CTERM_NotWrapped(termId_);

        // Mark the term as unwrapped
        term.wrapped = false;

        // Burn the ERC721 token
        _burn(termId_);

        emit TermUnwrapped(termId_);
    }

    // ========== TERM MANAGEMENT =========== //

    function _create(
        address owner_,
        uint256 remainingDeposit_,
        uint256 conversionPrice_,
        uint48 expiry_,
        bool wrap_
    ) internal returns (uint256 termId) {
        // Create the term record
        termId = ++termCount;
        _terms[termId] = ConvertibleDepositTerm({
            remainingDeposit: remainingDeposit_,
            conversionPrice: conversionPrice_,
            expiry: expiry_,
            wrapped: wrap_
        });

        // Update ERC721 storage
        _ownerOf[termId] = owner_;
        _balanceOf[owner_]++;

        // Add the term ID to the user's list of terms
        _userTerms[owner_].push(termId);

        // If specified, wrap the term
        if (wrap_) _mint(owner_, termId);

        // Emit the event
        emit TermCreated(termId, owner_, remainingDeposit_, conversionPrice_, expiry_, wrap_);

        return termId;
    }

    /// @inheritdoc CTERMv1
    /// @dev        This function reverts if:
    ///             - The caller is not permissioned
    ///             - The owner is the zero address
    ///             - The remaining deposit is 0
    ///             - The conversion price is 0
    ///             - The expiry is in the past
    function create(
        address owner_,
        uint256 remainingDeposit_,
        uint256 conversionPrice_,
        uint48 expiry_,
        bool wrap_
    ) external virtual override permissioned returns (uint256 termId) {
        // Validate that the owner is not the zero address
        if (owner_ == address(0)) revert CTERM_InvalidParams("owner");

        // Validate that the remaining deposit is greater than 0
        if (remainingDeposit_ == 0) revert CTERM_InvalidParams("deposit");

        // Validate that the conversion price is greater than 0
        if (conversionPrice_ == 0) revert CTERM_InvalidParams("conversion price");

        // Validate that the expiry is in the future
        if (expiry_ <= block.timestamp) revert CTERM_InvalidParams("expiry");

        return _create(owner_, remainingDeposit_, conversionPrice_, expiry_, wrap_);
    }

    /// @inheritdoc CTERMv1
    /// @dev        This function reverts if:
    ///             - The caller is not permissioned
    ///             - The term ID is invalid
    function update(
        uint256 termId_,
        uint256 amount_
    ) external virtual override permissioned onlyValidTerm(termId_) {
        // Update the remaining deposit of the term
        ConvertibleDepositTerm storage term = _terms[termId_];
        term.remainingDeposit = amount_;

        // Emit the event
        emit TermUpdated(termId_, amount_);
    }

    /// @inheritdoc CTERMv1
    /// @dev        This function reverts if:
    ///             - The caller is not the owner of the term
    ///             - The amount is 0
    ///             - The amount is greater than the remaining deposit
    ///             - `to_` is the zero address
    function split(
        uint256 termId_,
        uint256 amount_,
        address to_,
        bool wrap_
    )
        external
        virtual
        override
        onlyValidTerm(termId_)
        onlyTermOwner(termId_)
        returns (uint256 newTermId)
    {
        ConvertibleDepositTerm storage term = _terms[termId_];

        // Validate that the amount is greater than 0
        if (amount_ == 0) revert CTERM_InvalidParams("amount");

        // Validate that the amount is less than or equal to the remaining deposit
        if (amount_ > term.remainingDeposit) revert CTERM_InvalidParams("amount");

        // Validate that the to address is not the zero address
        if (to_ == address(0)) revert CTERM_InvalidParams("to");

        // Calculate the remaining deposit of the existing term
        uint256 remainingDeposit = term.remainingDeposit - amount_;

        // Update the remaining deposit of the existing term
        term.remainingDeposit = remainingDeposit;

        // Create the new term
        newTermId = _create(to_, amount_, term.conversionPrice, term.expiry, wrap_);

        // Emit the event
        emit TermSplit(termId_, newTermId, amount_, to_, wrap_);

        return newTermId;
    }

    // ========== ERC721 OVERRIDES ========== //

    /// @inheritdoc ERC721
    function tokenURI(uint256 id_) public view virtual override returns (string memory) {
        // TODO implement tokenURI SVG
        return "";
    }

    /// @inheritdoc ERC721
    /// @dev        This function performs the following:
    ///             - Updates the owner of the term
    ///             - Calls `transferFrom` on the parent contract
    function transferFrom(address from_, address to_, uint256 tokenId_) public override {
        ConvertibleDepositTerm storage term = _terms[tokenId_];

        // Validate that the term is valid
        if (term.conversionPrice == 0) revert CTERM_InvalidTermId(tokenId_);

        // Ownership is validated in `transferFrom` on the parent contract

        // Add to user terms on the destination address
        _userTerms[to_].push(tokenId_);

        // Remove from user terms on the source address
        bool found = false;
        for (uint256 i = 0; i < _userTerms[from_].length; i++) {
            if (_userTerms[from_][i] == tokenId_) {
                _userTerms[from_][i] = _userTerms[from_][_userTerms[from_].length - 1];
                _userTerms[from_].pop();
                found = true;
                break;
            }
        }
        if (!found) revert CTERM_InvalidTermId(tokenId_);

        // Call `transferFrom` on the parent contract
        super.transferFrom(from_, to_, tokenId_);
    }

    // ========== TERM INFORMATION ========== //

    function _getTerm(uint256 termId_) internal view returns (ConvertibleDepositTerm memory) {
        ConvertibleDepositTerm memory term = _terms[termId_];
        // `create()` blocks a 0 conversion price, so this should never happen on a valid term
        if (term.conversionPrice == 0) revert CTERM_InvalidTermId(termId_);

        return term;
    }

    /// @inheritdoc CTERMv1
    function getUserTermIds(
        address user_
    ) external view virtual override returns (uint256[] memory termIds) {
        return _userTerms[user_];
    }

    /// @inheritdoc CTERMv1
    /// @dev        This function reverts if:
    ///             - The term ID is invalid
    function getTerm(
        uint256 termId_
    ) external view virtual override returns (ConvertibleDepositTerm memory) {
        return _getTerm(termId_);
    }

    // ========== MODIFIERS ========== //

    modifier onlyValidTerm(uint256 termId_) {
        if (_getTerm(termId_).conversionPrice == 0) revert CTERM_InvalidTermId(termId_);
        _;
    }

    modifier onlyTermOwner(uint256 termId_) {
        // This validates that the caller is the owner of the term
        if (_ownerOf[termId_] != msg.sender) revert CTERM_NotOwner(termId_);
        _;
    }
}
