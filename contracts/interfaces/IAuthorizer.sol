// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

interface IAuthorizer {
    /**
     * @dev Returns true if `account` can perform the action described by `actionId` in the contract `where`.
     */
    function canPerform(bytes32 actionId, address account, address where) external view returns (bool);
}
