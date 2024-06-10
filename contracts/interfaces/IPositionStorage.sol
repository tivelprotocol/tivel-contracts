// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

interface IPositionStorage {
    struct BaseToken {
        address id;
        uint256 amount;
        uint256 entryPrice;
        uint256 liqPrice;
        uint256 closePrice;
    }
    struct QuoteToken {
        address id;
        uint256 amount;
    }
    struct Collateral {
        address id;
        uint256 amount;
        uint256 entryPrice;
        uint256 liqPrice;
        uint256 closePrice;
    }
    struct Status {
        bool isClosed;
        bool isRollbacked;
        bool isClosedManuallyStep1;
        bool isClosedManuallyStep2;
    }
    struct TradePosition {
        bytes32 positionKey;
        address owner;
        address pool;
        BaseToken baseToken;
        QuoteToken quoteToken;
        Collateral collateral;
        uint256 deadline;
        uint256 stoplossPrice;
        uint256 takeProfitPrice;
        uint256 fee;
        uint256 protocolFee;
        Status status;
        address closer;
        uint256 liquidationMarkTime;
    }
    struct OpenTradePositionParams {
        address owner;
        address baseToken;
        address quoteToken;
        address collateral;
        uint256 baseAmount;
        uint256 quoteAmount;
        uint256 collateralAmount;
        uint256 deadline;
        uint256 stoplossPrice;
        uint256 takeProfitPrice;
    }
    struct CloseTradePositionParams {
        bytes32 positionKey;
        bytes data0;
        bytes data1;
        address closer;
    }
    struct RollbackTradePositionParams {
        bytes32 positionKey;
        address rollbacker;
        address serviceToken;
        uint256 serviceFee;
    }
    struct UpdateTPnSLParams {
        bytes32 positionKey;
        uint256 takeProfitPrice;
        uint256 stoplossPrice;
        address updater;
        address serviceToken;
        uint256 serviceFee;
    }
    struct UpdateCollateralAmountParams {
        bytes32 positionKey;
        uint256 amount;
        address updater;
        address serviceToken;
        uint256 serviceFee;
    }
    struct UpdateDeadlineParams {
        bytes32 positionKey;
        uint256 deadline;
        address updater;
        address serviceToken;
        uint256 serviceFee;
    }

    function factory() external view returns (address);

    function position(bytes32) external view returns (TradePosition memory);

    function positionKeys(uint256) external view returns (bytes32);

    function positionKeyToIndex(bytes32) external view returns (uint256);

    function positionLength() external view returns (uint256);

    function getMinCollateralAmount(
        OpenTradePositionParams memory
    ) external view returns (uint256);

    function getQuoteAmountRange(
        OpenTradePositionParams memory
    ) external view returns (uint256 minQuoteAmount, uint256 maxQuoteAmount);

    function previewTradePosition(
        OpenTradePositionParams memory
    ) external view returns (TradePosition memory);

    function previewUpdateCollateralAmount(
        UpdateCollateralAmountParams memory
    ) external view returns (uint256 collateralLiqPrice);

    function previewUpdateDeadline(
        UpdateDeadlineParams memory
    ) external view returns (uint256 fee, uint256 protocolFee);

    function canLiquidate(bytes32) external view returns (bool);

    function canLiquidationMark(bytes32) external view returns (bool);

    function openTradePosition(
        TradePosition memory
    ) external returns (bytes32 positionKey);

    function updateStatus(
        bytes32 _positionKey,
        address _updater
    ) external returns (bool needLiquidate);

    function liquidationMark(bytes32) external;

    function rollback(bytes32 _positionKey, address _updater) external;

    function closeManuallyStep1(bytes32) external;

    function closeManuallyStep2(bytes32) external;

    function updateCloseValues(
        bytes32 _positionKey,
        uint256 _baseValue,
        uint256 _loss,
        uint256 _remainingCollateralAmount
    ) external;

    function updateTPnSL(UpdateTPnSLParams memory) external;

    function updateCollateralAmount(
        UpdateCollateralAmountParams memory
    ) external returns (uint256 collateralLiqPrice);

    function updateDeadline(
        UpdateDeadlineParams memory
    ) external returns (uint256 fee, uint256 protocolFee);
}
