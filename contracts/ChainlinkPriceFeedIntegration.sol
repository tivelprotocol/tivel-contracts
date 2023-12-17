// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

import "./interfaces/IPriceFeedIntegration.sol";
import "./interfaces/IChainlinkPriceFeed.sol";

contract ChainlinkPriceFeedIntegration is IPriceFeedIntegration {
    uint256 public constant override PRECISION = 1e8;
    address public manager;
    mapping(address => address) feeds;

    event SetManager(address manager);
    event SetPriceFeed(address token, address feed);

    error Forbidden(address sender);
    error InvalidFeed(address token);

    constructor() {
        manager = msg.sender;
    }

    modifier onlyManager() {
        if (msg.sender != manager) revert Forbidden(msg.sender);
        _;
    }

    function setManager(address _manager) external onlyManager {
        manager = _manager;

        emit SetManager(_manager);
    }

    function setPriceFeed(address _token, address _feed) external onlyManager {
        feeds[_token] = _feed;

        emit SetPriceFeed(_token, _feed);
    }

    function _price(address _token) internal view returns (uint256 price) {
        address feed = feeds[_token];
        if (feed == address(0)) revert InvalidFeed(_token);
        price = IChainlinkPriceFeed(feed).latestAnswer();
    }

    function getPrice(
        address _baseToken,
        address _quoteToken
    ) external view override returns (uint256 price) {
        uint256 quotePrice = _price(_quoteToken);
        if (quotePrice > 0) {
            uint256 basePrice = _price(_baseToken);
            price = (basePrice * PRECISION) / quotePrice;
        }
    }
}
