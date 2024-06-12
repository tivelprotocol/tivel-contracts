// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

interface IMetaAggregator {
    function swap(
        address _tokenIn,
        address _tokenOut,
        uint256 _minAmountOut,
        address _to,
        bytes calldata _data
    ) external returns (uint256 amountOut);
}
