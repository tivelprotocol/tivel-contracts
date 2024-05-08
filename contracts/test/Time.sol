// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

contract Time {
    function timestamp() external view returns (uint256) {
        return block.timestamp;
    }
}
