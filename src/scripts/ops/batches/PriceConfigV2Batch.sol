// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {AggregatorV2V3Interface} from "src/interfaces/AggregatorV2V3Interface.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IPriceConfigv2} from "src/policies/interfaces/IPriceConfigv2.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";
import {toSubKeycode} from "src/Submodules.sol";

// Contracts
import {console2} from "@forge-std-1.16.2/console2.sol";
import {ChainlinkPriceFeeds} from "src/modules/PRICE/submodules/feeds/ChainlinkPriceFeeds.sol";
import {PriceConfigv2} from "src/policies/price/PriceConfig.v2.sol";
import {TimelockBatchScript} from "src/scripts/ops/lib/TimelockBatchScript.sol";

/// @notice Add, update and remove PRICE assets through the existing PriceConfigv2 policy.
/// @dev Updates and removals use the policy's delayed queue.
contract PriceConfigV2Batch is TimelockBatchScript {
    using SafeCast for uint256;

    /// @notice Admit the asset and single-feed parameters supplied in the args file.
    function addAsset(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        console2.log("PriceConfigV2Batch: addAsset");
        PriceConfigv2 config = PriceConfigv2(
            _envAddressNotZero("olympus.policies.OlympusPriceConfigV2")
        );
        address asset = _readBatchArgAddress("addAsset", "asset");
        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](1);
        feeds[0] = IPRICEv2.Component({
            target: toSubKeycode("PRICE.CHAINLINK"),
            selector: ChainlinkPriceFeeds.getOneFeedPrice.selector,
            params: abi.encode(
                ChainlinkPriceFeeds.OneFeedParams({
                    feed: AggregatorV2V3Interface(_readBatchArgAddress("addAsset", "feed")),
                    updateThreshold: _readBatchArgUint256("addAsset", "maximumAge").toUint48()
                })
            )
        });
        IPRICEv2.Component memory strategy = IPRICEv2.Component({
            target: toSubKeycode(bytes20(0)),
            selector: bytes4(0),
            params: new bytes(0)
        });
        IPriceConfigv2.PriceFeedExpectation[]
            memory expectations = new IPriceConfigv2.PriceFeedExpectation[](1);
        expectations[0] = IPriceConfigv2.PriceFeedExpectation({
            expectedPrice: _readBatchArgUint256("addAsset", "expectedPrice"),
            toleranceBps: _readBatchArgUint256("addAsset", "toleranceBps").toUint16()
        });
        addToBatch(
            address(config),
            abi.encodeCall(
                IPriceConfigv2.addAsset,
                (asset, false, false, 0, 0, new uint256[](0), strategy, feeds, expectations)
            )
        );
        proposeBatch();
    }

    /// @notice Queue a complete update with typed params and matching feed expectations.
    function queueUpdateAsset(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        console2.log("PriceConfigV2Batch: queueUpdateAsset");
        (
            IPRICEv2.UpdateAssetParams memory params,
            IPriceConfigv2.PriceFeedExpectation[] memory expectations
        ) = abi.decode(
                vm.parseBytes(_readBatchArgString("queueUpdateAsset", "encodedUpdate")),
                (IPRICEv2.UpdateAssetParams, IPriceConfigv2.PriceFeedExpectation[])
            );
        addToBatch(
            _envAddressNotZero("olympus.policies.OlympusPriceConfigV2"),
            abi.encodeCall(
                IPriceConfigv2.queueUpdateAsset,
                (_readBatchArgAddress("queueUpdateAsset", "asset"), params, expectations)
            )
        );
        proposeBatch();
    }

    function queueRemoveAsset(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        console2.log("PriceConfigV2Batch: queueRemoveAsset");
        addToBatch(
            _envAddressNotZero("olympus.policies.OlympusPriceConfigV2"),
            abi.encodeCall(
                IPriceConfigv2.queueRemoveAsset,
                (_readBatchArgAddress("queueRemoveAsset", "asset"))
            )
        );
        proposeBatch();
    }

    function _timelockKey() internal pure override returns (string memory) {
        return "olympus.policies.OlympusPriceConfigV2";
    }

    /// @notice Cancel a PriceConfigV2 action through the Emergency multisig.
    /// @dev PriceConfigV2 requires EMERGENCY to cancel, including for actions the DAO proposed.
    ///      Keep the original entry point and args key on the Emergency Safe.
    function cancelQueuedAction(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external override setUpWithEmergencyMS(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        _cancelQueuedAction("cancelQueuedAction");
    }
}
