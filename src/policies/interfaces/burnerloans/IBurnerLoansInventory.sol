// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

/// @title Burner Loans Inventory Interface
/// @notice Custodies supplied OHM and provides cap-bounded funding for one loan facility.
interface IBurnerLoansInventory {
    // ========== EVENTS ========== //

    /// @notice Emitted when the maximum active principal changes.
    /// @param capOhm New global debt cap in OHM decimals.
    event GlobalDebtCapSet(uint256 capOhm);

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

    // ========== ERRORS ========== //

    /// @notice A required address is zero.
    error BurnerLoansInventory_ZeroAddress();

    /// @notice An operation was requested with a zero amount.
    error BurnerLoansInventory_ZeroAmount();

    /// @notice The immutable Burner Loans Core binding is incompatible.
    /// @param core Invalid Core address.
    error BurnerLoansInventory_InvalidCore(address core);

    /// @notice A proposed debt cap is below active principal.
    /// @param cap Proposed global debt cap.
    /// @param activePrincipal Current active principal.
    error BurnerLoansInventory_InvalidCap(uint256 cap, uint256 activePrincipal);

    /// @notice A draw exceeds cap-bounded funding capacity, including available mint approval.
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

    // ========== FUNCTIONS ========== //

    /// @notice Sets the maximum active OHM principal funded by this Burner Loans Inventory.
    /// @dev Reconciles MINTR approval against current principal and provider idle, even for an unchanged cap.
    ///      An unchanged cap emits no GlobalDebtCapSet event.
    /// @param capOhm_ Maximum active principal, in OHM token decimals.
    function setGlobalDebtCap(uint128 capOhm_) external;

    /// @notice Supplies protocol-owned OHM and creates an equal provider claim.
    /// @param amount_ OHM supplied and credited, in OHM token decimals.
    function supply(uint128 amount_) external;

    /// @notice Withdraws currently idle supplied OHM and reduces the provider claim.
    ///
    /// @param amount_ Supplied OHM to withdraw, in OHM token decimals.
    /// @param recipient_ Account receiving the withdrawn OHM.
    function withdraw(uint128 amount_, address recipient_) external;

    /// @notice Funds a loan draw using supplied OHM first and newly minted OHM second.
    /// @dev OHM is assumed not to charge transfer fees. Burner Loans owns origination control.
    ///
    /// @param recipient_ Account receiving the funded OHM.
    /// @param amount_ Principal funded, in OHM token decimals.
    function draw(address recipient_, uint128 amount_) external;

    /// @notice Accounts for OHM already transferred to Burner Loans Inventory as principal repayment.
    /// @dev The facility must verify an exact transfer before this call.
    ///
    /// @param amount_ Repaid principal to settle, in OHM token decimals.
    function settleRepayment(uint128 amount_) external;

    /// @notice Removes defaulted principal from the active-principal ledger.
    /// @dev A failed MINTR restoration is reported without reverting;
    ///      administration may restore capacity later with syncMintApproval.
    ///
    /// @param amount_ Defaulted principal to remove, in OHM token decimals.
    function settleDefault(uint128 amount_) external;

    /// @notice Administratively reconciles MINTR approval to the desired cap-derived amount.
    /// @dev This recovery operation may restore an unrecorded approval deficit.
    ///
    /// @return approval_ Reconciled MINTR approval for Burner Loans Inventory.
    function syncMintApproval() external returns (uint256 approval_);

    /// @notice Burns all unaccounted OHM surplus through MINTR.
    /// @dev Accepts governance ADMIN or the nonzero config operator. Inventory must be active
    ///      and locally enabled. Does nothing when there is no surplus; protects supplied idle OHM.
    function burnSurplus() external;

    /// @notice Transfers all unaccounted OHM surplus to TRSRY.
    /// @dev Accepts governance ADMIN or the nonzero config operator, including while locally
    ///      disabled. Inventory must remain Kernel-active. Does nothing when there is no surplus;
    ///      supplied idle OHM and provider claims are preserved.
    function rescueSurplus() external;

    /// @notice Returns the OHM token funded by Burner Loans Inventory.
    /// @return address The OHM token address.
    function ohm() external view returns (address);

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
