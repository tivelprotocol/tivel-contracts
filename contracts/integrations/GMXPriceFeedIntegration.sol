// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

import "../interfaces/IPriceFeedIntegration.sol";
import "../interfaces/IGMXPriceFeed.sol";

contract GMXPriceFeedIntegration is IPriceFeedIntegration {
    uint256 public constant override PRECISION = 1e30;
    address public immutable feed; // 0x11D62807dAE812a0F1571243460Bf94325F43BB7

    constructor(address _feed) {
        feed = _feed;
    }

    function _price(address _token) internal view returns (uint256 price) {
        price = IGMXPriceFeed(feed).prices(_token);
    }

    function getPrice(
        address _baseToken,
        address _quoteToken
    ) external view override returns (uint256 price) {
        uint256 basePrice = _price(_baseToken);
        if (basePrice > 0) {
            uint256 quotePrice = _price(_quoteToken);
            price = (quotePrice * PRECISION) / basePrice;
        }
    }
}
