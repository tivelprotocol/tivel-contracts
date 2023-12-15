// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

import "./interfaces/IPoolDeployer.sol";
import "./Pool.sol";

contract PoolDeployer is IPoolDeployer {
    address public override factory;

    error Forbidden(address sender);
    error InitializedAlready();

    event SetFactory(address indexed factory);

    modifier onlyFactory() {
        if (msg.sender != factory) revert Forbidden(msg.sender);
        _;
    }

    function setFactory(address _factory) external {
        if (factory != address(0)) revert InitializedAlready();
        factory = _factory;

        emit SetFactory(_factory);
    }

    function poolInitCodeHash() external pure returns (bytes32) {
        return keccak256(type(Pool).creationCode);
    }

    function deployPool(
        address _quoteToken,
        uint256 _interest
    ) external override onlyFactory returns (address payable pool) {
        // create pool contract
        pool = payable(
            address(new Pool{salt: keccak256(abi.encode(_quoteToken))}())
        );
        Pool(pool).initialize(factory, _quoteToken, _interest);
    }
}
