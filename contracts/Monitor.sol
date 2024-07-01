// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

import "@chainlink/contracts/src/v0.8/AutomationCompatible.sol";
import "./libraries/TransferHelper.sol";
import "./interfaces/ICloseCallback.sol";
import "./interfaces/IFactory.sol";
import "./interfaces/IDEXAggregator.sol";
import "./interfaces/IMetaAggregator.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IPool.sol";

contract Monitor is AutomationCompatibleInterface, ICloseCallback {
    address public manager;
    address public keeper;
    address public factory;
    address public positionStorage;
    address public metaAggregator;
    uint256 public batchSize;
    uint256 public monitorSize;
    uint256 public startIndex;

    error Forbidden(address sender);
    error TooHighValue(uint256 value, uint256 max);
    error TooLowValue(uint256 value, uint256 min);
    error InsufficientOutput();

    event SetManager(address manager);
    event SetKeeper(address keeper);
    event SetFactory(address factory);
    event SetMetaAggregator(address metaAggregator);
    event SetBatchSize(uint256 batchSize);
    event SetMonitorSize(uint256 monitorSize);
    event SetStartIndex(uint256 startIndex);
    event ProcessBatch(
        uint256 count,
        bytes performData,
        uint256 usedGas,
        uint256 gasPrice
    );

    constructor(
        address _keeper,
        address _factory,
        uint256 _batchSize,
        uint256 _monitorSize,
        uint256 _startIndex
    ) {
        manager = msg.sender;
        keeper = _keeper;
        factory = _factory;
        positionStorage = IFactory(_factory).positionStorage();
        batchSize = _batchSize;
        monitorSize = _monitorSize;
        startIndex = _startIndex;
    }

    modifier onlyManager() {
        if (msg.sender != manager) revert Forbidden(msg.sender);
        _;
    }

    function setManager(address _manager) external onlyManager {
        manager = _manager;

        emit SetManager(_manager);
    }

    function setKeeper(address _keeper) external onlyManager {
        keeper = _keeper;

        emit SetKeeper(_keeper);
    }

    function setFactory(address _factory) external onlyManager {
        factory = _factory;
        positionStorage = IFactory(_factory).positionStorage();

        emit SetFactory(_factory);
    }

    function setMetaAggregator(
        address _newMetaAggregator
    ) external onlyManager {
        metaAggregator = _newMetaAggregator;

        emit SetMetaAggregator(_newMetaAggregator);
    }

    function setBatchSize(uint256 _batchSize) external onlyManager {
        if (_batchSize > monitorSize)
            revert TooHighValue(_batchSize, monitorSize);
        batchSize = _batchSize;

        emit SetBatchSize(_batchSize);
    }

    function setMonitorSize(uint256 _monitorSize) external onlyManager {
        if (_monitorSize < batchSize)
            revert TooLowValue(_monitorSize, batchSize);
        monitorSize = _monitorSize;

        emit SetMonitorSize(_monitorSize);
    }

    function setStartIndex(uint256 _startIndex) external onlyManager {
        startIndex = _startIndex;

        emit SetStartIndex(_startIndex);
    }

    function closeCallback(
        address _tokenIn,
        address _tokenOut,
        uint256 _minAmountOut,
        bytes calldata _data
    ) external override {
        uint256 balance = IERC20(_tokenIn).balanceOf(address(this));
        uint256 amountOut;
        if (metaAggregator == address(0) || _data.length == 0) {
            IFactory _factory = IFactory(factory);
            IDEXAggregator aggregator = IDEXAggregator(
                _factory.dexAggregator()
            );

            TransferHelper.safeTransfer(_tokenIn, address(aggregator), balance);
            (amountOut, ) = aggregator.swap(
                address(0),
                _tokenIn,
                _tokenOut,
                _minAmountOut,
                address(this)
            );
        } else {
            IMetaAggregator aggregator = IMetaAggregator(metaAggregator);

            TransferHelper.safeTransfer(_tokenIn, address(aggregator), balance);
            amountOut = aggregator.swap(
                _tokenIn,
                _tokenOut,
                _minAmountOut,
                address(this),
                _data
            );
        }

        if (amountOut < _minAmountOut) revert InsufficientOutput();
        TransferHelper.safeTransfer(_tokenOut, address(msg.sender), amountOut);
    }

    function checkUpkeep(
        bytes calldata /* checkData */
    )
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        IPositionStorage _positionStorage = IPositionStorage(positionStorage);
        bytes32[] memory batchPositionKeys = new bytes32[](batchSize);
        uint256 count;
        uint256 i;

        uint256 positionLength = _positionStorage.positionLength();
        if (startIndex < positionLength) {
            for (uint256 j = startIndex; j < positionLength; j++) {
                bytes32 positionKey = _positionStorage.positionKeys(j + 1);
                if (_positionStorage.canLiquidate(positionKey)) {
                    batchPositionKeys[count] = positionKey;
                    count++;
                }
                i++;
                if (i == monitorSize) {
                    break;
                }
                if (count == batchSize) {
                    break;
                }
            }
        }

        upkeepNeeded = count > 0;
        if (upkeepNeeded) {
            performData = abi.encode(batchPositionKeys, count);
        }
    }

    function _close(
        bytes32 _positionKey,
        bytes memory _data0,
        bytes memory _data1,
        address _closer
    ) internal {
        IPositionStorage.TradePosition memory pos = IPositionStorage(
            positionStorage
        ).position(_positionKey);
        IPool(pos.pool).close(
            IPositionStorage.CloseTradePositionParams({
                positionKey: pos.positionKey,
                data0: _data0,
                data1: _data1,
                closer: _closer
            })
        );
    }

    // called by offchain monitor which uses meta aggregator
    function close(
        bytes32 _positionKey,
        bytes memory _data0,
        bytes memory _data1
    ) external {
        _close(_positionKey, _data0, _data1, msg.sender);
    }

    function performUpkeep(bytes calldata _performData) external override {
        uint256 usedGas = gasleft();
        (bytes32[] memory batchPositionKeys, uint256 count) = abi.decode(
            _performData,
            (bytes32[], uint256)
        );

        for (uint256 i = 0; i < count; i++) {
            _close(
                batchPositionKeys[i],
                new bytes(0),
                new bytes(0),
                address(this)
            );
        }

        emit ProcessBatch(
            count,
            _performData,
            usedGas - gasleft(),
            tx.gasprice
        );
    }

    function performUpkeepWithSwapData(bytes calldata _performData) external {
        uint256 usedGas = gasleft();
        (bytes32[] memory batchPositionKeys, bytes[] memory data0s, bytes[] memory data1s, uint256 count) = abi.decode(
            _performData,
            (bytes32[], bytes[], bytes[], uint256)
        );

        for (uint256 i = 0; i < count; i++) {
            _close(
                batchPositionKeys[i],
                data0s[i],
                data1s[i],
                address(this)
            );
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
        IPositionStorage _positionStorage = IPositionStorage(positionStorage);
        bytes32[] memory batchPositionKeys = new bytes32[](batchSize);
        uint256 count;
        uint256 i;

        uint256 positionLength = _positionStorage.positionLength();
        if (startIndex < positionLength) {
            for (uint256 j = startIndex; j < positionLength; j++) {
                bytes32 positionKey = _positionStorage.positionKeys(j + 1);
                if (_positionStorage.canLiquidate(positionKey)) {
                    batchPositionKeys[count] = positionKey;
                    count++;
                }
                i++;
                if (i == monitorSize) {
                    break;
                }
                if (count == batchSize) {
                    break;
                }
            }
        }

        canExec = count > 0;
        if (canExec) {
            execPayload = abi.encodeWithSignature(
                "performUpkeep(bytes)",
                abi.encode(batchPositionKeys, count)
            );
        }
    }
}
