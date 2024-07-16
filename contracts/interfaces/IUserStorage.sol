// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

interface IUserStorage {
    struct User {
        address id;
        bytes32 referralCode;
        bytes32 referrerCode;
        uint256 membershipLevel;
    }

    function getUserInfo(address) external view returns (User memory);

    function getReferrer(address) external view returns (address);

    function referralCodeToAddress(bytes32) external view returns (address);

    function discountedFee(
        address _user,
        uint256 _fee
    ) external view returns (uint256);

    function canUpdateDeadline(address) external view returns (bool);

    function generateReferralCode(
        address _user,
        bytes32 _referralCode
    ) external;

    function updateReferrerCode(address _user, bytes32 _referrerCode) external;

    function updateMembership(address _user, uint256 _membershipLevel) external;
}
