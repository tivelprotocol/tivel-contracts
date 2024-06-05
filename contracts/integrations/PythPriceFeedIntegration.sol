// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

import "../libraries/PythStructs.sol";
import "../libraries/PythUtils.sol";
import "../interfaces/external/IPyth.sol";
import "../interfaces/IPriceFeedIntegration.sol";
import "hardhat/console.sol";

contract PythPriceFeedIntegration is IPriceFeedIntegration {
    uint256 public constant override PRECISION = 1e18;
    uint8 public constant DECIMALS = 18;
    address public manager;
    address public pythAddress;
    mapping(address => bytes32) feeds;

    event SetManager(address manager);
    event SetPythAddress(address pyth);
    event SetPriceFeed(address token, bytes32 feed);

    error Forbidden(address sender);
    error InvalidFeed(address token);

    constructor(address _pythAddress) {
        manager = msg.sender;
        pythAddress = _pythAddress;
    }

    modifier onlyManager() {
        if (msg.sender != manager) revert Forbidden(msg.sender);
        _;
    }

    function setManager(address _manager) external onlyManager {
        manager = _manager;

        emit SetManager(_manager);
    }

    function setPythAddress(address _pythAddress) external onlyManager {
        pythAddress = _pythAddress;

        emit SetPythAddress(_pythAddress);
    }

    function setPriceFeed(address _token, bytes32 _feed) external onlyManager {
        feeds[_token] = _feed;

        emit SetPriceFeed(_token, _feed);
    }

    function _price(address _token) internal view returns (uint256 price) {
        bytes32 feed = feeds[_token];
        if (feed != bytes32(0)) {
            PythStructs.Price memory pythPrice = IPyth(pythAddress).getPriceUnsafe(
                feed
            );
            price = PythUtils.convertToUint(
                pythPrice.price,
                pythPrice.expo,
                DECIMALS
            );
        }
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
