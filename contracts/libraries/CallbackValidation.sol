// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

import "../interfaces/IPool.sol";
import "./PoolAddress.sol";

library CallbackValidation {
    /// @notice Returns the address of a valid Pool
    /// @param _poolDeployer The contract address of the pool deployer
    /// @param _token The contract address of quote token
    /// @return pool The pool contract address
    function verifyCallback(
        address _poolDeployer,
        address _token
    ) internal view returns (IPool pool) {
        pool = IPool(PoolAddress.computeAddress(_poolDeployer, _token));
        require(msg.sender == address(pool));
    }
}
