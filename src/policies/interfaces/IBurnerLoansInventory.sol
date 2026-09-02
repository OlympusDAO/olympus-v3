// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

/// @title Burner Loans Inventory Interface
/// @notice Custodies supplied OHM and provides cap-bounded funding for one loan facility.
interface IBurnerLoansInventory {
    /// @notice A required address is zero.
    error BurnerLoansInventory_ZeroAddress();

    /// @notice An operation was requested with a zero amount.
    error BurnerLoansInventory_ZeroAmount();

    /// @notice A linked Burner Loans policy is incompatible.
    /// @param policy Invalid policy address.
    error BurnerLoansInventory_InvalidPolicy(address policy);

    /// @notice A caller is not authorized for the requested Inventory operation.
    /// @param caller Unauthorized caller.
    error BurnerLoansInventory_Unauthorized(address caller);

    /// @notice A proposed debt cap is below active principal.
    /// @param cap Proposed global debt cap.
    /// @param activePrincipal Current active principal.
    error BurnerLoansInventory_InvalidCap(uint256 cap, uint256 activePrincipal);

    /// @notice A draw exceeds the remaining global principal capacity.
    /// @param requested Requested OHM amount.
    /// @param available Available OHM capacity.
    error BurnerLoansInventory_InsufficientCapacity(uint256 requested, uint256 available);

    /// @notice A withdrawal exceeds the provider's outstanding claim.
    /// @param requested Requested OHM amount.
    /// @param available Available provider claim.
    error BurnerLoansInventory_InsufficientClaim(uint256 requested, uint256 available);

    /// @notice A withdrawal exceeds supplied OHM currently held idle.
    /// @param requested Requested OHM amount.
    /// @param available Available supplied idle OHM.
    error BurnerLoansInventory_InsufficientIdle(uint256 requested, uint256 available);

    /// @notice A repayment or default exceeds active principal.
    /// @param requested Requested principal reduction.
    /// @param activePrincipal Current active principal.
    error BurnerLoansInventory_ExcessivePrincipal(uint256 requested, uint256 activePrincipal);

    /// @notice The Inventory balance cannot support its recorded liabilities or settlement.
    /// @param required Required OHM balance.
    /// @param actual Actual OHM balance.
    error BurnerLoansInventory_InsufficientBalance(uint256 required, uint256 actual);

    /// @notice A required Kernel module uses an unsupported major version.
    error BurnerLoansInventory_InvalidModuleVersion();

    /// @notice A linked policy or module reports a different OHM token.
    /// @param expected Expected OHM token.
    /// @param actual Reported OHM token.
    error BurnerLoansInventory_InvalidOhm(address expected, address actual);

    /// @notice Emitted when the maximum active principal changes.
    /// @param capOhm New global debt cap in OHM decimals.
    event GlobalDebtCapSet(uint256 capOhm);

    /// @notice Emitted when the authorized Config policy changes.
    /// @param configurator New Config policy.
    event ConfiguratorSet(address indexed configurator);

    /// @notice Emitted when a provider supplies protocol-owned OHM.
    /// @param provider Provider whose claim increases.
    /// @param amount OHM supplied.
    /// @param providerClaimOhm Provider claim after supply.
    /// @param suppliedOhm Aggregate provider claims after supply.
    event OhmSupplied(
        address indexed provider,
        uint256 amount,
        uint256 providerClaimOhm,
        uint256 suppliedOhm
    );

    /// @notice Emitted when a provider withdraws idle supplied OHM.
    /// @param provider Provider whose claim decreases.
    /// @param amount OHM withdrawn.
    /// @param providerClaimOhm Provider claim after withdrawal.
    /// @param suppliedOhm Aggregate provider claims after withdrawal.
    event OhmWithdrawn(
        address indexed provider,
        uint256 amount,
        uint256 providerClaimOhm,
        uint256 suppliedOhm
    );

    /// @notice Emitted when Inventory funds a loan draw.
    /// @param recipient Account receiving OHM.
    /// @param amount Total OHM drawn.
    /// @param suppliedAmount Portion funded from supplied idle OHM.
    /// @param mintedAmount Portion funded by newly minted OHM.
    event OhmDrawn(
        address indexed recipient,
        uint256 amount,
        uint256 suppliedAmount,
        uint256 mintedAmount
    );
    /// @notice Reports the repayment accounted and the portions actually retained and burned.
    /// @dev A failed burn reports zero `burnedAmount`; `OhmBurnFailed` reports the surplus amount.
    /// @param amount Principal repayment settled.
    /// @param retainedAmount Repayment retained to replenish supplied idle OHM.
    /// @param burnedAmount Repayment burned through MINTR.
    event RepaymentSettled(uint256 amount, uint256 retainedAmount, uint256 burnedAmount);

    /// @notice Emitted when defaulted principal is removed from active accounting.
    /// @param amount Principal defaulted.
    event PrincipalDefaulted(uint256 amount);

    /// @notice Reports a failed MINTR approval restoration that requires an admin sync.
    /// @param amount Approval increase that was not applied.
    /// @param failureData Revert data returned by MINTR.
    event ApprovalRestorationFailed(uint256 amount, bytes failureData);
    /// @notice Reports repayment OHM that could not be burned and remains as ordinary surplus.
    /// @param amount Repayment OHM left as surplus.
    /// @param failureData Revert data returned by MINTR.
    event OhmBurnFailed(uint256 amount, bytes failureData);

    /// @notice Emitted after MINTR approval is reconciled to its cap-derived target.
    /// @param approval Resulting mint approval.
    event MintApprovalSynchronized(uint256 approval);

    /// @notice Emitted when all unaccounted OHM surplus is burned.
    /// @param amount Surplus OHM burned.
    event SurplusBurned(uint256 amount);

    /// @notice Emitted when all unaccounted OHM surplus is transferred to Treasury.
    /// @param amount Surplus OHM rescued.
    event SurplusRescued(uint256 amount);

    /// @notice Sets the Burner Loans Config policy authorized to set the global debt cap.
    /// @dev Callable only by OCG admin while Burner Loans Inventory is globally disabled. The
    ///      policy must belong to the same Kernel and point to this contract's immutable facility.
    /// @param configurator_ Burner Loans Config policy to authorize.
    function setConfigurator(address configurator_) external;

    /// @notice Sets the maximum active OHM principal funded by this Burner Loans Inventory.
    /// @dev Reverts when the caller is not Burner Loans' current configurator, the cap is below
    ///      active principal, or MINTR cannot reconcile approval exactly.
    /// @param capOhm_ Maximum active principal, in OHM token decimals.
    function setGlobalDebtCap(uint128 capOhm_) external;

    /// @notice Supplies protocol-owned OHM and creates an equal provider claim.
    /// @dev Reverts if:
    ///      - Burner Loans Inventory is disabled.
    ///      - The caller lacks `burner_loans_inventory_provider`.
    ///      - `amount_` is zero.
    ///      - The OHM transfer fails or Burner Loans Inventory receives an amount different from
    ///        `amount_`.
    /// @param amount_ OHM supplied and credited, in OHM token decimals.
    function supply(uint128 amount_) external;

    /// @notice Withdraws currently idle supplied OHM and reduces the provider claim.
    /// @dev Reverts when Burner Loans Inventory is disabled, the caller lacks
    ///      `burner_loans_inventory_provider`, the amount or recipient is zero, or the amount
    ///      exceeds the caller's claim or the aggregate supplied idle balance.
    /// @param amount_ Supplied OHM to withdraw, in OHM token decimals.
    /// @param recipient_ Account receiving the withdrawn OHM.
    function withdraw(uint128 amount_, address recipient_) external;

    /// @notice Funds a loan draw using supplied OHM first and newly minted OHM second.
    /// @dev OHM is assumed not to charge transfer fees. Reverts when Burner Loans Inventory is
    ///      disabled, the caller is not Burner Loans, an input is zero, or the amount exceeds
    ///      available capacity. Burner Loans owns the origination control.
    /// @param recipient_ Account receiving the funded OHM.
    /// @param amount_ Principal funded, in OHM token decimals.
    function draw(address recipient_, uint128 amount_) external;

    /// @notice Accounts for OHM already transferred to Burner Loans Inventory as principal repayment.
    /// @dev The facility must verify an exact transfer before this call. Reverts when Burner Loans Inventory is
    ///      disabled, the caller is not the facility, the amount is zero or excessive, or the
    ///      Burner Loans Inventory balance does not contain the reported repayment in addition to supplied idle.
    /// @param amount_ Repaid principal to settle, in OHM token decimals.
    function settleRepayment(uint128 amount_) external;

    /// @notice Removes defaulted principal from the active-principal ledger.
    /// @dev Reverts when Burner Loans Inventory is disabled, the caller is not the facility, or the amount is
    ///      zero or greater than active principal. A failed MINTR restoration is reported without
    ///      reverting; an admin may restore capacity later with `syncMintApproval`.
    /// @param amount_ Defaulted principal to remove, in OHM token decimals.
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
