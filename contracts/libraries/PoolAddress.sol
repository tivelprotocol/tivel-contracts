// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

/// @title Provides functions for deriving a pool address from the pool deployer, tokens
library PoolAddress {
    bytes32 internal constant POOL_INIT_CODE_HASH =
        0xbd1575baaac859f31c0502bbe3808283611e4319fec6ae1632f4c2d49305b0a3;

    function computeAddress(
        address _poolDeployer,
        address _token
    ) internal pure returns (address pool) {
        pool = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff",
                            _poolDeployer,
                            keccak256(abi.encode(_token)),
                            POOL_INIT_CODE_HASH
                        )
                    )
                )
            )
        );
    }
}
