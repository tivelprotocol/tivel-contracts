// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

interface ISyncswapPool {
    struct TokenAmount {
        address token;
        uint amount;
    }

    function token0() external view returns (address);

    function token1() external view returns (address);

    function getReserves() external view returns (uint256, uint256);

    function getSwapFee(
        address _sender,
        address _tokenIn,
        address _tokenOut,
        bytes memory data
    ) external view returns (uint24);

    function getAmountOut(
        address _tokenIn,
        uint256 _amountIn,
        address _sender
    ) external view returns (uint256 amountOut);

    function getAmountIn(
        address _tokenOut,
        uint256 _amountOut,
        address _sender
    ) external view returns (uint256 amountIn);

    function swap(
        bytes calldata _data,
        address _sender,
        address _callback,
        bytes calldata _callbackData
    ) external returns (TokenAmount memory tokenAmount);
}
