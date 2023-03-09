// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

// Import system dependencies
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {ROLESv1, RolesConsumer} from "src/modules/ROLES/OlympusRoles.sol";
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";
import "src/Kernel.sol";

// Import external dependencies
import {IAuraRewardPool, IAuraMiningLib} from "policies/lending/interfaces/IAura.sol";

// Import vault dependencies
import {BLEVaultLido} from "policies/lending/BLEVaultLido.sol";

// Import libraries
import {ClonesWithImmutableArgs} from "clones/ClonesWithImmutableArgs.sol";

contract BLEVaultManagerLido is Policy, RolesConsumer {
    using ClonesWithImmutableArgs for address;

    // ========= ERRORS ========= //

    error BLEFactoryLido_Inactive();
    error BLEFactoryLido_InvalidVault();
    error BLEFactoryLido_LimitViolation();
    error BLEFactoryLido_InvalidLimit();
    error BLEFactoryLido_InvalidFee();

    // ========= EVENTS ========= //

    event VaultDeployed(address vault, address owner, uint32 fee);

    // ========= STATE VARIABLES ========= //

    // Modules
    MINTRv1 public MINTR;
    TRSRYv1 public TRSRY;

    // Tokens
    address public aura;
    address public bal;

    // Exchange Info
    string public exchangeName;

    // Aura Info
    IAuraPool public auraPool;
    IAuraMiningLib public auraMiningLib;

    // Vault Info
    BLEVaultLido public implementation;
    mapping(BLEVaultLido => address) public vaultOwners;

    // System State
    uint256 public ohmLimit;
    uint256 public mintedOHM;
    uint256 public netBurnedOHM;
    uint32 public currentFee;
    bool public isActive;

    // Constants
    uint32 public constant MAX_FEE = 10000; // 100%

    //============================================================================================//
    //                                      POLICY SETUP                                          //
    //============================================================================================//

    constructor(
        Kernel kernel_,
        address aura_,
        address bal_,
        address auraPool_,
        uint256 ohmLimit_
    ) Policy(kernel_) {
        // Set exchange name
        exchangeName = "Balancer";

        // Set tokens
        aura = aura_;
        bal = bal_;

        // Set Aura Pool
        auraPool = IAuraPool(auraPool_);

        // Set OHM Limit
        ohmLimit = ohmLimit_;
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
        if (!isActive) revert BLEFactoryLido_Inactive();
        _;
    }

    modifier onlyVault() {
        if (vaultOwners[BLEVaultLido(msg.sender)] == address(0))
            revert BLEFactoryLido_InvalidVault();
        _;
    }

    //============================================================================================//
    //                                        VAULT DEPLOYMENT                                    //
    //============================================================================================//

    function deployVault() external onlyWhileActive returns (address vault) {
        // Create clone of vault implementation
        bytes memory data = abi.encodePacked(msg.sender, this, currentFee);
        BLEVaultLido clone = BLEVaultLido(address(implementation).clone(data));

        // Set vault owner
        vaultOwners[clone] = msg.sender;

        // Emit event
        emit VaultDeployed(address(clone), msg.sender, currentFee);

        // Return vault address
        return address(clone);
    }

    //============================================================================================//
    //                                         OHM MANAGEMENT                                     //
    //============================================================================================//

    function mintOHM(uint256 amount_) external onlyWhileActive onlyVault {
        // Check that minting will not exceed limit
        if (mintedOHM + amount_ > ohmLimit) revert BLEFactoryLido_LimitViolation();

        mintedOHM += amount_;

        // Mint OHM
        MINTR.increaseMintApproval(address(this), amount_);
        MINTR.mintOhm(msg.sender, amount_);
    }

    function burnOHM(uint256 amount_) external onlyWhileActive onlyVault {
        // Handle accounting
        if (amount_ > mintedOHM) {
            netBurnedOHM += amount_ - mintedOHM;
            mintedOHM = 0;
        } else {
            mintedOHM -= amount_;
        }

        // Burn OHM
        MINTR.burnOhm(msg.sender, amount_);
    }

    //============================================================================================//
    //                                         VIEW FUNCTIONS                                     //
    //============================================================================================//

    function getRewardRate(address rewardToken_) external view returns (uint256 rewardRate) {
        if (rewardToken_ == bal) {
            // If reward token is Bal, return rewardRate from Aura Pool
            rewardRate = auraPool.rewardRate();
        } else if (rewardToken_ == aura) {
            // If reward token is Aura, calculate rewardRate from AuraMiningLib
            uint256 balRewardRate = auraPool.rewardRate();
            rewardRate = auraMiningLib.convertCrvToCvx(balRewardRate);
        } else {
            uint256 numExtraRewards = auraPool.rewardsPool.extraRewardsLength();
            for (uint256 i = 0; i < numExtraRewards; i++) {
                IAuraRewardPool extraRewardPool = IAuraRewardPool(
                    auraPool.rewardsPool.extraRewards(i)
                );
                if (rewardToken_ == extraRewardPool.rewardToken()) {
                    rewardRate = extraRewardPool.rewardRate();
                    break;
                }
            }
        }
    }

    //============================================================================================//
    //                                        ADMIN FUNCTIONS                                     //
    //============================================================================================//

    function setLimit(uint256 newLimit_) external onlyRole("liquidityvault_admin") {
        if (newLimit_ < mintedOHM) revert BLEFactoryLido_InvalidLimit();
        ohmLimit = newLimit_;
    }

    function setFee(uint32 newFee_) external onlyRole("liquidityvault_admin") {
        if (newFee_ > MAX_FEE) revert BLEFactoryLido_InvalidFee();
        currentFee = newFee_;
    }

    function activate() external onlyRole("liquidityvault_admin") {
        isActive = true;
    }

    function deactivate() external onlyRole("liquidityvault_admin") {
        isActive = false;
    }
}
