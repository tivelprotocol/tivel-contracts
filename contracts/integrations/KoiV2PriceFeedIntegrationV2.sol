// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

import "../interfaces/IPriceFeedIntegration.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/external/IKoiV2Factory.sol";
import "../interfaces/external/IKoiV2Pair.sol";

contract KoiV2PriceFeedIntegrationV2 is IPriceFeedIntegration {
    address public manager;
    uint256 public constant override PRECISION = 1e30;
    address public immutable factory;
    address public immutable WETH;
    mapping(address => mapping(address => address)) public bridgeToken;

    error Forbidden(address sender);
    error ZeroAddress();

    event SetManager(address manager);
    event SetBridgeToken(
        address indexed tokenIn,
        address indexed tokenOut,
        address bridgeToken
    );

    constructor(address _factory, address _WETH) {
        factory = _factory;
        WETH = _WETH;
        manager = msg.sender;
    }

    modifier onlyManager() {
        if (msg.sender != manager) revert Forbidden(msg.sender);
        _;
    }

    function setManager(address _newManager) external onlyManager {
        if (msg.sender == address(0)) revert ZeroAddress();
        manager = _newManager;

        emit SetManager(_newManager);
    }

    function setBridgeToken(
        address _tokenIn,
        address _tokenOut,
        address _bridgeToken
    ) external onlyManager {
        bridgeToken[_tokenIn][_tokenOut] = _bridgeToken;

        emit SetBridgeToken(_tokenIn, _tokenOut, _bridgeToken);
    }

    function _quote(
        uint256 _amount,
        address _baseToken,
        address _quoteToken
    ) internal view returns (uint256 price) {
        address pool = IKoiV2Factory(factory).getPair(
            _baseToken,
            _quoteToken,
            false // only volatile pairs now
        );
        if (pool != address(0)) {
            address token0 = IKoiV2Pair(pool).token0();
            (uint256 reserve0, uint256 reserve1, ) = IKoiV2Pair(pool)
                .getReserves();
            (uint256 baseReserve, uint256 quoteReserve) = _baseToken == token0
                ? (reserve0, reserve1)
                : (reserve1, reserve0);
            if (baseReserve > 0)
                price = (_amount * PRECISION * quoteReserve) / baseReserve;
        }
    }

    function getPrice(
        address _baseToken,
        address _quoteToken
    ) external view override returns (uint256 price) {
        if (_baseToken == _quoteToken) {
            return PRECISION;
        }

        address bridge = bridgeToken[_baseToken][_quoteToken];
        address _WETH = WETH;
        if (_baseToken == _WETH || _quoteToken == _WETH) {
            price = _quote(1, _baseToken, _quoteToken);
        } else {
            if (bridge == address(0)) {
                bridge = _WETH;
            }
            price = _quote(1, _baseToken, bridge);
            price = _quote(price, bridge, _quoteToken) / PRECISION;
        }

        uint256 baseDecimals = IERC20(_baseToken).decimals();
        uint256 quoteDecimals = IERC20(_quoteToken).decimals();
        uint256 basePrec = 10 ** baseDecimals;
        uint256 quotePrec = 10 ** quoteDecimals;
        price = (price * basePrec) / quotePrec;
    }
}
