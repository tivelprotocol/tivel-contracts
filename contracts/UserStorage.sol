// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

import "./interfaces/IUserStorage.sol";

contract UserStorage is IUserStorage { // 0x870B9af87B568B6C9a43a0Dd16788F8c57cF8524
    address public manager;
    mapping(address => bool) public operator;
    mapping(address => IUserStorage.User) private userInfo;

    mapping(bytes32 => address) public override referralCodeToAddress;

    error Forbidden(address sender);
    error BadLengths(uint256 length0, uint256 length1);
    error Generated();
    error InvalidReferralCode();
    error InvalidReferrerCode();

    event SetManager(address manager);
    event SetOperator(address user, bool isOperator);
    event GenerateReferralCode(
        address indexed user,
        bytes32 indexed referralCode
    );
    event UpdateReferrerCode(
        address indexed user,
        address indexed referrer,
        bytes32 indexed referrerCode
    );
    event UpdateMembership(address indexed user, uint256 membershipLevel);

    constructor() {
        manager = msg.sender;
    }

    modifier onlyManager() {
        if (msg.sender != manager) revert Forbidden(msg.sender);
        _;
    }

    modifier onlyOperator() {
        if (!operator[msg.sender]) revert Forbidden(msg.sender);
        _;
    }

    function setManager(address _manager) external onlyManager {
        manager = _manager;

        emit SetManager(_manager);
    }

    function setOperators(
        address[] memory _users,
        bool[] memory _isOperators
    ) external onlyManager {
        if (_users.length != _isOperators.length)
            revert BadLengths(_users.length, _isOperators.length);
        for (uint256 i = 0; i < _users.length; i++) {
            operator[_users[i]] = _isOperators[i];
            emit SetOperator(_users[i], _isOperators[i]);
        }
    }

    function getUserInfo(
        address _user
    ) external view override returns (IUserStorage.User memory) {
        return userInfo[_user];
    }

    function getReferrer(
        address _user
    ) external view override returns (address) {
        bytes32 referrerCode = userInfo[_user].referrerCode;
        return referralCodeToAddress[referrerCode];
    }

    function discountedFee(
        address _user,
        uint256 _fee
    ) external view override returns (uint256) {
        User memory user = userInfo[_user];
        uint256 factor = 4; // TODO: find the best factor
        uint256 discount = (_fee * user.membershipLevel) /
            (user.membershipLevel + factor);
        return _fee - discount;
    }

    function canUpdateDeadline(
        address _user
    ) external view override returns (bool) {
        // User memory user = userInfo[_user];
        // return user.membershipLevel > 0;
        return true;
    }

    function generateReferralCode(
        address _user,
        bytes32 _referralCode
    ) external override {
        if (msg.sender != _user) revert Forbidden(msg.sender);

        User storage user = userInfo[_user];
        if (user.id == address(0)) {
            user.id = _user;
        }
        if (user.referralCode != bytes32(0)) revert Generated();
        if (referralCodeToAddress[_referralCode] == address(0)) revert InvalidReferralCode();

        user.referralCode = _referralCode;
        referralCodeToAddress[_referralCode] = _user;

        emit GenerateReferralCode(_user, _referralCode);
    }

    function updateReferrerCode(
        address _user,
        bytes32 _referrerCode
    ) external override {
        if (msg.sender != _user) revert Forbidden(msg.sender);

        User storage user = userInfo[_user];
        if (user.id == address(0)) {
            user.id = _user;
        }
        address referrer = referralCodeToAddress[_referrerCode];
        if (referrer == address(0)) revert InvalidReferrerCode();

        user.referrerCode = _referrerCode;

        emit UpdateReferrerCode(_user, referrer, _referrerCode);
    }

    function updateMembership(
        address _user,
        uint256 _membershipLevel
    ) external override onlyOperator {
        User storage user = userInfo[_user];
        if (user.id == address(0)) {
            user.id = _user;
        }
        user.membershipLevel = _membershipLevel;

        emit UpdateMembership(_user, _membershipLevel);
    }
}
