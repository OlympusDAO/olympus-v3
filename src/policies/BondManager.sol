// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

// Import external dependencies
import {ERC20} from "solmate/tokens/ERC20.sol";
import {OlympusERC20Token} from "src/external/OlympusERC20.sol";

// Import internal dependencies
import "src/Kernel.sol";
import {MINTRv1} from "modules/MINTR/MINTR.v1.sol";
import {TRSRYv1} from "modules/TRSRY/TRSRY.v1.sol";
import {ROLESv1} from "modules/ROLES/ROLES.v1.sol";
import {RolesConsumer} from "modules/ROLES/OlympusRoles.sol";

// Import interfaces
import {IBondAuctioneer} from "interfaces/IBondAuctioneer.sol";
import {IBondCallback} from "interfaces/IBondCallback.sol";
import {IBondTeller} from "interfaces/IBondTeller.sol";
import {IEasyAuction} from "interfaces/IEasyAuction.sol";

/// @title Olympus Bond Manager
/// @notice Olympus Bond Manager (Policy) Contract
contract BondManager is Policy, RolesConsumer {
    // ========= EVENTS ========= //

    event BondProtocolMarketLaunched(uint256 marketId, uint256 capacity, uint256 bondTerm);
    event GnosisAuctionLaunched(uint256 marketId, uint96 capacity, uint256 bondTerm);

    // ========= DATA STRUCTURES ========= //

    struct BondProtocolParameters {
        uint256 initialPrice;
        uint256 minPrice;
        uint32 debtBuffer;
        uint256 auctionTime;
        uint32 depositInterval;
    }

    struct GnosisAuctionParameters {
        uint256 auctionCancelTime;
        uint256 auctionTime;
        uint96 minRatioSold;
        uint256 minBuyAmount;
        uint256 minFundingThreshold;
    }

    // ========= STATE ========= //

    // Modules
    MINTRv1 public MINTR;
    TRSRYv1 public TRSRY;

    // Policies
    IBondCallback public bondCallback;

    // External Contracts
    IBondAuctioneer public fixedExpiryAuctioneer;
    IBondTeller public fixedExpiryTeller;
    IEasyAuction public gnosisEasyAuction;

    // Tokens
    OlympusERC20Token public ohm;

    // Market Parameters
    BondProtocolParameters public bondProtocolParameters;
    GnosisAuctionParameters public gnosisAuctionParameters;

    //============================================================================================//
    //                                      POLICY SETUP                                          //
    //============================================================================================//

    constructor(
        Kernel kernel_,
        address fixedExpiryAuctioneer_,
        address fixedExpiryTeller_,
        address gnosisEasyAuction_,
        address ohm_
    ) Policy(kernel_) {
        fixedExpiryAuctioneer = IBondAuctioneer(fixedExpiryAuctioneer_);
        fixedExpiryTeller = IBondTeller(fixedExpiryTeller_);
        gnosisEasyAuction = IEasyAuction(gnosisEasyAuction_);
        ohm = OlympusERC20Token(ohm_);
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
    function requestPermissions() external view override returns (Permissions[] memory requests) {
        Keycode MINTR_KEYCODE = MINTR.KEYCODE();

        requests = new Permissions[](2);
        requests[0] = Permissions(MINTR_KEYCODE, MINTR.mintOhm.selector);
        requests[1] = Permissions(MINTR_KEYCODE, MINTR.burnOhm.selector);
    }

    //============================================================================================//
    //                                       CORE FUNCTIONS                                       //
    //============================================================================================//

    function createBondProtocolMarket(uint256 capacity_, uint256 bondTerm_)
        external
        onlyRole("bondmanager_admin")
        returns (uint256 marketId)
    {
        // Encodes the information needed for creating a bond market on Bond Protocol
        bytes memory createMarketParams = abi.encode(
            ERC20(address(ohm)), // payoutToken
            ERC20(address(ohm)), // quoteToken
            address(bondCallback), // callbackAddress
            false, // capacityInQuote
            capacity_, // capacity
            bondProtocolParameters.initialPrice, // formattedInitialPrice
            bondProtocolParameters.minPrice, // formattedMinimumPrice
            bondProtocolParameters.debtBuffer, // debtBuffer
            uint48(block.timestamp + bondTerm_), // vesting
            uint48(block.timestamp + bondProtocolParameters.auctionTime), // conclusion
            bondProtocolParameters.depositInterval, // depositInterval
            int8(0)
        );

        marketId = fixedExpiryAuctioneer.createMarket(createMarketParams);
        bondCallback.whitelist(address(fixedExpiryTeller), marketId);

        emit BondProtocolMarketLaunched(marketId, capacity_, bondTerm_);
    }

    function createGnosisAuction(uint96 capacity_, uint256 bondTerm_)
        external
        onlyRole("bondmanager_admin")
        returns (uint256 auctionId)
    {
        MINTR.mintOhm(address(this), capacity_);

        uint48 expiry = uint48(block.timestamp + bondTerm_);

        // Create bond token
        ohm.increaseAllowance(address(fixedExpiryTeller), capacity_);
        fixedExpiryTeller.deploy(ERC20(address(ohm)), expiry);
        (ERC20 bondToken, ) = fixedExpiryTeller.create(ERC20(address(ohm)), expiry, capacity_);

        // Launch Gnosis Auction
        bondToken.approve(address(gnosisEasyAuction), capacity_);
        auctionId = gnosisEasyAuction.initiateAuction(
            bondToken, // auctioningToken
            ERC20(address(ohm)), // biddingToken
            block.timestamp + gnosisAuctionParameters.auctionCancelTime, // last order cancellation time
            block.timestamp + gnosisAuctionParameters.auctionTime, // auction end time
            capacity_, // auctioned amount of bondToken
            capacity_ / gnosisAuctionParameters.minRatioSold, // minimum tokens bought for auction to be valid
            gnosisAuctionParameters.minBuyAmount, // minimum purchase size of auctioning token
            gnosisAuctionParameters.minFundingThreshold, // minimum funding threshold
            false, // is atomic closure allowed
            address(0), // access manager contract
            new bytes(0) // access manager contract data
        );

        emit GnosisAuctionLaunched(auctionId, capacity_, bondTerm_);
    }

    function closeBondProtocolMarket(uint256 marketId_) external onlyRole("bondmanager_admin") {
        fixedExpiryAuctioneer.closeMarket(marketId_);
    }

    function settleGnosisAuction(uint256 auctionId_) external onlyRole("bondmanager_admin") {
        gnosisEasyAuction.settleAuction(auctionId_);
    }

    //============================================================================================//
    //                                      ADMIN FUNCTIONS                                       //
    //============================================================================================//

    function setBondProtocolParameters(
        uint256 initialPrice_,
        uint256 minPrice_,
        uint32 debtBuffer_,
        uint256 auctionTime_,
        uint32 depositInterval_
    ) external onlyRole("bondmanager_admin") {
        bondProtocolParameters = BondProtocolParameters({
            initialPrice: initialPrice_,
            minPrice: minPrice_,
            debtBuffer: debtBuffer_,
            auctionTime: auctionTime_,
            depositInterval: depositInterval_
        });
    }

    function setGnosisAuctionParameters(
        uint256 auctionCancelTime_,
        uint256 auctionTime_,
        uint96 minRatioSold_,
        uint256 minBuyAmount_,
        uint256 minFundingThreshold_
    ) external onlyRole("bondmanager_admin") {
        gnosisAuctionParameters = GnosisAuctionParameters({
            auctionCancelTime: auctionCancelTime_,
            auctionTime: auctionTime_,
            minRatioSold: minRatioSold_,
            minBuyAmount: minBuyAmount_,
            minFundingThreshold: minFundingThreshold_
        });
    }

    function setCallback(IBondCallback newCallback_) external onlyRole("bondmanager_admin") {
        bondCallback = newCallback_;
    }

    //============================================================================================//
    //                                   EMERGENCY FUNCTIONS                                      //
    //============================================================================================//

    function emergencyShutdownBondProtocolMarket(uint256 marketId_)
        external
        onlyRole("bondmanager_admin")
    {
        bondCallback.blacklist(address(fixedExpiryTeller), marketId_);
        fixedExpiryAuctioneer.closeMarket(marketId_);
    }

    function emergencySetApproval(address contract_, uint256 amount_)
        external
        onlyRole("bondmanager_admin")
    {
        ohm.increaseAllowance(contract_, amount_);
    }

    function emergencyWithdraw(uint256 amount_) external onlyRole("bondmanager_admin") {
        ohm.transfer(address(TRSRY), amount_);
    }
}
