// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

import "@chainlink/contracts/src/v0.8/AutomationCompatible.sol";
import "./libraries/TransferHelper.sol";
import "./interfaces/ICloseCallback.sol";
import "./interfaces/IFactory.sol";
import "./interfaces/IDEXAggregator.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IPool.sol";

contract Monitor is AutomationCompatibleInterface, ICloseCallback {
    address public manager;
    address public keeper;
    address public factory;
    uint256 public batchSize;
    uint256 public monitorSize;
    uint256 public startIndex;

    error Forbidden(address sender);
    error TooHighValue(uint256 value, uint256 max);
    error TooLowValue(uint256 value, uint256 min);

    event SetManager(address manager);
    event SetKeeper(address keeper);
    event SetFactory(address factory);
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

        emit SetFactory(_factory);
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
        uint256 _amountOut,
        bytes calldata /* _data */
    ) external override {
        IDEXAggregator dexAggregator = IDEXAggregator(
            IFactory(factory).dexAggregator()
        );

        uint256 balance = IERC20(_tokenIn).balanceOf(address(this));
        TransferHelper.safeTransfer(_tokenIn, address(dexAggregator), balance);
        dexAggregator.swap(
            address(0),
            _tokenIn,
            _tokenOut,
            _amountOut,
            address(this)
        );
        TransferHelper.safeTransfer(_tokenOut, address(msg.sender), _amountOut);

        uint256 dust = IERC20(_tokenOut).balanceOf(address(this));
        if (dust > 0) {
            TransferHelper.safeTransfer(
                _tokenOut,
                address(dexAggregator),
                dust
            );
            dexAggregator.swap(
                address(0),
                _tokenOut,
                _tokenIn,
                0,
                address(msg.sender)
            );
        }
    }

    function checkUpkeep(
        bytes calldata /* checkData */
    )
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        IPositionStorage positionStorage = IPositionStorage(
            IFactory(factory).positionStorage()
        );
        bytes32[] memory batchPositionKeys = new bytes32[](batchSize);
        uint256 count;
        uint256 i;

        uint256 openingPositionLength = positionStorage.openingPositionLength();
        for (uint256 j = startIndex; j < openingPositionLength; j++) {
            bytes32 positionKey = positionStorage.openingPositionKey(j);
            if (positionStorage.canLiquidate(positionKey)) {
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

        upkeepNeeded = count > 0;
        if (upkeepNeeded) {
            performData = abi.encode(batchPositionKeys, count);
        }
    }

    function performUpkeep(bytes calldata _performData) external override {
        IPositionStorage positionStorage = IPositionStorage(
            IFactory(factory).positionStorage()
        );
        uint256 usedGas = gasleft();
        (bytes32[] memory batchPositionKeys, uint256 count) = abi.decode(
            _performData,
            (bytes32[], uint256)
        );

        for (uint256 i = 0; i < count; i++) {
            uint256 index = positionStorage.positionIndex(batchPositionKeys[i]);
            if (index > 0) {
                IPositionStorage.TradePosition memory pos = positionStorage
                    .position(index - 1);
                IPool(pos.pool).close(
                    IPositionStorage.CloseTradePositionParams({
                        positionKey: pos.positionKey,
                        data0: new bytes(0),
                        data1: new bytes(0),
                        closer: address(this)
                    })
                );
            }
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
        IPositionStorage positionStorage = IPositionStorage(
            IFactory(factory).positionStorage()
        );
        bytes32[] memory batchPositionKeys = new bytes32[](batchSize);
        uint256 count;
        uint256 i;

        uint256 openingPositionLength = positionStorage.openingPositionLength();
        for (uint256 j = startIndex; j < openingPositionLength; j++) {
            bytes32 positionKey = positionStorage.openingPositionKey(j);
            if (positionStorage.canLiquidate(positionKey)) {
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

        canExec = count > 0;
        if (canExec) {
            execPayload = abi.encodeWithSignature(
                "performUpkeep(bytes)",
                abi.encode(batchPositionKeys, count)
            );
        }
    }
}
