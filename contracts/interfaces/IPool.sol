// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

import "./IPositionStorage.sol";
import "./IWithdrawalMonitor.sol";

interface IPool {
    struct LiquidityPosition {
        uint256 liquidity;
        uint256 feeDebt;
        uint256 pendingFee;
        uint256 withdrawingLiquidity;
    }

    function factory() external view returns (address);

    function positionStorage() external view returns (address);

    function withdrawalMonitor() external view returns (address);

    function quoteToken() external view returns (address);

    function precision() external view returns (uint256);

    function interest() external view returns (uint256);

    function maxOpenInterest() external view returns (uint256);

    function openInterest() external view returns (uint256);

    function quoteReserve() external view returns (uint256);

    function quoteInDebt() external view returns (uint256);

    function withdrawingLiquidity() external view returns (uint256);

    function accFee() external view returns (uint256);

    function accProtocolFee() external view returns (uint256);

    function accFeePerShare() external view returns (uint256);

    function tradeableBaseToken(address) external view returns (bool);

    function baseReserve(address) external view returns (uint256);

    function collateralReserve(address) external view returns (uint256);

    function availableLiquidity() external view returns (uint256);

    function liquidityPosition(
        address
    )
        external
        view
        returns (
            uint256 liquidity,
            uint256 feeDebt,
            uint256 pendingFee,
            uint256 withdrawingLiquidity
        );

    function claimableFee(address) external view returns (uint256);

    function setInterest(uint256) external;

    function setMaxOpenInterest(uint256) external;

    function setBaseTokens(
        address[] memory _baseTokens,
        bool[] memory _tradeables
    ) external;

    function availLiquidity() external;

    function mint(
        address _to,
        uint256 _liquidity,
        bytes calldata _data
    ) external;

    function collect(address _to, uint256 _amount) external;

    function addBurnRequest(
        uint256 _liquidity,
        address _to,
        bytes calldata _data
    ) external returns (uint256);

    function burn(IWithdrawalMonitor.WithdrawalRequest memory) external;

    function open(
        IPositionStorage.OpenTradePositionParams memory
    ) external returns (bytes32);

    function close(IPositionStorage.CloseTradePositionParams calldata) external;

    function rollback(
        IPositionStorage.RollbackTradePositionParams memory
    ) external;

    function updateCollateralAmount(
        IPositionStorage.UpdateCollateralAmountParams memory
    ) external returns (uint256 collateralLiqPrice);

    function updateDeadline(
        IPositionStorage.UpdateDeadlineParams memory
    ) external;
}
