// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

interface IPriceFeed {
    function PRECISION() external view returns (uint256);

    function getPrice(
        address _baseToken,
        address _quoteToken
    ) external view returns (uint256 highest, uint256 lowest);

    function getHighestPrice(
        address _baseToken,
        address _quoteToken
    ) external view returns (uint256 highest);

    function getLowestPrice(
        address _baseToken,
        address _quoteToken
    ) external view returns (uint256 lowest);
}
