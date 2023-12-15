// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

import "./BlockTimestamp.sol";

abstract contract PeripheryValidation is BlockTimestamp {
    error TransactionTooOld();

    modifier checkDeadline(uint256 _deadline) {
        if (_blockTimestamp() > _deadline) revert TransactionTooOld();
        _;
    }
}
