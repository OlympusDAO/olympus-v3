// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {AggregatorV2V3Interface} from "src/interfaces/AggregatorV2V3Interface.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {ITimelockQueue} from "src/policies/interfaces/utils/ITimelockQueue.sol";
import {IPriceConfigv2} from "src/policies/interfaces/IPriceConfigv2.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";
import {toSubKeycode} from "src/Submodules.sol";

// Contracts
import {ChainlinkPriceFeeds} from "src/modules/PRICE/submodules/feeds/ChainlinkPriceFeeds.sol";
import {PriceConfigv2} from "src/policies/price/PriceConfig.v2.sol";
import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";

/// @notice Add, update and remove PRICE assets through the existing PriceConfigv2 policy.
/// @dev Updates and removals use the policy's delayed queue.
contract PriceConfigV2Batch is BatchScriptV2 {
    using SafeCast for uint256;

    /// @notice Admit the asset and single-feed parameters supplied in the args file.
    function addAsset(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        PriceConfigv2 config = PriceConfigv2(
            _envAddressNotZero("olympus.policies.OlympusPriceConfigV2")
        );
        address asset = _readBatchArgAddress("addAsset", "asset");
        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](1);
        feeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getOneFeedPrice.selector,
            abi.encode(
                ChainlinkPriceFeeds.OneFeedParams(
                    AggregatorV2V3Interface(_readBatchArgAddress("addAsset", "feed")),
                    _readBatchArgUint256("addAsset", "maximumAge").toUint48()
                )
            )
        );
        IPRICEv2.Component memory strategy;
        IPriceConfigv2.PriceFeedExpectation[]
            memory expectations = new IPriceConfigv2.PriceFeedExpectation[](1);
        expectations[0] = IPriceConfigv2.PriceFeedExpectation(
            _readBatchArgUint256("addAsset", "expectedPrice"),
            _readBatchArgUint256("addAsset", "toleranceBps").toUint16()
        );
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
        addToBatch(
            _envAddressNotZero("olympus.policies.OlympusPriceConfigV2"),
            abi.encodeCall(
                IPriceConfigv2.queueRemoveAsset,
                (_readBatchArgAddress("queueRemoveAsset", "asset"))
            )
        );
        proposeBatch();
    }

    function executeQueuedAction(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        addToBatch(
            _envAddressNotZero("olympus.policies.OlympusPriceConfigV2"),
            abi.encodeCall(
                ITimelockQueue.executeQueuedAction,
                (SafeCast.toUint64(_readBatchArgUint256("executeQueuedAction", "actionId")))
            )
        );
        proposeBatch();
    }

    function cancelQueuedAction(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUpWithEmergencyMS(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        addToBatch(
            _envAddressNotZero("olympus.policies.OlympusPriceConfigV2"),
            abi.encodeCall(
                ITimelockQueue.cancelQueuedAction,
                (SafeCast.toUint64(_readBatchArgUint256("cancelQueuedAction", "actionId")))
            )
        );
        proposeBatch();
    }
}
