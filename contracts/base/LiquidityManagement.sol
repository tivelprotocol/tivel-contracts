// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;
pragma abicoder v2;

import "../libraries/PoolAddress.sol";
import "../libraries/CallbackValidation.sol";
import "../interfaces/IMintCallback.sol";
import "./PeripheryPayments.sol";
import "./PeripheryImmutableState.sol";

/// @title Liquidity management functions
/// @notice Internal functions for safely managing liquidity
abstract contract LiquidityManagement is
    IMintCallback,
    PeripheryImmutableState,
    PeripheryPayments
{
    struct MintCallbackData {
        address token;
        address payer;
    }

    /// @inheritdoc IMintCallback
    function mintCallback(
        address _token,
        uint256 _liquidity,
        bytes calldata _data
    ) external override {
        MintCallbackData memory decoded = abi.decode(_data, (MintCallbackData));
        CallbackValidation.verifyCallback(poolDeployer, decoded.token);

        if (_liquidity > 0) pay(_token, decoded.payer, msg.sender, _liquidity);
    }

    /// @notice Add liquidity to an initialized pool
    function addLiquidity(
        address _token,
        uint256 _liquidity,
        address _to
    ) internal returns (IPool) {
        IPool pool = IPool(PoolAddress.computeAddress(poolDeployer, _token));

        pool.mint(
            _to,
            _liquidity,
            abi.encode(MintCallbackData({token: _token, payer: msg.sender}))
        );

        return pool;
    }
}
