// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

interface IDEXIntegration {
    function validatePair(
        address _tokenIn,
        address _tokenOut
    ) external view returns (bool);

    function getAmountOut(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn
    ) external view returns (uint256);

    function getAmountIn(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountOut
    ) external view returns (uint256);

    function swap(
        address _tokenIn,
        address _tokenOut,
        address _to
    ) external returns (uint256);
}
