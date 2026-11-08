// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

/// @notice Permanent custody and accounting boundary. Operation-role holders settle user operations.
interface IBurnerLoansCore {
    // ========== EVENTS ========== //

    /// @notice The full unreserved balance was sent to a rescue destination.
    /// @param token Recovered token.
    /// @param destination Rescue recipient.
    /// @param amount Transferred amount.
    event AssetRescued(address indexed token, address indexed destination, uint256 amount);

    /// @notice Emitted at initial construction and each Payout replacement.
    /// @param previousPayout Previous selection, or zero during construction.
    /// @param payout New selected custody; old pending claims remain at previousPayout.
    event PayoutSet(address indexed previousPayout, address indexed payout);

    /// @notice Emitted when OCG ADMIN selects replaceable economic code.
    /// @param risk Selected same-Kernel/OHM Risk policy.
    event RiskSet(address indexed risk);

    /// @notice Emitted when the Burner Loans Inventory contract is bound or replaced.
    /// @param inventory New Burner Loans Inventory policy.
    event InventorySet(address indexed inventory);

    /// @notice Emitted when Config registers a newly created collateral market.
    /// @param asset Collateral asset added to the append-only registry.
    event AssetRegistered(address indexed asset);

    /// @notice Emitted for each borrower included in a successful seizure batch.
    /// @param caller Keeper that initiated the seizure.
    /// @param asset Collateral asset seized from the position.
    /// @param borrower Borrower whose position defaulted.
    /// @param debtOhm Principal defaulted, in OHM decimals.
    /// @param collateral Asset-denominated collateral credit removed from the position.
    event Seized(
        address indexed caller,
        address indexed asset,
        address indexed borrower,
        uint256 debtOhm,
        uint256 collateral
    );

    /// @notice Emitted after a seizure batch is settled and collateral is distributed.
    /// @param caller Keeper that initiated the seizure.
    /// @param asset Collateral asset settled by the batch.
    /// @param borrowerCount Number of borrowers seized.
    /// @param seizedDebtOhm Aggregate principal defaulted, in OHM decimals.
    /// @param seizedCollateral Aggregate collateral seized.
    /// @param tokenOut Token returned by DepositManager.
    /// @param keeperReward Output-token amount awarded to the keeper.
    /// @param collateralToTreasury Output-token amount routed to Treasury.
    event SeizureBatchSettled(
        address indexed caller,
        address indexed asset,
        uint256 borrowerCount,
        uint256 seizedDebtOhm,
        uint256 seizedCollateral,
        address tokenOut,
        uint256 keeperReward,
        uint256 collateralToTreasury
    );

    // ========== ERRORS ========== //

    /// @notice OHM has no code or does not report supported token decimals.
    error BurnerLoansCore_InvalidOhm(address ohm);

    /// @notice Payout lacks compatible Core-bound metadata or is unavailable.
    error BurnerLoansCore_InvalidPayout(address payout);

    /// @notice A registered asset cannot be reassigned to another market.
    error BurnerLoansCore_MarketMismatch(
        address asset,
        uint32 currentMarket,
        uint32 proposedMarket
    );

    /// @notice The Risk replacement lacks required interfaces or uses another OHM token.
    /// @param candidate Invalid replacement calculator.
    error BurnerLoansCore_InvalidRisk(address candidate);

    /// @notice The supplied DepositManager does not implement the required interface.
    /// @param depositManager Invalid DepositManager address.
    error BurnerLoansCore_InvalidDepositManager(address depositManager);

    /// @notice The supplied Burner Loans Inventory does not implement the expected interface.
    /// @param inventory Invalid Burner Loans Inventory address.
    error BurnerLoansCore_InvalidInventory(address inventory);

    /// @notice An operation was requested with a zero token amount.
    error BurnerLoansCore_ZeroAmount();

    /// @notice A collateral deposit produced no asset-denominated collateral credit.
    error BurnerLoansCore_ZeroCollateralCredit();

    /// @notice A collateral withdrawal produced no assets.
    error BurnerLoansCore_ZeroCollateralWithdrawal();

    /// @notice The borrower has no outstanding debt for the asset.
    error BurnerLoansCore_NoDebt();

    /// @notice Burner Loans could not approve the ReceiptTokenManager for collateral custody.
    /// @param receiptTokenManager ReceiptTokenManager whose approval failed.
    error BurnerLoansCore_ReceiptApprovalFailed(address receiptTokenManager);

    /// @notice The collateral asset is not registered by Burner Loans.
    /// @param asset Unregistered collateral asset.
    error BurnerLoansCore_AssetNotConfigured(address asset);

    /// @notice New originations are disabled for the collateral asset.
    /// @param asset Collateral asset whose originations are disabled.
    error BurnerLoansCore_AssetOriginationsDisabled(address asset);

    /// @notice Custodied collateral is insufficient to cover recorded liabilities.
    /// @param asset Insolvent collateral asset.
    /// @param liabilities Collateral liabilities, in collateral token decimals.
    /// @param assets Collateral assets held in custody, in collateral token decimals.
    /// @param borrowed Collateral currently borrowed from custody, in collateral token decimals.
    error BurnerLoansCore_Insolvent(
        address asset,
        uint256 liabilities,
        uint256 assets,
        uint256 borrowed
    );

    /// @notice A custody receipt, output token or market identity disagrees with the settlement instruction.
    error BurnerLoansCore_InvalidSettlement();

    /// @notice The combined protocol and referral fee exceeds the uint256 maximum.
    /// @param protocolFee Protocol allocation, in collateral token decimals.
    /// @param referralFee Referral allocation, in collateral token decimals.
    error BurnerLoansCore_FeeOverflow(uint256 protocolFee, uint256 referralFee);

    // ========== STRUCTS ========== //

    /// @notice Complete configuration decoded from a Burner Loans FLOAN market.
    /// @dev Shared by market administration and servicing policies; FLOAN stores the canonical values.
    /// @param originationsEnabled Whether new debt may be originated against the asset.
    /// @param withdrawAsShares Whether custody exits return the ERC-4626 share token.
    /// @param collateralDecimals Decimal precision of the collateral token.
    /// @param maxLtvBps Maximum loan-to-value ratio applied to collateral value.
    /// @param backingMultiplierBps Multiplier applied to the protocol backing floor.
    /// @param keeperRewardBps Share of underlying-denominated seized collateral awarded to the keeper.
    /// @param termLength Duration added to the current timestamp for a new maturity.
    /// @param maxMaturityHorizon Maximum permitted distance between maturity and current time.
    /// @param debtCap Maximum active principal for the asset, in OHM decimals.
    /// @param maxKeeperReward Maximum keeper reward, in underlying collateral decimals.
    struct AssetConfig {
        bool originationsEnabled;
        bool withdrawAsShares;
        uint8 collateralDecimals;
        uint16 maxLtvBps;
        uint16 backingMultiplierBps;
        uint16 keeperRewardBps;
        uint48 termLength;
        uint48 maxMaturityHorizon;
        uint128 debtCap;
        uint128 maxKeeperReward;
    }

    /// @notice Prices and backing captured by Risk for one operation; never persisted on Core.
    /// @param ohmUsdPrice USD price per whole OHM token, in PRICE decimals.
    /// @param collateralUsdPrice USD price per whole underlying collateral token, in PRICE decimals.
    /// @param backingPerOhmUsd Protocol backing per whole OHM token, in PRICE decimals.
    struct PriceSnapshot {
        uint256 ohmUsdPrice;
        uint256 collateralUsdPrice;
        uint256 backingPerOhmUsd;
    }

    /// @notice A borrower's collateral and debt position for one collateral asset.
    /// @param depositedCollateral Withdrawable collateral credit, in collateral token decimals.
    /// @param debtOhm Outstanding principal, in OHM decimals.
    /// @param maturity Position maturity timestamp.
    /// @param lastBorrowBlock Block number of the position's latest borrow.
    struct Position {
        uint256 depositedCollateral;
        uint128 debtOhm;
        uint48 maturity;
        uint48 lastBorrowBlock;
    }

    /// @notice Current custody accounting for one collateral asset.
    /// @param shares Payout shares attributed to Burner Loans; raw asset units when no vault is configured.
    /// @param assets Assets represented by the custody shares, in collateral token decimals.
    /// @param borrowed Assets temporarily borrowed from custody, in collateral token decimals.
    /// @param liabilities Collateral owed to borrowers, in collateral token decimals.
    /// @param claimableYield Maximum underlying-output yield reported by DepositManager after
    ///        borrowed assets, liabilities, and its one-unit redemption buffer, in collateral
    ///        token decimals. Share-mode claims can additionally reclaim the final solvent unit.
    /// @param solvent Whether custody assets plus borrowed assets cover liabilities.
    struct AssetCollateralStatus {
        uint256 shares;
        uint256 assets;
        uint256 borrowed;
        uint256 liabilities;
        uint256 claimableYield;
        bool solvent;
    }

    /// @notice Projected aggregate result of a seizure batch.
    /// @param seizedDebtOhm Principal defaulted, in OHM decimals.
    /// @param seizedCollateral Collateral seized, in collateral token decimals.
    /// @param tokenOut Token returned by DepositManager.
    /// @param collateralToTreasury Output-token amount routed to Treasury.
    /// @param keeperReward Output-token amount awarded to the keeper.
    struct SeizePreview {
        uint256 seizedDebtOhm;
        uint256 seizedCollateral;
        address tokenOut;
        uint256 collateralToTreasury;
        uint256 keeperReward;
    }

    /// @notice A complete borrow instruction, including the actual payer and policy-approved protocol and referral fees.
    /// @param asset Configured underlying collateral token identifying the market.
    /// @param borrower Account whose position incurs debt.
    /// @param payer Actual action caller paying the total fee (protocolFee + referralFee).
    /// @param recipient Account receiving principal.
    /// @param amount Principal to add, in OHM units.
    /// @param maturity Policy-approved maturity timestamp in seconds.
    /// @param protocolFee Protocol fee allocation in underlying collateral units.
    /// @param referrer Referral recipient; zero requires a zero referralFee, while a nonzero address may receive zero.
    /// @param referralFee Referrer allocation in underlying collateral units.
    struct BorrowRequest {
        address asset;
        address borrower;
        address payer;
        address recipient;
        uint128 amount;
        uint48 maturity;
        uint256 protocolFee;
        address referrer;
        uint256 referralFee;
    }

    // ========== FUNCTIONS ========== //

    /// @notice Credits only the collateral actually recorded by DepositManager.
    /// @param asset Configured underlying collateral token.
    /// @param amount Requested deposit in underlying token units.
    /// @param payer Actual action caller funding the deposit.
    /// @param borrower Account receiving collateral credit.
    /// @return credit Actual collateral credit in underlying units.
    /// @return collateral Borrower collateral after settlement in underlying units.
    function settleDeposit(
        address asset,
        uint128 amount,
        address payer,
        address borrower
    ) external returns (uint128 credit, uint128 collateral);

    /// @notice Debits collateral and completes the custody exit atomically.
    /// @param asset Configured underlying collateral token.
    /// @param amount Collateral credit to debit, in underlying units.
    /// @param borrower Account whose collateral is withdrawn.
    /// @param recipient Account receiving underlying tokens or vault shares.
    /// @return token Underlying collateral or vault share output token.
    /// @return output Actual amount returned in output token units.
    /// @return remaining Borrower collateral remaining in underlying units.
    function settleWithdraw(
        address asset,
        uint128 amount,
        address borrower,
        address recipient
    ) external returns (address token, uint256 output, uint128 remaining);

    /// @notice Increases principal, collects protocolFee + referralFee and funds the recipient atomically.
    /// @param request Policy-approved principal, maturity, separate fee allocations and actual payer/recipient identities.
    /// @return principal Outstanding borrower principal in OHM units.
    /// @return maturity Resulting maturity timestamp in seconds.
    function settleBorrow(
        BorrowRequest calldata request
    ) external returns (uint128 principal, uint48 maturity);

    /// @notice Collects exact OHM into Inventory and decreases principal atomically; no price read is required.
    /// @param asset Configured collateral token identifying the market.
    /// @param amount Principal to repay, in OHM units.
    /// @param payer Actual action caller paying OHM.
    /// @param borrower Account whose principal is reduced.
    /// @return principal Outstanding borrower principal in OHM units.
    function settleRepay(
        address asset,
        uint128 amount,
        address payer,
        address borrower
    ) external returns (uint128 principal);

    /// @notice Applies the policy-selected maturity and collects the total extension fee (protocolFee + referralFee).
    /// @param asset Configured collateral token identifying the market.
    /// @param borrower Account whose debt maturity is updated.
    /// @param payer Actual action caller paying the total extension fee (protocolFee + referralFee).
    /// @param maturity Policy-approved new maturity timestamp in seconds.
    /// @param protocolFee Protocol fee allocation in underlying collateral units.
    /// @param referrer Referral recipient; zero requires a zero referralFee, while a nonzero address may receive zero.
    /// @param referralFee Referrer allocation in underlying collateral units.
    /// @return newMaturity Applied maturity timestamp in seconds.
    function settleExtend(
        address asset,
        address borrower,
        address payer,
        uint48 maturity,
        uint256 protocolFee,
        address referrer,
        uint256 referralFee
    ) external returns (uint48 newMaturity);

    /// @notice Defaults and redeems a complete batch, allocating only actual received collateral.
    /// @param asset Configured underlying collateral token.
    /// @param borrowers Distinct accounts approved for liquidation by the calling policy.
    /// @param keeper Keeper identity, or zero for a protocol caller.
    /// @param snapshot Operation-local prices and backing used for all keeper allocations.
    /// @return result Batch principal, actual redemption proceeds and allocated payouts.
    function settleSeize(
        address asset,
        address[] calldata borrowers,
        address keeper,
        PriceSnapshot calldata snapshot
    ) external returns (SeizePreview memory result);

    /// @notice Returns the registered market identifier, including market zero.
    /// @param asset Registered underlying collateral token.
    /// @return market Canonical registered FLOAN market identifier.
    function marketId(address asset) external view returns (uint32 market);

    /// @notice Whether Config has registered this asset's canonical market.
    /// @param asset Underlying collateral token to query.
    /// @return registered Whether Config has registered a canonical market for the asset.
    function isAssetRegistered(address asset) external view returns (bool registered);

    /// @notice Number of append-only registered assets.
    /// @return count Number of registered assets.
    function getAssetCount() external view returns (uint256 count);

    /// @notice Registered asset at an index.
    /// @param index Zero-based index in the registered asset list.
    /// @return asset Registered underlying collateral token at the index.
    function getAssetAt(uint256 index) external view returns (address asset);

    /// @notice Immutable debt token used by Core and Inventory.
    /// @return token Immutable debt token.
    function ohm() external view returns (address token);

    /// @notice Immutable custody contract whose operator is this Core.
    /// @return custodian Immutable operator-namespaced collateral custodian.
    function depositManager() external view returns (address custodian);

    /// @notice Selected OHM funding and provider-claim contract.
    /// @return funding Current principal funding and provider-claim contract.
    function inventory() external view returns (address funding);

    /// @notice Current FLOAN module containing Core's markets and positions.
    /// @return module Current fixed-term position storage module.
    function floan() external view returns (address module);

    /// @notice Selected pricing and economic implementation.
    /// @return evaluator Current pricing and economic implementation.
    function risk() external view returns (address evaluator);

    /// @notice Canonical principal across this Core's FLOAN markets.
    /// @return principal Aggregate outstanding principal in OHM units.
    function totalActiveDebtOhm() external view returns (uint256 principal);

    /// @notice OCG ADMIN installs an operational Risk with matching OHM, Kernel and immutable Core binding.
    /// @dev Installation preserves the replacement's configuration authority and existing positions.
    /// @param risk Replacement economic and pricing contract bound to this Core.
    function setRisk(address risk) external;

    /// @notice OCG ADMIN binds operational Inventory with matching canonical debt and migrated aggregate claims.
    /// @param inventory Replacement funding contract bound to this Core and its OHM token.
    function setInventory(address inventory) external;

    /// @notice Config registers a created market or updates its custody output mode.
    /// @param asset Underlying collateral token for the canonical market.
    /// @param market FLOAN market identifier created for this facility.
    /// @param withdrawAsShares Whether custody exits return vault shares instead of underlying tokens.
    function registerMarket(address asset, uint32 market, bool withdrawAsShares) external;

    /// @notice Completes a YieldClaimerTask-approved direct payment using Core's DepositManager identity.
    /// @param asset Configured underlying collateral token.
    /// @param requested Yield amount approved by the caller, in underlying token units.
    /// @param recipient Treasury or RevenueDistributor selected by the trusted YieldClaimerTask.
    /// @return token Actual underlying or share output token.
    /// @return output Actual yield paid in output token units.
    function settleYield(
        address asset,
        uint256 requested,
        address recipient
    ) external returns (address token, uint256 output);

    /// @notice Selected Payout receiving new fees and seizure proceeds directly.
    /// @return payout Custodian receiving new fees and liquidation proceeds.
    function payout() external view returns (address payout);

    /// @notice OCG ADMIN selects a Core-bound Payout; existing obligations remain on their old Payout.
    /// @param payout Replacement payout custodian bound to this Core.
    function setPayout(address payout) external;

    /// @notice Requires Core's reentrancy guard to be idle before an external component mutates shared custody.
    function requireNotReentrant() external view;

    /// @notice Selected Config or OCG ADMIN rescues only Core's own unreserved token balances.
    /// @param token Token whose full unreserved Core balance is rescued.
    /// @param destination Account receiving Core surplus.
    function rescue(address token, address destination) external;

    /// @notice Quotes Core's current direct token balance for any requester.
    /// @param token Token whose recoverable direct balance is quoted.
    /// @param destination Prospective recovery recipient.
    /// @return amount Current recoverable balance; a quote grants no execution authority.
    function previewRescue(
        address token,
        address destination
    ) external view returns (uint256 amount);
}
