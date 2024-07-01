// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

interface IKoiV2Factory {
    function getPair(
        address _tokenA,
        address _tokenB,
        bool _stable
    ) external view returns (address);
}
