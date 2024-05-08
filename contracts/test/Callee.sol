// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

import "../libraries/TransferHelper.sol";
import "../interfaces/IMintCallback.sol";
import "../interfaces/IPool.sol";

contract Callee is IMintCallback {
    error WrongPool();

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
}
