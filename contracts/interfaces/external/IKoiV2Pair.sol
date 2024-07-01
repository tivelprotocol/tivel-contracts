// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

interface IKoiV2Pair {
    function token0() external view returns (address);

    function token1() external view returns (address);

    function getReserves() external view returns (uint256, uint256, uint256);

    function getAmountOut(
        uint256 _amountIn,
        address _tokenIn
    ) external view returns (address);
    
    function pairFee() external view returns (uint256);
}
