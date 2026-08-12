// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";

/// @title Burner Loans Inventory Interface
/// @notice Custodies supplied OHM and provides cap-bounded funding for one loan facility.
interface IBurnerLoansInventory is IERC165 {
    error BurnerLoansInventory_ZeroAddress();
    error BurnerLoansInventory_ZeroAmount();
    error BurnerLoansInventory_InvalidPolicy(address policy);
    error BurnerLoansInventory_Unauthorized(address caller);
    error BurnerLoansInventory_InvalidCap(uint256 cap, uint256 activePrincipal);
    error BurnerLoansInventory_InsufficientCapacity(uint256 requested, uint256 available);
    error BurnerLoansInventory_InsufficientClaim(uint256 requested, uint256 available);
    error BurnerLoansInventory_InsufficientIdle(uint256 requested, uint256 available);
    error BurnerLoansInventory_ExcessivePrincipal(uint256 requested, uint256 activePrincipal);
    error BurnerLoansInventory_InsufficientBalance(uint256 required, uint256 actual);
    error BurnerLoansInventory_InvalidModuleVersion();
    error BurnerLoansInventory_InvalidOhm(address expected, address actual);

    event GlobalDebtCapSet(uint256 capOhm);
    event ConfiguratorSet(address indexed configurator);
    event OhmSupplied(
        address indexed provider,
        uint256 amount,
        uint256 providerClaimOhm,
        uint256 suppliedOhm
    );
    event OhmWithdrawn(
        address indexed provider,
        uint256 amount,
        uint256 providerClaimOhm,
        uint256 suppliedOhm
    );
    event OhmDrawn(
        address indexed recipient,
        uint256 amount,
        uint256 suppliedAmount,
        uint256 mintedAmount
    );
    /// @notice Reports the repayment accounted and the portions actually retained and burned.
    /// @dev A failed burn reports zero `burnedAmount`; `OhmBurnFailed` reports the surplus amount.
    event RepaymentSettled(uint256 amount, uint256 retainedAmount, uint256 burnedAmount);
    event PrincipalDefaulted(uint256 amount);
    /// @notice Reports a failed MINTR approval restoration that requires an admin sync.
    /// @param amount Approval increase that was not applied.
    /// @param failureData Revert data returned by MINTR.
    event ApprovalRestorationFailed(uint256 amount, bytes failureData);
    /// @notice Reports repayment OHM that could not be burned and remains as ordinary surplus.
    /// @param amount Repayment OHM left as surplus.
    /// @param failureData Revert data returned by MINTR.
    event OhmBurnFailed(uint256 amount, bytes failureData);
    event MintApprovalSynchronized(uint256 approval);
    event SurplusBurned(uint256 amount);
    event SurplusRescued(uint256 amount);

    /// @notice Sets the Burner Loans Config policy authorized to set the global debt cap.
    /// @dev Callable only by OCG admin while Burner Loans Inventory is globally disabled. The
    ///      policy must belong to the same Kernel and point to this contract's immutable facility.
    function setConfigurator(address configurator_) external;

    /// @notice Sets the maximum active OHM principal funded by this Burner Loans Inventory.
    /// @dev Reverts when the caller is not Burner Loans' current configurator, the cap is below
    ///      active principal, or MINTR cannot reconcile approval exactly.
    function setGlobalDebtCap(uint128 capOhm_) external;

    /// @notice Supplies protocol-owned OHM and creates an equal provider claim.
    /// @dev OHM is assumed not to charge transfer fees. Reverts when Burner Loans Inventory is
    ///      disabled, the caller lacks `burner_loans_inventory_provider`, or the amount is zero.
    function supply(uint128 amount_) external;

    /// @notice Withdraws currently idle supplied OHM and reduces the provider claim.
    /// @dev Reverts when Burner Loans Inventory is disabled, the caller lacks
    ///      `burner_loans_inventory_provider`, the amount or recipient is zero, or the amount
    ///      exceeds the caller's claim or the aggregate supplied idle balance.
    function withdraw(uint128 amount_, address recipient_) external;

    /// @notice Funds a loan draw using supplied OHM first and newly minted OHM second.
    /// @dev OHM is assumed not to charge transfer fees. Reverts when Burner Loans Inventory is
    ///      disabled, the caller is not Burner Loans, an input is zero, or the amount exceeds
    ///      available capacity. Burner Loans owns the origination control.
    function draw(address recipient_, uint128 amount_) external;

    /// @notice Accounts for OHM already transferred to Burner Loans Inventory as principal repayment.
    /// @dev The facility must verify an exact transfer before this call. Reverts when Burner Loans Inventory is
    ///      disabled, the caller is not the facility, the amount is zero or excessive, or the
    ///      Burner Loans Inventory balance does not contain the reported repayment in addition to supplied idle.
    function settleRepayment(uint128 amount_) external;

    /// @notice Removes defaulted principal from the active-principal ledger.
    /// @dev Reverts when Burner Loans Inventory is disabled, the caller is not the facility, or the amount is
    ///      zero or greater than active principal. A failed MINTR restoration is reported without
    ///      reverting; an admin may restore capacity later with `syncMintApproval`.
    function recordDefault(uint128 amount_) external;

    /// @notice Administratively reconciles MINTR approval to the desired cap-derived amount.
    /// @dev This break-glass operation may restore an unrecorded approval deficit. Reverts when
    ///      Burner Loans Inventory is disabled, MINTR reconciliation fails, or the caller lacks
    ///      `burner_loans_admin`.
    /// @return approval_ Reconciled MINTR approval for Burner Loans Inventory.
    function syncMintApproval() external returns (uint256 approval_);

    /// @notice Burns all unaccounted OHM surplus through MINTR.
    /// @dev Reverts when Burner Loans Inventory is disabled, the caller is not an admin, or MINTR
    ///      rejects the burn. Does nothing when there is no surplus.
    function burnSurplus() external;

    /// @notice Transfers all unaccounted OHM surplus to TRSRY.
    /// @dev Reverts when Burner Loans Inventory is disabled or the caller is not an admin. Does
    ///      nothing when there is no surplus.
    function rescueSurplus() external;

    /// @notice Returns the OHM token funded by Burner Loans Inventory.
    /// @return address The OHM token address.
    function ohm() external view returns (address);

    /// @notice Returns the Burner Loans Config policy authorized by this contract.
    /// @return address The Burner Loans Config address.
    function configurator() external view returns (address);

    /// @notice Returns the immutable loan facility.
    /// @return address The facility policy address.
    function facility() external view returns (address);

    /// @notice Returns the maximum active OHM principal.
    /// @return uint128 The global debt cap in OHM token decimals.
    function globalDebtCapOhm() external view returns (uint128);

    /// @notice Returns the aggregate principal currently outstanding.
    /// @return uint128 The active principal in OHM token decimals.
    function activePrincipalOhm() external view returns (uint128);

    /// @notice Returns supplied OHM currently held and available to fund draws or withdrawals.
    /// @return uint128 The idle supplied balance in OHM token decimals.
    function suppliedIdleOhm() external view returns (uint128);

    /// @notice Returns all providers' aggregate outstanding supplied-OHM claim.
    /// @return uint128 The aggregate provider claim in OHM token decimals.
    function suppliedOhm() external view returns (uint128);

    /// @notice Returns one provider's outstanding supplied-OHM claim.
    /// @param provider_ Provider whose claim is queried.
    /// @return uint128 The provider claim in OHM token decimals.
    function providerClaimOhm(address provider_) external view returns (uint128);

    /// @notice Returns the cap-derived target for Burner Loans Inventory's MINTR approval.
    /// @return uint256 The desired MINTR approval in OHM token decimals.
    function desiredMintApproval() external view returns (uint256);

    /// @notice Returns the amount that can currently be drawn without exceeding the cap.
    /// @return uint256 The drawable capacity in OHM token decimals.
    function availableCapacity() external view returns (uint256);

    /// @notice Returns raw OHM not accounted as supplied idle.
    /// @return uint256 The unaccounted OHM balance in OHM token decimals.
    function surplusOhm() external view returns (uint256);
}
