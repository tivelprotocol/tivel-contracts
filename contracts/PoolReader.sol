// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

import "./interfaces/IERC20.sol";
import "./interfaces/IFactory.sol";
import "./interfaces/IPool.sol";

struct PoolDetail {
    address pool;
    address quoteToken;
    string quoteSymbol;
    uint256 quoteDecimals;
    uint256 quoteReserve;
    uint256 quoteInDebt;
    uint256 withdrawingLiquidity;
    uint256 availableLiquidity;
    uint256 interest;
}

contract PoolReader {
    function allPools(address _factory) public view returns (address[] memory) {
        uint256 length = IFactory(_factory).poolLength();
        address[] memory pools = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            pools[i] = IFactory(_factory).pools(i);
        }
        return pools;
    }

    function poolDetail(address _pool) public view returns (PoolDetail memory) {
        address quoteToken = IPool(_pool).quoteToken();
        return
            PoolDetail({
                pool: _pool,
                quoteToken: quoteToken,
                quoteSymbol: IERC20(quoteToken).symbol(),
                quoteDecimals: IERC20(quoteToken).decimals(),
                quoteReserve: IPool(_pool).quoteReserve(),
                quoteInDebt: IPool(_pool).quoteInDebt(),
                withdrawingLiquidity: IPool(_pool).withdrawingLiquidity(),
                availableLiquidity: IPool(_pool).availableLiquidity(),
                interest: IPool(_pool).interest()
            });
    }

    function allPoolDetails(
        address _factory
    ) external view returns (PoolDetail[] memory) {
        address[] memory pools = allPools(_factory);
        PoolDetail[] memory poolDetails = new PoolDetail[](pools.length);
        for (uint256 i = 0; i < pools.length; i++) {
            poolDetails[i] = poolDetail(pools[i]);
        }
        return poolDetails;
    }
}
