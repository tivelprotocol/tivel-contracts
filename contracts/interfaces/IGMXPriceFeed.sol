// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

interface IGMXPriceFeed {
    function prices(address) external view returns (uint256);
}
