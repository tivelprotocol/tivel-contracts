// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

/// @title Provides functions for deriving a pool address from the pool deployer, tokens
library PoolAddress {
    bytes32 internal constant POOL_INIT_CODE_HASH =
        0xf1036993f1275518585918ce3130714428155c415f20bed4b4bdbb1d7d87aa71;

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

