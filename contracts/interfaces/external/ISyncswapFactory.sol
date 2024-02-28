// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

interface ISyncswapFactory {
    function getPool(
        address _tokenA,
        address _tokenB
    ) external view returns (address);
}
