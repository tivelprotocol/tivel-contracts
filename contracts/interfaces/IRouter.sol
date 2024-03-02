// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

import "../interfaces/IPositionStorage.sol";

interface IRouter {
    struct OpenTradePositionParams {
        address baseToken;
        address quoteToken;
        address collateral;
        uint256 baseAmount;
        uint256 quoteAmount;
        uint256 collateralAmount;
        uint256 deadline;
        uint256 stoplossPrice;
        uint256 txDeadline;
    }
    struct CloseTradePositionParams {
        address pool;
        bytes32 positionKey;
        uint256 txDeadline;
    }
    struct RollbackTradePositionParams {
        address pool;
        bytes32 positionKey;
        uint256 txDeadline;
    }
    struct UpdateStoplossPriceParams {
        address pool;
        bytes32 positionKey;
        uint256 stoplossPrice;
        uint256 txDeadline;
    }
    struct UpdateCollateralAmountParams {
        address pool;
        bytes32 positionKey;
        uint256 amount;
        uint256 txDeadline;
    }
    struct UpdateDeadlineParams {
        address pool;
        bytes32 positionKey;
        uint256 deadline;
        uint256 txDeadline;
    }

    function WETH() external view returns (address);

    function factory() external view returns (address);

    function preview(
        OpenTradePositionParams memory
    ) external view returns (IPositionStorage.TradePosition memory);

    function open(OpenTradePositionParams memory) external returns (bytes32);

    function openWithEthAsCollateral(
        OpenTradePositionParams memory
    ) external payable returns (bytes32);

    function openWithEthAsBaseToken(
        OpenTradePositionParams memory
    ) external payable returns (bytes32);

    function openETH(
        OpenTradePositionParams memory
    ) external payable returns (bytes32);

    function close(CloseTradePositionParams memory) external;

    function rollback(RollbackTradePositionParams memory) external;

    function updateStoplossPrice(UpdateStoplossPriceParams memory) external;

    function updateCollateralAmount(
        UpdateCollateralAmountParams memory
    ) external returns (uint256 collateralLiqPrice);

    function updateDeadline(UpdateDeadlineParams memory) external;
}
