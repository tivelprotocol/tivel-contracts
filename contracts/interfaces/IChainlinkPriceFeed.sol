// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

interface IChainlinkPriceFeed {
    function latestAnswer() external view returns (uint256);
}
