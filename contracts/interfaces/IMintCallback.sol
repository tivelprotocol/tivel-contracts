// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

interface IMintCallback {
    function mintCallback(
        address _token,
        uint256 _liquidity,
        bytes calldata _data
    ) external;
}
