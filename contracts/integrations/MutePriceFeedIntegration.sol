// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

import "../interfaces/IPriceFeedIntegration.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/external/IMuteRouter.sol";

contract MutePriceFeedIntegration is IPriceFeedIntegration {
    uint256 public constant override PRECISION = 1e30;
    address public immutable router;

    constructor(address _router) {
        router = _router;
    }

    function getPrice(
        address _baseToken,
        address _quoteToken
    ) external view override returns (uint256 price) {
        if (_baseToken == _quoteToken) {
            return PRECISION;
        }

        uint256 amountIn = 10000;
        (uint256 amountOut, , uint256 fee) = IMuteRouter(router).getAmountOut(
            amountIn,
            _baseToken,
            _quoteToken
        );
        amountOut = (amountOut * (10000 + fee)) / 10000;
        price = (amountOut * PRECISION) / amountIn;

        uint256 baseDecimals = IERC20(_baseToken).decimals();
        uint256 quoteDecimals = IERC20(_quoteToken).decimals();
        uint256 basePrec = 10 ** baseDecimals;
        uint256 quotePrec = 10 ** quoteDecimals;
        price = (price * basePrec) / quotePrec;
    }
}
