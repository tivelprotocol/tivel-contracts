// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

contract Lockable {
    uint256 private unlocked = 1;

    error Locked();

    modifier lock() {
        if (unlocked != 1) revert Locked();
        unlocked = 0;
        _;
        unlocked = 1;
    }
}
