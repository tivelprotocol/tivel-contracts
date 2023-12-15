// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;
pragma abicoder v2;

contract Multicall {
    struct Call {
        address target;
        bytes callData;
    }
    struct Result {
        bool success;
        bytes returnData;
    }

    error CallFailed1();
    error CallFailed2();

    function aggregate(
        Call[] memory _calls
    ) public returns (uint256 blockNumber, bytes[] memory returnData) {
        blockNumber = block.number;
        returnData = new bytes[](_calls.length);
        for (uint256 i = 0; i < _calls.length; i++) {
            (bool success, bytes memory ret) = _calls[i].target.call(
                _calls[i].callData
            );
            if (!success) revert CallFailed1();
            returnData[i] = ret;
        }
    }

    function blockAndAggregate(
        Call[] memory _calls
    )
        public
        returns (
            uint256 blockNumber,
            bytes32 blockHash,
            Result[] memory returnData
        )
    {
        (blockNumber, blockHash, returnData) = tryBlockAndAggregate(
            true,
            _calls
        );
    }

    function getBlockHash(
        uint256 _blockNumber
    ) public view returns (bytes32 blockHash) {
        blockHash = blockhash(_blockNumber);
    }

    function getBlockNumber() public view returns (uint256 blockNumber) {
        blockNumber = block.number;
    }

    function getCurrentBlockCoinbase() public view returns (address coinbase) {
        coinbase = block.coinbase;
    }

    function getCurrentBlockDifficulty()
        public
        view
        returns (uint256 difficulty)
    {
        difficulty = block.difficulty;
    }

    function getCurrentBlockGasLimit() public view returns (uint256 gaslimit) {
        gaslimit = block.gaslimit;
    }

    function getCurrentBlockTimestamp()
        public
        view
        returns (uint256 timestamp)
    {
        timestamp = block.timestamp;
    }

    function getEthBalance(
        address _addr
    ) public view returns (uint256 balance) {
        balance = _addr.balance;
    }

    function getLastBlockHash() public view returns (bytes32 blockHash) {
        blockHash = blockhash(block.number - 1);
    }

    function tryAggregate(
        bool _requireSuccess,
        Call[] memory _calls
    ) public returns (Result[] memory returnData) {
        returnData = new Result[](_calls.length);
        for (uint256 i = 0; i < _calls.length; i++) {
            (bool success, bytes memory ret) = _calls[i].target.call(
                _calls[i].callData
            );

            if (_requireSuccess && !success) {
                revert CallFailed2();
            }

            returnData[i] = Result(success, ret);
        }
    }

    function tryBlockAndAggregate(
        bool _requireSuccess,
        Call[] memory _calls
    )
        public
        returns (
            uint256 blockNumber,
            bytes32 blockHash,
            Result[] memory returnData
        )
    {
        blockNumber = block.number;
        blockHash = blockhash(block.number);
        returnData = tryAggregate(_requireSuccess, _calls);
    }
}
