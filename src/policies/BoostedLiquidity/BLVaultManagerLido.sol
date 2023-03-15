// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

// Import system dependencies
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {ROLESv1, RolesConsumer} from "src/modules/ROLES/OlympusRoles.sol";
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";
import "src/Kernel.sol";

// Import external dependencies
import {AggregatorV3Interface} from "interfaces/AggregatorV2V3Interface.sol";
import {IAuraRewardPool, IAuraMiningLib} from "policies/BoostedLiquidity/interfaces/IAura.sol";
import {JoinPoolRequest, IVault, IBasePool, IBalancerHelper} from "policies/BoostedLiquidity/interfaces/IBalancer.sol";
import {IWsteth} from "policies/BoostedLiquidity/interfaces/ILido.sol";

// Import vault dependencies
import {RewardsData} from "policies/BoostedLiquidity/interfaces/IBLVaultLido.sol";
import {IBLVaultManagerLido} from "policies/BoostedLiquidity/interfaces/IBLVaultManagerLido.sol";
import {BLVaultLido} from "policies/BoostedLiquidity/BLVaultLido.sol";

// Import libraries
import {ClonesWithImmutableArgs} from "clones/ClonesWithImmutableArgs.sol";

contract BLVaultManagerLido is Policy, IBLVaultManagerLido, RolesConsumer {
    using ClonesWithImmutableArgs for address;

    // ========= ERRORS ========= //

    error BLManagerLido_Inactive();
    error BLManagerLido_InvalidVault();
    error BLManagerLido_LimitViolation();
    error BLManagerLido_InvalidLpAmount();
    error BLManagerLido_InvalidLimit();
    error BLManagerLido_InvalidFee();
    error BLManagerLido_BadPriceFeed();
    error BLManagerLido_VaultAlreadyExists();

    // ========= EVENTS ========= //

    event VaultDeployed(address vault, address owner, uint64 fee);

    // ========= STATE VARIABLES ========= //

    // Modules
    MINTRv1 public MINTR;
    TRSRYv1 public TRSRY;

    // Tokens
    address public ohm;
    address public pairToken; // wstETH for this implementation
    address public aura;
    address public bal;

    // Exchange Info
    string public exchangeName;
    BalancerData public balancerData;

    // Aura Info
    AuraData public auraData;
    IAuraMiningLib public auraMiningLib;

    // Oracle Info
    OracleFeed public ohmEthPriceFeed;
    OracleFeed public stethEthPriceFeed;

    // Vault Info
    BLVaultLido public implementation;
    mapping(BLVaultLido => address) public vaultOwners;
    mapping(address => BLVaultLido) public userVaults;

    // Vaults State
    uint256 public totalLp;
    uint256 public deployedOhm;
    uint256 public circulatingOhmBurned;

    // System Configuration
    uint256 public ohmLimit;
    uint64 public currentFee;
    bool public isLidoBLVaultActive;

    // Constants
    uint32 public constant MAX_FEE = 10000; // 100%

    //============================================================================================//
    //                                      POLICY SETUP                                          //
    //============================================================================================//

    constructor(
        Kernel kernel_,
        TokenData memory tokenData_,
        BalancerData memory balancerData_,
        AuraData memory auraData_,
        address auraMiningLib_,
        OracleFeed memory ohmEthPriceFeed_,
        OracleFeed memory stethEthPriceFeed_,
        address implementation_,
        uint256 ohmLimit_,
        uint64 fee_
    ) Policy(kernel_) {
        // Set exchange name
        {
            exchangeName = "Balancer";
        }

        // Set tokens
        {
            ohm = tokenData_.ohm;
            pairToken = tokenData_.pairToken;
            aura = tokenData_.aura;
            bal = tokenData_.bal;
        }

        // Set exchange info
        {
            balancerData = balancerData_;
        }

        // Set Aura Pool
        {
            auraData = auraData_;
            auraMiningLib = IAuraMiningLib(auraMiningLib_);
        }

        // Set oracle info
        {
            ohmEthPriceFeed = ohmEthPriceFeed_;
            stethEthPriceFeed = stethEthPriceFeed_;
        }

        // Set vault implementation
        {
            implementation = BLVaultLido(implementation_);
        }

        // Configure system
        {
            ohmLimit = ohmLimit_;
            currentFee = fee_;
        }
    }

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](3);
        dependencies[0] = toKeycode("MINTR");
        dependencies[1] = toKeycode("TRSRY");
        dependencies[2] = toKeycode("ROLES");

        MINTR = MINTRv1(getModuleAddress(dependencies[0]));
        TRSRY = TRSRYv1(getModuleAddress(dependencies[1]));
        ROLES = ROLESv1(getModuleAddress(dependencies[2]));
    }

    /// @inheritdoc Policy
    function requestPermissions()
        external
        view
        override
        returns (Permissions[] memory permissions)
    {
        Keycode mintrKeycode = MINTR.KEYCODE();

        permissions = new Permissions[](5);
        permissions[0] = Permissions(mintrKeycode, MINTR.mintOhm.selector);
        permissions[1] = Permissions(mintrKeycode, MINTR.burnOhm.selector);
        permissions[2] = Permissions(mintrKeycode, MINTR.increaseMintApproval.selector);
    }

    //============================================================================================//
    //                                           MODIFIERS                                        //
    //============================================================================================//

    modifier onlyWhileActive() {
        if (!isLidoBLVaultActive) revert BLManagerLido_Inactive();
        _;
    }

    modifier onlyVault() {
        if (vaultOwners[BLVaultLido(msg.sender)] == address(0)) revert BLManagerLido_InvalidVault();
        _;
    }

    //============================================================================================//
    //                                        VAULT DEPLOYMENT                                    //
    //============================================================================================//

    /// @inheritdoc IBLVaultManagerLido
    function deployVault() external override onlyWhileActive returns (address vault) {
        if (address(userVaults[msg.sender]) != address(0))
            revert BLManagerLido_VaultAlreadyExists();

        // Create clone of vault implementation
        bytes memory data = abi.encodePacked(
            msg.sender, // Owner
            this, // Vault Manager
            address(TRSRY), // Treasury
            address(MINTR), // Minter
            ohm, // OHM
            pairToken, // Pair Token (wstETH)
            aura, // Aura
            bal, // Balancer
            balancerData.vault, // Balancer Vault
            balancerData.liquidityPool, // Balancer Pool
            auraData.pid, // Aura PID
            auraData.auraBooster, // Aura Booster
            auraData.auraRewardPool, // Aura Reward Pool
            currentFee
        );
        BLVaultLido clone = BLVaultLido(address(implementation).clone(data));

        // Initialize clone of vault implementation (for reentrancy state)
        clone.initializeClone();

        // Set vault owner
        vaultOwners[clone] = msg.sender;
        userVaults[msg.sender] = clone;

        // Emit event
        emit VaultDeployed(address(clone), msg.sender, currentFee);

        // Return vault address
        return address(clone);
    }

    //============================================================================================//
    //                                         OHM MANAGEMENT                                     //
    //============================================================================================//

    /// @inheritdoc IBLVaultManagerLido
    function mintOhmToVault(uint256 amount_) external override onlyWhileActive onlyVault {
        // Check that minting will not exceed limit
        if (deployedOhm + amount_ > ohmLimit + circulatingOhmBurned)
            revert BLManagerLido_LimitViolation();

        deployedOhm += amount_;

        // Mint OHM
        MINTR.increaseMintApproval(address(this), amount_);
        MINTR.mintOhm(msg.sender, amount_);
    }

    /// @inheritdoc IBLVaultManagerLido
    function burnOhmFromVault(uint256 amount_) external override onlyWhileActive onlyVault {
        // Account for how much OHM has been deployed by the Vault system or burned from circulating supply.
        // If we are burning more OHM than has been deployed by the system we are removing previously
        // circulating OHM which should be tracked separately.
        if (amount_ > deployedOhm) {
            circulatingOhmBurned += amount_ - deployedOhm;
            deployedOhm = 0;
        } else {
            deployedOhm -= amount_;
        }

        // Burn OHM
        MINTR.burnOhm(msg.sender, amount_);
    }

    //============================================================================================//
    //                                     VAULT STATE MANAGEMENT                                 //
    //============================================================================================//

    /// @inheritdoc IBLVaultManagerLido
    function increaseTotalLp(uint256 amount_) external override onlyWhileActive onlyVault {
        totalLp += amount_;
    }

    /// @inheritdoc IBLVaultManagerLido
    function decreaseTotalLp(uint256 amount_) external override onlyWhileActive onlyVault {
        if (amount_ > totalLp) revert BLManagerLido_InvalidLpAmount();
        totalLp -= amount_;
    }

    //============================================================================================//
    //                                         VIEW FUNCTIONS                                     //
    //============================================================================================//

    /// @inheritdoc IBLVaultManagerLido
    function getLpBalance(address user_) external view override returns (uint256) {
        return userVaults[user_].getLpBalance();
    }

    /// @inheritdoc IBLVaultManagerLido
    function getUserPairShare(address user_) external view override returns (uint256) {
        return userVaults[user_].getUserPairShare();
    }

    /// @inheritdoc IBLVaultManagerLido
    function getOutstandingRewards(
        address user_
    ) external view override returns (RewardsData[] memory) {
        // Get user's vault address
        BLVaultLido vault = userVaults[user_];

        RewardsData[] memory rewards = vault.getOutstandingRewards();
        return rewards;
    }

    /// @inheritdoc IBLVaultManagerLido
    function getMaxDeposit() external view override returns (uint256) {
        uint256 maxOhmAmount = ohmLimit - deployedOhm;

        // Convert max OHM mintable amount to pair token amount
        uint256 ohmTknPrice = getOhmTknPrice();
        uint256 maxTknAmount = (maxOhmAmount * 1e18) / ohmTknPrice;

        return maxTknAmount;
    }

    /// @inheritdoc IBLVaultManagerLido
    /// @dev    This is an external function but should only be used in a callstatic from an external
    ///         source like the frontend.
    function getExpectedLpAmount(uint256 amount_) external override returns (uint256 bptAmount) {
        IBasePool pool = IBasePool(balancerData.liquidityPool);
        IBalancerHelper balancerHelper = IBalancerHelper(balancerData.balancerHelper);

        // Calculate OHM amount to mint
        uint256 ohmTknPrice = getOhmTknPrice();
        uint256 ohmMintAmount = (amount_ * ohmTknPrice) / 1e18;

        // Build join pool request
        address[] memory assets = new address[](2);
        assets[0] = ohm;
        assets[1] = pairToken;

        uint256[] memory maxAmountsIn = new uint256[](2);
        maxAmountsIn[0] = ohmMintAmount;
        maxAmountsIn[1] = amount_;

        JoinPoolRequest memory joinPoolRequest = JoinPoolRequest({
            assets: assets,
            maxAmountsIn: maxAmountsIn,
            userData: abi.encode(1, maxAmountsIn, 0),
            fromInternalBalance: false
        });

        // Join pool query
        (bptAmount, ) = balancerHelper.queryJoin(
            pool.getPoolId(),
            address(this),
            address(this),
            joinPoolRequest
        );
    }

    /// @inheritdoc IBLVaultManagerLido
    function getRewardTokens() external view override returns (address[] memory) {
        IAuraRewardPool auraPool = IAuraRewardPool(auraData.auraRewardPool);

        uint256 numExtraRewards = auraPool.extraRewardsLength();
        address[] memory rewardTokens = new address[](numExtraRewards + 2);
        rewardTokens[0] = aura;
        rewardTokens[1] = auraPool.rewardToken();
        for (uint256 i; i < numExtraRewards; ) {
            IAuraRewardPool extraRewardPool = IAuraRewardPool(auraPool.extraRewards(i));
            rewardTokens[i + 2] = extraRewardPool.rewardToken();

            unchecked {
                ++i;
            }
        }
        return rewardTokens;
    }

    /// @inheritdoc IBLVaultManagerLido
    function getRewardRate(
        address rewardToken_
    ) external view override returns (uint256 rewardRate) {
        IAuraRewardPool auraPool = IAuraRewardPool(auraData.auraRewardPool);

        if (rewardToken_ == bal) {
            // If reward token is Bal, return rewardRate from Aura Pool
            rewardRate = auraPool.rewardRate();
        } else if (rewardToken_ == aura) {
            // If reward token is Aura, calculate rewardRate from AuraMiningLib
            uint256 balRewardRate = auraPool.rewardRate();
            rewardRate = auraMiningLib.convertCrvToCvx(balRewardRate);
        } else {
            uint256 numExtraRewards = auraPool.extraRewardsLength();
            for (uint256 i; i < numExtraRewards; ) {
                IAuraRewardPool extraRewardPool = IAuraRewardPool(auraPool.extraRewards(i));
                if (rewardToken_ == extraRewardPool.rewardToken()) {
                    rewardRate = extraRewardPool.rewardRate();
                    break;
                }

                unchecked {
                    ++i;
                }
            }
        }
    }

    /// @inheritdoc IBLVaultManagerLido
    function getPoolOhmShare() public view override returns (uint256) {
        // Cast addresses
        IVault vault = IVault(balancerData.vault);
        IBasePool pool = IBasePool(balancerData.liquidityPool);

        // Get pool total supply
        uint256 poolTotalSupply = pool.totalSupply();

        // Get token balances in pool
        (, uint256[] memory balances_, ) = vault.getPoolTokens(pool.getPoolId());

        // Balancer pool tokens are sorted alphabetically by token address. In the case of this
        // deployment, OHM is the first token in the pool. Therefore, the OHM balance is at index 0.
        if (poolTotalSupply == 0) return 0;
        else return (balances_[0] * totalLp) / poolTotalSupply;
    }

    /// @inheritdoc IBLVaultManagerLido
    function getOhmSupplyChangeData()
        external
        view
        override
        returns (uint256 poolOhmShare, uint256 deployedOhm, uint256 circulatingOhmBurned)
    {
        // Net emitted is the amount of OHM that was minted to the pool but is no longer in the
        // pool beyond what has been burned in the past. Net removed is the amount of OHM that is
        // in the pool but wasn’t minted there plus what has been burned in the past. Here we just return
        // the data components to calculate that.

        uint256 currentPoolOhmShare = getPoolOhmShare();
        return (currentPoolOhmShare, deployedOhm, circulatingOhmBurned);
    }

    /// @inheritdoc IBLVaultManagerLido
    function getOhmTknPrice() public view override returns (uint256) {
        // Get stETH per wstETH (18 Decimals)
        uint256 stethPerWsteth = IWsteth(pairToken).stEthPerToken();

        // Get ETH per OHM (18 Decimals)
        uint256 ethPerOhm = _validatePrice(ohmEthPriceFeed.feed, ohmEthPriceFeed.updateThreshold);

        // Get stETH per ETH (18 Decimals)
        uint256 stethPerEth = _validatePrice(
            stethEthPriceFeed.feed,
            stethEthPriceFeed.updateThreshold
        );

        // Calculate OHM per wstETH (9 decimals)
        return (stethPerWsteth * stethPerEth) / (ethPerOhm * 1e9);
    }

    /// @inheritdoc IBLVaultManagerLido
    function getTknOhmPrice() public view override returns (uint256) {
        // Get stETH per wstETH (18 Decimals)
        uint256 stethPerWsteth = IWsteth(pairToken).stEthPerToken();

        // Get ETH per OHM (18 Decimals)
        uint256 ethPerOhm = _validatePrice(ohmEthPriceFeed.feed, ohmEthPriceFeed.updateThreshold);

        // Get stETH per ETH (18 Decimals)
        uint256 stethPerEth = _validatePrice(
            stethEthPriceFeed.feed,
            stethEthPriceFeed.updateThreshold
        );

        // Calculate wstETH per OHM (18 decimals)
        return (ethPerOhm * 1e36) / (stethPerWsteth * stethPerEth);
    }

    //============================================================================================//
    //                                        ADMIN FUNCTIONS                                     //
    //============================================================================================//

    /// @inheritdoc IBLVaultManagerLido
    function setLimit(uint256 newLimit_) external override onlyRole("liquidityvault_admin") {
        if (newLimit_ < deployedOhm) revert BLManagerLido_InvalidLimit();
        ohmLimit = newLimit_;
    }

    /// @inheritdoc IBLVaultManagerLido
    function setFee(uint64 newFee_) external override onlyRole("liquidityvault_admin") {
        if (newFee_ > MAX_FEE) revert BLManagerLido_InvalidFee();
        currentFee = newFee_;
    }

    /// @inheritdoc IBLVaultManagerLido
    function changeUpdateThresholds(
        uint48 ohmEthUpdateThreshold_,
        uint48 stethEthUpdateThreshold_
    ) external onlyRole("liquidityvault_admin") {
        ohmEthPriceFeed.updateThreshold = ohmEthUpdateThreshold_;
        stethEthPriceFeed.updateThreshold = stethEthUpdateThreshold_;
    }

    /// @inheritdoc IBLVaultManagerLido
    function activate() external override onlyRole("liquidityvault_admin") {
        isLidoBLVaultActive = true;
    }

    /// @inheritdoc IBLVaultManagerLido
    function deactivate() external override onlyRole("liquidityvault_admin") {
        isLidoBLVaultActive = false;
    }

    //============================================================================================//
    //                                      INTERNAL FUNCTIONS                                    //
    //============================================================================================//

    function _validatePrice(
        AggregatorV3Interface priceFeed_,
        uint48 updateThreshold_
    ) internal view returns (uint256) {
        // Get price data
        (uint80 roundId, int256 priceInt, , uint256 updatedAt, uint80 answeredInRound) = priceFeed_
            .latestRoundData();

        // Validate chainlink price feed data
        // 1. Price should be greater than 0
        // 2. Updated at timestamp should be within the update threshold
        // 3. Answered in round ID should be the same as round ID
        if (
            priceInt <= 0 ||
            updatedAt < block.timestamp - updateThreshold_ ||
            answeredInRound != roundId
        ) revert BLManagerLido_BadPriceFeed();

        return uint256(priceInt);
    }
}
