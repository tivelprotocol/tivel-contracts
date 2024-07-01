// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

import "@chainlink/contracts/src/v0.8/AutomationCompatible.sol";
import "./interfaces/IPositionStorage.sol";

contract LiquidationMarker is AutomationCompatibleInterface {
    address public manager;
    address public keeper;
    address public positionStorageAddress;
    uint256 public batchSize;
    uint256 public monitorSize;
    uint256 public startIndex;

    error Forbidden(address sender);
    error TooHighValue(uint256 value, uint256 max);
    error TooLowValue(uint256 value, uint256 min);

    event SetManager(address manager);
    event SetKeeper(address keeper);
    event SetPositionStorage(address positionStorageAddress);
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
        address _positionStorageAddress,
        uint256 _batchSize,
        uint256 _monitorSize,
        uint256 _startIndex
    ) {
        manager = msg.sender;
        keeper = _keeper;
        positionStorageAddress = _positionStorageAddress;
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

    function setPositionStorage(
        address _positionStorageAddress
    ) external onlyManager {
        positionStorageAddress = _positionStorageAddress;

        emit SetPositionStorage(_positionStorageAddress);
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

    function checkUpkeep(
        bytes calldata /* checkData */
    )
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        IPositionStorage positionStorage = IPositionStorage(
            positionStorageAddress
        );
        bytes32[] memory batchPositionKeys = new bytes32[](batchSize);
        uint256 count;
        uint256 i;

        uint256 positionLength = positionStorage.positionLength();
        if (startIndex < positionLength) {
            for (uint256 j = startIndex; j < positionLength; j++) {
                bytes32 positionKey = positionStorage.positionKeys(j + 1);
                if (positionStorage.canLiquidationMark(positionKey)) {
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

    function performUpkeep(bytes calldata _performData) external override {
        IPositionStorage positionStorage = IPositionStorage(
            positionStorageAddress
        );
        uint256 usedGas = gasleft();
        (bytes32[] memory batchPositionKeys, uint256 count) = abi.decode(
            _performData,
            (bytes32[], uint256)
        );

        for (uint256 i = 0; i < count; i++) {
            positionStorage.liquidationMark(batchPositionKeys[i]);
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
            positionStorageAddress
        );
        bytes32[] memory batchPositionKeys = new bytes32[](batchSize);
        uint256 count;
        uint256 i;

        uint256 positionLength = positionStorage.positionLength();
        if (startIndex < positionLength) {
            for (uint256 j = startIndex; j < positionLength; j++) {
                bytes32 positionKey = positionStorage.positionKeys(j + 1);
                if (positionStorage.canLiquidationMark(positionKey)) {
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
