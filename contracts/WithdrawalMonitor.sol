// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

import "@chainlink/contracts/src/v0.8/AutomationCompatible.sol";
import "./libraries/PoolAddress.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IFactory.sol";
import "./interfaces/IPool.sol";
import "./interfaces/IWithdrawalMonitor.sol";
import "./interfaces/external/IWETH9.sol";

contract WithdrawalMonitor is
    AutomationCompatibleInterface,
    IWithdrawalMonitor
{
    bytes4 private constant SELECTOR =
        bytes4(keccak256(bytes("transfer(address,uint256)")));
    address public override factory;
    address public poolDeployer;

    address public manager;
    address public keeper;

    mapping(address => WithdrawalRequest[]) public override request;
    mapping(address => uint256) public override currentIndex;

    error InitializedAlready();
    error Forbidden(address sender);
    error EthTransferFailed(address to, uint256 value);
    error TransferFailed(address token, address to, uint256 value);

    event SetManager(address manager);
    event SetKeeper(address keeper);
    event AddRequest(
        address indexed pool,
        uint256 indexed index,
        address owner,
        address quoteToken,
        uint256 liquidity,
        address to,
        bytes data
    );
    event UpdateCallbackResult(
        address indexed pool,
        uint256 indexed index,
        string result
    );
    event FulfillRequest(address indexed pool, uint256 indexed index);
    event ProcessBatch(
        uint256 count,
        bytes performData,
        uint256 usedGas,
        uint256 gasPrice
    );

    constructor(address _keeper) {
        manager = msg.sender;
        keeper = _keeper;
    }

    modifier onlyManager() {
        if (msg.sender != manager) revert Forbidden(msg.sender);
        _;
    }

    function setFactory(address _factory) external {
        if (factory != address(0)) revert InitializedAlready();
        factory = _factory;
        poolDeployer = IFactory(_factory).poolDeployer();
    }

    function setManager(address _manager) external onlyManager {
        manager = _manager;

        emit SetManager(_manager);
    }

    function setKeeper(address _keeper) external onlyManager {
        keeper = _keeper;

        emit SetKeeper(_keeper);
    }

    function requestLength(
        address _pool
    ) external view override returns (uint256) {
        return request[_pool].length;
    }

    function addRequest(
        address _owner,
        address _quoteToken,
        uint256 _liquidity,
        address _to,
        bytes calldata _data
    ) external override returns (uint256 index) {
        address pool = PoolAddress.computeAddress(poolDeployer, _quoteToken);
        if (msg.sender != pool) revert Forbidden(msg.sender);

        index = request[pool].length;
        request[pool].push(
            WithdrawalRequest({
                index: index,
                owner: _owner,
                quoteToken: _quoteToken,
                liquidity: _liquidity,
                to: _to,
                data: _data,
                callbackResult: ""
            })
        );

        emit AddRequest(
            pool,
            index,
            _owner,
            _quoteToken,
            _liquidity,
            _to,
            _data
        );
    }

    function updateCallbackResult(
        uint256 _index,
        string memory _result
    ) external override {
        WithdrawalRequest storage _request = request[msg.sender][_index];

        _request.callbackResult = _result;

        emit UpdateCallbackResult(msg.sender, _index, _result);
    }

    function _execute(address _pool) internal {
        uint256 withdrawingLiquidity = IPool(_pool).withdrawingLiquidity();
        uint256 _currentIndex = currentIndex[_pool];
        if (_currentIndex == request[_pool].length) {
            if (withdrawingLiquidity > 0) {
                IPool(_pool).availLiquidity();
            }
        } else {
            WithdrawalRequest memory _request = request[_pool][_currentIndex];
            uint256 availableLiquidity = IPool(_pool).availableLiquidity();
            if (
                availableLiquidity + withdrawingLiquidity >= _request.liquidity
            ) {
                IPool(_pool).burn(_request);
                currentIndex[_pool]++;

                emit FulfillRequest(_pool, _request.index);
            }
        }
    }

    function execute(address _pool) external override {
        _execute(_pool);
    }

    function checkUpkeep(
        bytes calldata /* checkData */
    )
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        IFactory _factory = IFactory(factory);
        uint256 poolLength = _factory.poolLength();
        address[] memory poolsToFulfill = new address[](poolLength);
        uint256 count;

        for (uint256 i = 0; i < poolLength; i++) {
            address pool = _factory.pools(i);
            uint256 withdrawingLiquidity = IPool(pool).withdrawingLiquidity();
            uint256 _currentIndex = currentIndex[pool];
            if (_currentIndex == request[pool].length) {
                if (withdrawingLiquidity > 0) {
                    poolsToFulfill[count] = pool;
                    count++;
                }
            } else {
                WithdrawalRequest memory _request = request[pool][
                    _currentIndex
                ];
                uint256 availableLiquidity = IPool(pool).availableLiquidity();
                if (
                    availableLiquidity + withdrawingLiquidity >=
                    _request.liquidity
                ) {
                    poolsToFulfill[count] = pool;
                    count++;
                }
            }
        }

        upkeepNeeded = count > 0;
        if (upkeepNeeded) {
            performData = abi.encode(poolsToFulfill, count);
        }
    }

    function performUpkeep(bytes calldata _performData) external override {
        uint256 usedGas = gasleft();
        (address[] memory poolsToFulfill, uint256 count) = abi.decode(
            _performData,
            (address[], uint256)
        );

        for (uint256 i = 0; i < count; i++) {
            address pool = poolsToFulfill[i];
            _execute(pool);
        }

        emit ProcessBatch(
            count,
            _performData,
            usedGas - gasleft(),
            tx.gasprice
        );
    }

    // Gelato compatible function
    function checker()
        external
        view
        returns (bool canExec, bytes memory execPayload)
    {
        IFactory _factory = IFactory(factory);
        uint256 poolLength = _factory.poolLength();
        address[] memory poolsToFulfill = new address[](poolLength);
        uint256 count;

        for (uint256 i = 0; i < poolLength; i++) {
            address pool = _factory.pools(i);
            uint256 withdrawingLiquidity = IPool(pool).withdrawingLiquidity();
            uint256 _currentIndex = currentIndex[pool];
            if (_currentIndex == request[pool].length) {
                if (withdrawingLiquidity > 0) {
                    poolsToFulfill[count] = pool;
                    count++;
                }
            } else {
                WithdrawalRequest memory _request = request[pool][
                    _currentIndex
                ];
                uint256 availableLiquidity = IPool(pool).availableLiquidity();
                if (
                    availableLiquidity + withdrawingLiquidity >=
                    _request.liquidity
                ) {
                    poolsToFulfill[count] = pool;
                    count++;
                }
            }
        }

        canExec = count > 0;
        if (canExec) {
            execPayload = abi.encodeWithSignature(
                "performUpkeep(bytes)",
                abi.encode(poolsToFulfill, count)
            );
        }
    }
}
