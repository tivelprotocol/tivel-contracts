// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

interface IPeripheryImmutableState {
    function factory() external view returns (address);

    function WETH9() external view returns (address);

    function poolDeployer() external view returns (address);
}
