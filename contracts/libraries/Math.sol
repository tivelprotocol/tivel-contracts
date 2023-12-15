// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

// a library for performing various math operations

library Math {
    function min(uint _x, uint _y) internal pure returns (uint z) {
        z = _x < _y ? _x : _y;
    }

    // babylonian method (https://en.wikipedia.org/wiki/Methods_of_computing_square_roots#Babylonian_method)
    function sqrt(uint _y) internal pure returns (uint z) {
        if (_y > 3) {
            z = _y;
            uint x = _y / 2 + 1;
            while (x < z) {
                z = x;
                x = (_y / x + x) / 2;
            }
        } else if (_y != 0) {
            z = 1;
        }
    }
}
