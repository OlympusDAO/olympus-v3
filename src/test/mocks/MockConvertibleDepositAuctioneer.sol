// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(screaming-snake-case-immutable)
// solhint-disable custom-errors
// solhint-disable immutable-vars-naming
pragma solidity >=0.8.15;

import {Kernel, Policy, Keycode, toKeycode, Permissions} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/OlympusRoles.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";
import {IConvertibleDepositAuctioneer} from "src/policies/interfaces/deposits/IConvertibleDepositAuctioneer.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {ERC721} from "@openzeppelin-4.8.0/token/ERC721/ERC721.sol";

contract MockConvertibleDepositAuctioneer is IConvertibleDepositAuctioneer, Policy, PolicyEnabler {
    uint48 internal _initTimestamp;
    int256[] internal _auctionResults;

    IERC20 internal immutable _depositAsset;

    uint256 public target;
    uint256 public tickSize;
    uint256 public minPrice;
    uint256 public tickSizeBase;
    uint256 public minimumBid;

    // Additional state for testing
    uint256 public mockPrice = 30e18; // 30 USDS per OHM
    mapping(uint8 => bool) public depositPeriodsEnabled;
    uint8[] public enabledPeriods;

    uint256 internal constant OHM_SCALE = 1e9;

    // Receipt tokens and position NFT (assumed to be non-zero)
    mapping(uint8 => address) public receiptTokens; // period => receipt token address
    address public positionNFT;
    uint256 public nextPositionId = 1;

    constructor(Kernel kernel_, address depositAsset_) Policy(kernel_) {
        _depositAsset = IERC20(depositAsset_);
    }

    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("ROLES");

        ROLES = ROLESv1(getModuleAddress(dependencies[0]));

        return dependencies;
    }

    function requestPermissions()
        external
        view
        override
        returns (Permissions[] memory permissions)
    {}

    function bid(
        uint8 depositPeriod_,
        uint256 depositAmount_,
        uint256 minOhmOut_,
        bool,
        bool
    )
        external
        override
        returns (uint256 ohmOut, uint256 positionId, uint256 receiptTokenId, uint256 actualAmount)
    {
        // Transfer deposit asset from caller (assumed to be non-zero)
        IERC20(_depositAsset).transferFrom(msg.sender, address(this), depositAmount_);

        // Calculate OHM output
        ohmOut = (depositAmount_ * OHM_SCALE) / mockPrice;
        require(ohmOut >= minOhmOut_, "Slippage");

        // Mint receipt token (assumed to be configured for this period)
        address receiptTokenAddr = receiptTokens[depositPeriod_];
        receiptTokenId = depositPeriod_;
        // Call mint function on receipt token (assuming it has a mint(address, uint256) function)
        (bool success, ) = receiptTokenAddr.call(
            abi.encodeWithSignature("mint(address,uint256)", msg.sender, depositAmount_)
        );
        require(success, "Receipt token mint failed");

        // Mint position NFT (assumed to be non-zero)
        positionId = nextPositionId;
        ++nextPositionId;
        // Call mint function on position NFT (assuming it has a mint(address) function)
        (success, ) = positionNFT.call(abi.encodeWithSignature("mint(address)", address(this)));
        require(success, "Position NFT mint failed");
        // Transfer to caller
        ERC721(positionNFT).transferFrom(address(this), msg.sender, positionId);

        actualAmount = depositAmount_;

        return (ohmOut, positionId, receiptTokenId, actualAmount);
    }

    function previewBid(
        uint8,
        uint256 depositAmount_
    ) external view override returns (uint256 ohmOut) {
        if (depositAmount_ < minimumBid) return 0;
        ohmOut = (depositAmount_ * OHM_SCALE) / mockPrice;
        return ohmOut;
    }

    function getPreviousTick(uint8) external view override returns (Tick memory tick) {
        tick = Tick({price: mockPrice, capacity: 1000000e18, lastUpdate: uint48(block.timestamp)});
    }

    function getCurrentTick(uint8) external view override returns (Tick memory tick) {
        tick = Tick({price: mockPrice, capacity: 1000000e18, lastUpdate: uint48(block.timestamp)});
    }

    function getCurrentTickSize() external view override returns (uint256) {
        return tickSize;
    }

    function getAuctionParameters()
        external
        view
        override
        returns (AuctionParameters memory auctionParameters)
    {
        auctionParameters = AuctionParameters({
            target: target,
            tickSize: tickSize,
            minPrice: minPrice
        });
    }

    function isAuctionActive() external view override returns (bool) {
        return target > 0;
    }

    function getDayState() external view override returns (Day memory day) {}

    function setAuctionParameters(
        uint256 newTarget,
        uint256 newSize,
        uint256 newMinPrice
    ) external override {
        // Mimic behaviour of the real auctioneer with error handling
        // Tick size must be non-zero when target is non-zero
        if (newTarget > 0 && newSize == 0) revert("tick size zero");

        // Min price must be non-zero when target is non-zero (can be zero when auction is disabled)
        if (newTarget > 0 && newMinPrice == 0) revert("min price zero");

        target = newTarget;
        tickSize = newSize;
        minPrice = newMinPrice;
    }

    function setAuctionResults(int256[] memory results) external {
        _auctionResults = results;
    }

    function setTickStep(uint24 newStep) external override {}

    function getTickStep() external view override returns (uint24) {}

    function getAuctionTrackingPeriod() external view override returns (uint8) {}

    function getAuctionResults() external view override returns (int256[] memory) {
        return _auctionResults;
    }

    function getAuctionResultsNextIndex() external view override returns (uint8) {}

    function setAuctionTrackingPeriod(uint8 newPeriod) external override {}

    function enableDepositPeriod(uint8 depositPeriod_) external override {}

    function disableDepositPeriod(uint8 depositPeriod_) external override {}

    function getDepositAsset() external view override returns (IERC20) {
        return _depositAsset;
    }

    function getDepositPeriods() external view override returns (uint8[] memory) {
        return enabledPeriods;
    }

    function isDepositPeriodEnabled(
        uint8 depositPeriod_
    ) external view override returns (bool, bool) {
        bool enabled = depositPeriodsEnabled[depositPeriod_];
        return (enabled, enabled);
    }

    function getDepositPeriodsCount() external view override returns (uint256) {
        return enabledPeriods.length;
    }

    function getMinimumBid() external view override returns (uint256) {
        return minimumBid;
    }

    function setMinimumBid(uint256 newMinimumBid) external override {
        minimumBid = newMinimumBid;
    }

    function getTickSizeBase() external view override returns (uint256) {
        return tickSizeBase;
    }

    function setTickSizeBase(uint256 newBase) external override {
        tickSizeBase = newBase;
    }

    // ========== TEST HELPERS ========== //

    /// @notice Set the mock price for testing
    function setMockPrice(uint256 price_) external {
        mockPrice = price_;
    }

    /// @notice Set deposit period enabled state for a specific period
    function setDepositPeriodEnabled(uint8 period_, bool enabled_) external {
        depositPeriodsEnabled[period_] = enabled_;

        // Update enabledPeriods array
        bool found = false;
        for (uint256 i = 0; i < enabledPeriods.length; i++) {
            if (enabledPeriods[i] == period_) {
                found = true;
                if (!enabled_) {
                    // Remove from array
                    enabledPeriods[i] = enabledPeriods[enabledPeriods.length - 1];
                    enabledPeriods.pop();
                }
                break;
            }
        }
        if (enabled_ && !found) {
            enabledPeriods.push(period_);
        }
    }

    /// @notice Set receipt token for a specific period
    function setReceiptToken(uint8 period_, address receiptToken_) external {
        receiptTokens[period_] = receiptToken_;
    }

    /// @notice Set position NFT for testing
    function setPositionNFT(address positionNFT_) external {
        positionNFT = positionNFT_;
    }
}
/// forge-lint: disable-end(screaming-snake-case-immutable)
