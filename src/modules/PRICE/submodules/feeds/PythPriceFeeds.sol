// SPDX-License-Identifier: AGPL-3.0
/// forge-lint: disable-start(mixed-case-function)
pragma solidity >=0.8.15;

// Interfaces
import {IPyth} from "src/interfaces/IPyth.sol";

// Libraries
import {FullMath} from "src/libraries/FullMath.sol";
import {SafeCast} from "src/libraries/SafeCast.sol";

// Bophades
import {Module} from "src/Kernel.sol";
import {PriceSubmodule} from "modules/PRICE/PRICE.v2.sol";
import {Submodule, SubKeycode, toSubKeycode} from "src/Submodules.sol";

/// @title      PythPriceFeeds
/// @author     0xJem
/// @notice     Provides prices derived from Pyth Network price feed(s)
contract PythPriceFeeds is PriceSubmodule {
    using FullMath for uint256;

    uint256 internal constant _PRICE_DATA_SIZE = 128;

    /// @notice                 Parameters for a single Pyth price feed
    ///
    /// @param pyth             Address of the Pyth contract
    /// @param priceFeedId      The Pyth price feed ID
    /// @param updateThreshold  The maximum number of seconds elapsed since the last price feed update
    /// @param maxConfidence    The maximum confidence interval allowed (in output decimals scale)
    struct OneFeedParams {
        address pyth;
        bytes32 priceFeedId;
        uint48 updateThreshold;
        uint256 maxConfidence;
    }

    /// @notice                         Parameters for two Pyth price feeds
    ///
    /// @param firstPyth                First: Address of the Pyth contract
    /// @param firstPriceFeedId         First: The Pyth price feed ID
    /// @param firstUpdateThreshold     First: The maximum number of seconds elapsed since the last price feed update
    /// @param firstMaxConfidence       First: The maximum confidence interval allowed (in output decimals scale)
    /// @param secondPyth               Second: Address of the Pyth contract
    /// @param secondPriceFeedId        Second: The Pyth price feed ID
    /// @param secondUpdateThreshold    Second: The maximum number of seconds elapsed since the last price feed update
    /// @param secondMaxConfidence      Second: The maximum confidence interval allowed (in output decimals scale)
    struct TwoFeedParams {
        address firstPyth;
        bytes32 firstPriceFeedId;
        uint48 firstUpdateThreshold;
        uint256 firstMaxConfidence;
        address secondPyth;
        bytes32 secondPriceFeedId;
        uint48 secondUpdateThreshold;
        uint256 secondMaxConfidence;
    }

    // ========== ERRORS ========== //

    /// @notice                 A Pyth contract address specified in the parameters is invalid
    ///
    /// @param paramsIndex_     The index of the parameter
    /// @param feed_            The address of the Pyth contract
    error Pyth_ParamsPythInvalid(uint8 paramsIndex_, address feed_);

    /// @notice                 A price feed ID specified in the parameters is invalid
    ///
    /// @param paramsIndex_     The index of the parameter
    /// @param priceFeedId_     The price feed ID
    error Pyth_ParamsPriceFeedIdInvalid(uint8 paramsIndex_, bytes32 priceFeedId_);

    /// @notice                 An update threshold specified in the parameters is invalid
    /// @dev                    This currently occurs if the update threshold is 0
    ///
    /// @param paramsIndex_     The index of the parameter
    /// @param updateThreshold_ The update threshold
    error Pyth_ParamsUpdateThresholdInvalid(uint8 paramsIndex_, uint48 updateThreshold_);

    /// @notice                 A maximum confidence specified in the parameters is invalid
    /// @dev                    This currently occurs if the maximum confidence is 0
    ///
    /// @param paramsIndex_     The index of the parameter
    /// @param maxConfidence_   The maximum confidence (in output decimals scale)
    error Pyth_ParamsMaxConfidenceInvalid(uint8 paramsIndex_, uint256 maxConfidence_);

    /// @notice                 The price feed is invalid
    /// @dev                    This is triggered if the Pyth contract call reverts,
    /// @dev                    and indicates that the feed address is not a valid Pyth contract.
    ///
    /// @param pyth_            The address of the Pyth contract
    /// @param priceFeedId_     The price feed ID
    error Pyth_FeedInvalid(address pyth_, bytes32 priceFeedId_);

    /// @notice                 The price returned by the price feed is invalid
    /// @dev                    This could be because:
    /// @dev                    - The price is <= 0
    ///
    /// @param pyth_            The address of the Pyth contract
    /// @param priceFeedId_     The price feed ID
    /// @param price_           The price returned by the price feed
    error Pyth_FeedPriceInvalid(address pyth_, bytes32 priceFeedId_, int64 price_);

    /// @notice                     The data returned by the price feed is stale
    /// @dev                        This could be because:
    /// @dev                        - The price feed was last updated before the update threshold
    ///
    /// @param pyth_                The address of the Pyth contract
    /// @param priceFeedId_         The price feed ID
    /// @param publishTime_         The publish time of the price feed
    /// @param thresholdTimestamp_  The earliest acceptable timestamp
    error Pyth_FeedPublishTimeStale(
        address pyth_,
        bytes32 priceFeedId_,
        uint256 publishTime_,
        uint256 thresholdTimestamp_
    );

    /// @notice                     The confidence interval exceeds the maximum allowed
    ///
    /// @param pyth_                The address of the Pyth contract
    /// @param priceFeedId_         The price feed ID
    /// @param confidence_          The confidence interval returned by the price feed (in Pyth feed scale, i.e., 10^expo)
    /// @param maxConfidence_       The maximum confidence interval allowed (in Pyth feed scale, i.e., 10^expo)
    error Pyth_FeedConfidenceExcessive(
        address pyth_,
        bytes32 priceFeedId_,
        uint64 confidence_,
        uint64 maxConfidence_
    );

    /// @notice                 The exponent from the price feed is positive, which results in loss of precision
    /// @dev                    Positive expo values should not be accepted as they cause precision loss
    ///
    /// @param pyth_            The address of the Pyth contract
    /// @param priceFeedId_     The price feed ID
    /// @param expo_            The exponent from the price feed (must be <= 0)
    error Pyth_ExponentPositive(address pyth_, bytes32 priceFeedId_, int32 expo_);

    // ========== CONSTRUCTOR ========== //

    constructor(Module parent_) Submodule(parent_) {}

    // ========== KERNEL FUNCTIONS =========== //

    /// @inheritdoc      Submodule
    function SUBKEYCODE() public pure override returns (SubKeycode) {
        return toSubKeycode("PRICE.PYTH");
    }

    /// @inheritdoc      Submodule
    function VERSION() public pure override returns (uint8 major, uint8 minor) {
        return (1, 0);
    }

    // ========== PRICE FEED FUNCTIONS ========== //

    /// @notice                         Validates the result of the price feed
    /// @dev                            This function will revert if:
    /// @dev                            - Price <= 0
    /// @dev                            - Publish time is before the update threshold from the current time
    /// @dev                            - Confidence interval exceeds the maximum allowed
    ///
    /// @param pyth_                    Pyth contract address
    /// @param priceFeedId_             The price feed ID
    /// @param priceData                The price data returned by the Pyth contract
    /// @param blockTimestamp           The current block timestamp
    /// @param paramsUpdateThreshold    The maximum number of seconds elapsed since the last price feed update
    /// @param paramsMaxConfidence      The maximum confidence interval allowed (in Pyth feed scale, i.e., 10^expo)
    function _validatePriceFeedResult(
        address pyth_,
        bytes32 priceFeedId_,
        IPyth.Price memory priceData,
        uint256 blockTimestamp,
        uint48 paramsUpdateThreshold,
        uint64 paramsMaxConfidence
    ) internal pure {
        // Price must be positive
        if (priceData.price <= 0)
            revert Pyth_FeedPriceInvalid(pyth_, priceFeedId_, priceData.price);

        // Publish time must be after the update threshold
        // The Pyth contract reverts if the price is stale, but this serves as a backup
        if (priceData.publishTime < blockTimestamp - uint256(paramsUpdateThreshold))
            revert Pyth_FeedPublishTimeStale(
                pyth_,
                priceFeedId_,
                priceData.publishTime,
                blockTimestamp - uint256(paramsUpdateThreshold)
            );

        if (priceData.conf > paramsMaxConfidence)
            revert Pyth_FeedConfidenceExcessive(
                pyth_,
                priceFeedId_,
                priceData.conf,
                paramsMaxConfidence
            );
    }

    /// @notice                         Retrieves the latest price returned by the specified Pyth price feed.
    /// @dev                            The result is validated using `_validatePriceFeedResult`, and will revert if invalid
    ///
    /// @param pyth_                    Pyth contract address
    /// @param priceFeedId_             The Pyth price feed ID
    /// @param updateThreshold_         The maximum number of seconds elapsed since the last price feed update
    /// @param maxConfidence_           The maximum confidence interval allowed (in output decimals scale)
    /// @param outputDecimals_          The number of decimals to return the price in
    /// @return uint256                 The validated price in the scale of `outputDecimals_`
    function _getFeedPrice(
        address pyth_,
        bytes32 priceFeedId_,
        uint48 updateThreshold_,
        uint256 maxConfidence_,
        uint8 outputDecimals_
    ) internal view returns (uint256) {
        IPyth.Price memory priceData;
        {
            // Encode function call: getPriceNoOlderThan(bytes32,uint256)
            bytes memory callData = abi.encodeWithSelector(
                IPyth.getPriceNoOlderThan.selector,
                priceFeedId_,
                uint256(updateThreshold_)
            );

            // Perform low-level static call (view function)
            (bool success, bytes memory returnData) = pyth_.staticcall(callData);

            if (!success) {
                // If returnData is empty, it's a call failure (not a contract or function doesn't exist)
                if (returnData.length == 0) {
                    revert Pyth_FeedInvalid(pyth_, priceFeedId_);
                }
                // Otherwise, bubble up the revert from the function
                assembly {
                    revert(add(returnData, 0x20), mload(returnData))
                }
            }

            // Validate return data length matches expected ABI-encoded IPyth.Price struct size
            if (returnData.length != _PRICE_DATA_SIZE) {
                revert Pyth_FeedInvalid(pyth_, priceFeedId_);
            }

            // Decode the return data
            priceData = abi.decode(returnData, (IPyth.Price));
        }

        // Although technically possible, a positive exponent has not been seen and would result in loss of precision
        // Therefore, it is not supported
        if (priceData.expo > 0) {
            revert Pyth_ExponentPositive(pyth_, priceFeedId_, priceData.expo);
        }

        // Convert maxConfidence from output decimals scale to Pyth feed scale (10^expo)
        // Formula: maxConfidenceInPythScale = maxConfidence * 10^expo / 10^outputDecimals
        //         = maxConfidence * 10^(expo - outputDecimals)
        // Note: Result is cast to uint64 since it's compared against priceData.conf (uint64)
        uint64 maxConfidenceInPythScale = SafeCast.encodeUInt64(
            maxConfidence_.mulDiv(
                10 ** uint256(uint32(-priceData.expo)),
                10 ** uint256(outputDecimals_)
            )
        );

        // Validate raw values from the price feed
        _validatePriceFeedResult(
            pyth_,
            priceFeedId_,
            priceData,
            block.timestamp,
            updateThreshold_,
            maxConfidenceInPythScale
        );

        uint256 price = uint256(int256(priceData.price));

        // Convert price to output decimals
        // The PRICE module will handle the zero value
        return price.mulDiv(10 ** uint256(outputDecimals_), 10 ** uint256(uint32(-priceData.expo)));
    }

    /// @notice                 Returns the price from a single Pyth feed, as specified in `params_`.
    /// @dev                    This function will revert if:
    /// @dev                    - Any parameter is invalid
    /// @dev                    - The exponent calculation would result in an overflow
    /// @dev                    - The price feed's results are invalid
    ///
    /// @param outputDecimals_  The number of output decimals (assumed to be the same as PRICE decimals)
    /// @param params_          Pyth feed parameters of type `OneFeedParams`
    /// @return                 Price in the scale of `outputDecimals_`
    function getOneFeedPrice(
        address,
        uint8 outputDecimals_,
        bytes calldata params_
    ) external view returns (uint256) {
        // Decode params
        OneFeedParams memory params = abi.decode(params_, (OneFeedParams));
        if (params.pyth == address(0)) revert Pyth_ParamsPythInvalid(0, params.pyth);
        if (params.priceFeedId == bytes32(0))
            revert Pyth_ParamsPriceFeedIdInvalid(1, params.priceFeedId);
        if (params.updateThreshold == 0)
            revert Pyth_ParamsUpdateThresholdInvalid(2, params.updateThreshold);
        if (params.maxConfidence == 0)
            revert Pyth_ParamsMaxConfidenceInvalid(3, params.maxConfidence);

        uint256 feedPrice = _getFeedPrice(
            params.pyth,
            params.priceFeedId,
            params.updateThreshold,
            params.maxConfidence,
            outputDecimals_
        );

        return feedPrice;
    }

    /// @notice                 Returns the result of dividing the price from the first Pyth feed by the price from the second.
    /// @dev                    For example, passing in ETH/USD and DAI/USD will return the ETH/DAI price.
    ///
    /// @dev                    This function will revert if:
    /// @dev                    - Any parameter is invalid
    /// @dev                    - The exponent calculation would result in an overflow
    /// @dev                    - Any of the price feeds' results are invalid
    ///
    /// @param outputDecimals_  The number of output decimals (assumed to be the same as PRICE decimals)
    /// @param params_          Pyth feed parameters of type `TwoFeedParams`
    /// @return uint256         Price in the scale of `outputDecimals_`.
    function getTwoFeedPriceDiv(
        address,
        uint8 outputDecimals_,
        bytes calldata params_
    ) external view returns (uint256) {
        // Decode params
        TwoFeedParams memory params = abi.decode(params_, (TwoFeedParams));
        if (params.firstPyth == address(0)) revert Pyth_ParamsPythInvalid(0, params.firstPyth);
        if (params.firstPriceFeedId == bytes32(0))
            revert Pyth_ParamsPriceFeedIdInvalid(1, params.firstPriceFeedId);
        if (params.firstUpdateThreshold == 0)
            revert Pyth_ParamsUpdateThresholdInvalid(2, params.firstUpdateThreshold);
        if (params.firstMaxConfidence == 0)
            revert Pyth_ParamsMaxConfidenceInvalid(3, params.firstMaxConfidence);
        if (params.secondPyth == address(0)) revert Pyth_ParamsPythInvalid(4, params.secondPyth);
        if (params.secondPriceFeedId == bytes32(0))
            revert Pyth_ParamsPriceFeedIdInvalid(5, params.secondPriceFeedId);
        if (params.secondUpdateThreshold == 0)
            revert Pyth_ParamsUpdateThresholdInvalid(6, params.secondUpdateThreshold);
        if (params.secondMaxConfidence == 0)
            revert Pyth_ParamsMaxConfidenceInvalid(7, params.secondMaxConfidence);

        // Get prices from feeds (both already converted to outputDecimals scale)
        uint256 numeratorPrice = _getFeedPrice(
            params.firstPyth,
            params.firstPriceFeedId,
            params.firstUpdateThreshold,
            params.firstMaxConfidence,
            outputDecimals_
        );
        uint256 denominatorPrice = _getFeedPrice(
            params.secondPyth,
            params.secondPriceFeedId,
            params.secondUpdateThreshold,
            params.secondMaxConfidence,
            outputDecimals_
        );

        // If denominatorPrice is zero, do an early exit
        // The PRICE module will handle the zero value
        if (denominatorPrice == 0) return 0;

        // Convert to numerator/denominator price and return
        uint256 priceResult = numeratorPrice.mulDiv(10 ** outputDecimals_, denominatorPrice);

        return priceResult;
    }

    /// @notice                 Returns the result of multiplying the price from the first Pyth feed by the price from the second.
    /// @dev                    For example, passing in ETH/DAI and DAI/USD will return the ETH/USD price.
    ///
    /// @dev                    This function will revert if:
    /// @dev                    - Any parameter is invalid
    /// @dev                    - The exponent calculation would result in an overflow
    /// @dev                    - Any of the price feeds' results are invalid
    ///
    /// @param outputDecimals_  The number of output decimals (assumed to be the same as PRICE decimals)
    /// @param params_          Pyth feed parameters of type `TwoFeedParams`
    /// @return uint256         Price in the scale of `outputDecimals_`.
    function getTwoFeedPriceMul(
        address,
        uint8 outputDecimals_,
        bytes calldata params_
    ) external view returns (uint256) {
        // Decode params
        TwoFeedParams memory params = abi.decode(params_, (TwoFeedParams));
        if (params.firstPyth == address(0)) revert Pyth_ParamsPythInvalid(0, params.firstPyth);
        if (params.firstPriceFeedId == bytes32(0))
            revert Pyth_ParamsPriceFeedIdInvalid(1, params.firstPriceFeedId);
        if (params.firstUpdateThreshold == 0)
            revert Pyth_ParamsUpdateThresholdInvalid(2, params.firstUpdateThreshold);
        if (params.firstMaxConfidence == 0)
            revert Pyth_ParamsMaxConfidenceInvalid(3, params.firstMaxConfidence);
        if (params.secondPyth == address(0)) revert Pyth_ParamsPythInvalid(4, params.secondPyth);
        if (params.secondPriceFeedId == bytes32(0))
            revert Pyth_ParamsPriceFeedIdInvalid(5, params.secondPriceFeedId);
        if (params.secondUpdateThreshold == 0)
            revert Pyth_ParamsUpdateThresholdInvalid(6, params.secondUpdateThreshold);
        if (params.secondMaxConfidence == 0)
            revert Pyth_ParamsMaxConfidenceInvalid(7, params.secondMaxConfidence);

        // Get prices from feeds (both already converted to outputDecimals scale)
        uint256 firstPrice = _getFeedPrice(
            params.firstPyth,
            params.firstPriceFeedId,
            params.firstUpdateThreshold,
            params.firstMaxConfidence,
            outputDecimals_
        );
        uint256 secondPrice = _getFeedPrice(
            params.secondPyth,
            params.secondPriceFeedId,
            params.secondUpdateThreshold,
            params.secondMaxConfidence,
            outputDecimals_
        );

        // Convert to first * second price and return
        uint256 priceResult = firstPrice.mulDiv(secondPrice, 10 ** outputDecimals_);

        return priceResult;
    }

    // ========== IERC165 ========== //

    /// @inheritdoc Submodule
    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
/// forge-lint: disable-end(mixed-case-function)
