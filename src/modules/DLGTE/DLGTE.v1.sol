// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {Module} from "src/Kernel.sol";
import {IDLGTEv1} from "modules/DLGTE/IDLGTE.v1.sol";
import {IERC20} from "../../interfaces/IERC20.sol";

/**
 * @title  Olympus Governance Delegation
 * @notice Olympus Governance Delegation (Module) Contract
 * @dev    The Olympus Governance Delegation Module enables policies to delegate gOHM on behalf of accounts.
 *         If the gOHM is undelegated, this module acts as an escrow for the gOHM.
 *         When the gOHM is delegated, new individual escrows are created for those delegates, and that
 *         portion of gOHM is transferred to that escrow.
 *         gOHM balances are tracked per (policy, account) separately such that one policy cannot pull the
 *         gOHM from another policy (eg policy B pulling collateral out of the Cooler policy).
 */
abstract contract DLGTEv1 is Module, IDLGTEv1 {
    // ========= STATE ========= //

    ERC20 internal immutable _gOHM;

    /// @inheritdoc IDLGTEv1
    uint32 public constant override DEFAULT_MAX_DELEGATE_ADDRESSES = 10;

    constructor(address gohm_) {
        _gOHM = ERC20(gohm_);
    }

    // ========= FUNCTIONS ========= //

    /// @inheritdoc IDLGTEv1
    function setMaxDelegateAddresses(
        address account,
        uint32 maxDelegateAddresses
    ) external virtual override;

    /// @inheritdoc IDLGTEv1
    function depositUndelegatedGohm(address onBehalfOf, uint256 amount) external virtual override;

    /// @inheritdoc IDLGTEv1
    function withdrawUndelegatedGohm(address onBehalfOf, uint256 amount, bool autoRescindDelegations) external virtual override;

    /// @inheritdoc IDLGTEv1
    function applyDelegations(
        address onBehalfOf,
        DelegationRequest[] calldata delegationRequests
    )
        external
        virtual
        override
        returns (uint256 totalDelegated, uint256 totalUndelegated, uint256 undelegatedBalance);

    /// @inheritdoc IDLGTEv1
    function rescindDelegations(
        address onBehalfOf,
        uint256 requestedUndelegatedBalance
    ) external virtual override returns (uint256 actualUndelegatedBalance);

    /// @inheritdoc IDLGTEv1
    function policyAccountBalances(
        address policy,
        address account
    ) external view virtual override returns (uint256 gOhmBalance);

    /// @inheritdoc IDLGTEv1
    function accountDelegationsList(
        address account,
        uint256 startIndex,
        uint256 maxItems
    ) external view virtual override returns (AccountDelegation[] memory delegations);

    /// @inheritdoc IDLGTEv1
    function accountDelegationSummary(
        address account
    )
        external
        view
        virtual
        returns (
            uint256 totalGOhm,
            uint256 delegatedGOhm,
            uint256 numDelegateAddresses,
            uint256 maxAllowedDelegateAddresses
        );

    /// @inheritdoc IDLGTEv1
    function totalDelegatedTo(address delegate) external view virtual returns (uint256);

    /// @inheritdoc IDLGTEv1
    function maxDelegateAddresses(
        address account
    ) external view virtual override returns (uint32 result);

    /// @inheritdoc IDLGTEv1
    function gOHM() external view override returns (IERC20) {
        return IERC20(address(_gOHM));
    }
}
