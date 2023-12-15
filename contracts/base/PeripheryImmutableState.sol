// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

import "../interfaces/IFactory.sol";
import "../interfaces/IPeripheryImmutableState.sol";

/// @title Immutable state
/// @notice Immutable state used by periphery contracts
abstract contract PeripheryImmutableState is IPeripheryImmutableState {
    /// @inheritdoc IPeripheryImmutableState
    address public immutable override factory;
    /// @inheritdoc IPeripheryImmutableState
    address public immutable override WETH9;
    /// @inheritdoc IPeripheryImmutableState
    address public immutable override poolDeployer;

    constructor(address _factory, address _WETH9) {
        factory = _factory;
        WETH9 = _WETH9;
        poolDeployer = IFactory(_factory).poolDeployer();
    }
}
