// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

import "../libraries/TransferHelper.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IFactory.sol";
import "../interfaces/IDEXAggregator.sol";
import "../interfaces/IMintCallback.sol";
import "../interfaces/IPool.sol";

contract Callee is IMintCallback {
    error WrongPool();

    address public immutable factory;

    constructor(address _factory) {
        factory = _factory;
    }

    function mintCallback(
        address _token,
        uint256 _liquidity,
        bytes calldata _data
    ) external override {
        if (IPool(msg.sender).quoteToken() != _token) revert WrongPool();

        if (_liquidity > 0) {
            TransferHelper.safeTransfer(_token, msg.sender, _liquidity);
        }
    }

    function closeCallback(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountOut,
        bytes calldata /* _data */
    ) external {
        IFactory _factory = IFactory(factory);
        IDEXAggregator aggregator = IDEXAggregator(_factory.dexAggregator());

        uint256 balance = IERC20(_tokenIn).balanceOf(address(this));
        TransferHelper.safeTransfer(_tokenIn, address(aggregator), balance);
        IDEXAggregator(aggregator).swap(
            address(0),
            _tokenIn,
            _tokenOut,
            _amountOut,
            address(this)
        );
        TransferHelper.safeTransfer(_tokenOut, address(msg.sender), _amountOut);

        uint256 dust = IERC20(_tokenOut).balanceOf(address(this));
        if (dust > 0) {
            (uint256 dustOut, ) = IDEXAggregator(aggregator).getAmountOut(
                address(0),
                _tokenOut,
                _tokenIn,
                dust
            );
            if (dustOut > 0) {
                TransferHelper.safeTransfer(
                    _tokenOut,
                    address(aggregator),
                    dust
                );
                IDEXAggregator(aggregator).swap(
                    address(0),
                    _tokenOut,
                    _tokenIn,
                    0,
                    address(msg.sender)
                );
            } else {
                TransferHelper.safeTransfer(
                    _tokenOut,
                    _factory.protocolFeeTo(),
                    dust
                );
            }
        }
    }

    function mint(
        address _pool,
        address _to,
        uint256 _liquidity,
        bytes calldata _data
    ) external {
        IPool(_pool).mint(_to, _liquidity, _data);
    }

    function collect(address _pool, address _to, uint256 _amount) external {
        IPool(_pool).collect(_to, _amount);
    }

    function addBurnRequest(
        address _pool,
        uint256 _liquidity,
        address _to,
        bytes calldata _data
    ) external returns (uint256) {
        return IPool(_pool).addBurnRequest(_liquidity, _to, _data);
    }

    function close(address _pool, bytes32 _positionKey) external {
        IPool(_pool).close(
            IPositionStorage.CloseTradePositionParams({
                positionKey: _positionKey,
                data0: new bytes(0),
                data1: new bytes(0),
                closer: msg.sender
            })
        );
    }
}
