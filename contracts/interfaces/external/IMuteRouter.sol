// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

interface IMuteRouter {
    function pairFor(
        address _tokenA,
        address _tokenB,
        bool _stable
    ) external view returns (address);

    function getAmountOut(
        uint256 _amountIn,
        address _tokenIn,
        address _tokenOut
    ) external view returns (uint256 amountOut, bool stable, uint256 fee);

    function swapExactTokensForTokens(
        uint256 _amountIn,
        uint256 _amountOutMin,
        address[] calldata _path,
        address _to,
        uint256 _deadline,
        bool[] calldata _stable
    ) external returns (uint256[] memory amounts);
}
