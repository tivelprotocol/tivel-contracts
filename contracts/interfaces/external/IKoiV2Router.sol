// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

interface IKoiV2Router {
    function swapExactTokensForTokens(
        uint256 _amountIn,
        uint256 _amountOutMin,
        address[] calldata _path,
        address _to,
        uint256 _deadline,
        bool[] calldata _stable
    ) external returns (uint256[] memory amounts);
}
