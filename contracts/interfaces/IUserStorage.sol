// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

interface IUserStorage {
    struct User {
        address id;
        address ref;
        uint256 membershipLevel;
    }

    function getUserInfo(address) external view returns (User memory);

    function discountedFee(
        address _user,
        uint256 _fee
    ) external view returns (uint256);

    function canUpdateDeadline(address) external view returns (bool);

    function updateRef(address _user, address _ref) external;

    function updateMembership(address _user, uint256 _membershipLevel) external;
}
