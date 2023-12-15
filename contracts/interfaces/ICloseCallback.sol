// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

interface ICloseCallback {
    function closeCallback(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountOut,
        bytes calldata _data
    ) external;
}
