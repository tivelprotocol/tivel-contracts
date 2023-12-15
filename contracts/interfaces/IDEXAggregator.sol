// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

interface IDEXAggregator {
    function dexes(uint256) external view returns (address);

    function dexNames(uint256) external view returns (string memory);

    function dexIndex(address) external view returns (uint256);

    function dexLength() external view returns (uint256);

    function validatePair(
        address _dex,
        address _tokenIn,
        address _tokenOut
    ) external view returns (bool);

    function getAmountIn(
        address _dex,
        address _tokenIn,
        address _tokenOut,
        uint256 _amountOut
    ) external view returns (uint256 amountIn, address dex);

    function getAmountOut(
        address _dex,
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn
    ) external view returns (uint256 amountOut, address dex);

    function swap(
        address _dex,
        address _tokenIn,
        address _tokenOut,
        uint256 _minAmountOut,
        address _to
    ) external returns (uint256 amountOut, address dex);
}
