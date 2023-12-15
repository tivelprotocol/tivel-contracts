// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

interface IBurnCallback {
    function burnCallback(uint256 _liquidity, bytes calldata _data) external;
}
