// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

import "./interfaces/IERC20.sol";
import "./interfaces/IPriceFeed.sol";
import "./interfaces/IPriceFeedIntegration.sol";

contract PriceFeed is IPriceFeed {
    uint256 public constant override PRECISION = 1e30;
    address public manager;
    address[] public integrations;

    event SetManager(address manager);
    event SetIntegrations(address[] integrations);

    error Forbidden(address sender);

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

    function setIntegrations(
        address[] memory _integrations
    ) external onlyManager {
        integrations = _integrations;

        emit SetIntegrations(_integrations);
    }

    function _tryGetIntegrationPrice(
        IPriceFeedIntegration _integration,
        address _baseToken,
        address _quoteToken
    ) internal view returns (uint256) {
        try _integration.getPrice(_baseToken, _quoteToken) returns (
            uint256 result
        ) {
            return result;
        } catch {
            return 0;
        }
    }

    function getPrice(
        address _baseToken,
        address _quoteToken
    ) external view override returns (uint256 highest, uint256 lowest) {
        if (_baseToken == _quoteToken) {
            return (PRECISION, PRECISION);
        }
        uint256 length = integrations.length;
        for (uint256 i = 0; i < length; i++) {
            IPriceFeedIntegration integration = IPriceFeedIntegration(
                integrations[i]
            );
            uint256 price = _tryGetIntegrationPrice(
                integration,
                _baseToken,
                _quoteToken
            );

            if (price > 0) {
                uint256 prec = integration.PRECISION();
                price = (price * PRECISION) / prec;

                if (price > highest) {
                    highest = price;
                }
                if (price < lowest || lowest == 0) {
                    lowest = price;
                }
            }
        }

        uint256 baseDecimals = IERC20(_baseToken).decimals();
        uint256 quoteDecimals = IERC20(_quoteToken).decimals();
        uint256 basePrec = 10 ** baseDecimals;
        uint256 quotePrec = 10 ** quoteDecimals;
        highest = (highest * quotePrec) / basePrec;
        lowest = (lowest * quotePrec) / basePrec;
    }

    function getHighestPrice(
        address _baseToken,
        address _quoteToken
    ) external view override returns (uint256 highest) {
        if (_baseToken == _quoteToken) {
            return PRECISION;
        }
        uint256 length = integrations.length;
        for (uint256 i = 0; i < length; i++) {
            IPriceFeedIntegration integration = IPriceFeedIntegration(
                integrations[i]
            );
            uint256 price = _tryGetIntegrationPrice(
                integration,
                _baseToken,
                _quoteToken
            );

            if (price > 0) {
                uint256 prec = integration.PRECISION();
                price = (price * PRECISION) / prec;

                if (price > highest) {
                    highest = price;
                }
            }
        }

        uint256 baseDecimals = IERC20(_baseToken).decimals();
        uint256 quoteDecimals = IERC20(_quoteToken).decimals();
        uint256 basePrec = 10 ** baseDecimals;
        uint256 quotePrec = 10 ** quoteDecimals;
        highest = (highest * quotePrec) / basePrec;
    }

    function getLowestPrice(
        address _baseToken,
        address _quoteToken
    ) external view override returns (uint256 lowest) {
        if (_baseToken == _quoteToken) {
            return PRECISION;
        }
        uint256 length = integrations.length;
        for (uint256 i = 0; i < length; i++) {
            IPriceFeedIntegration integration = IPriceFeedIntegration(
                integrations[i]
            );
            uint256 price = _tryGetIntegrationPrice(
                integration,
                _baseToken,
                _quoteToken
            );

            if (price > 0) {
                uint256 prec = integration.PRECISION();
                price = (price * PRECISION) / prec;

                if (price < lowest || lowest == 0) {
                    lowest = price;
                }
            }
        }

        uint256 baseDecimals = IERC20(_baseToken).decimals();
        uint256 quoteDecimals = IERC20(_quoteToken).decimals();
        uint256 basePrec = 10 ** baseDecimals;
        uint256 quotePrec = 10 ** quoteDecimals;
        lowest = (lowest * quotePrec) / basePrec;
    }
}
