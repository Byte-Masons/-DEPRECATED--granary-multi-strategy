// SPDX-License-Identifier: agpl-3.0

pragma solidity ^0.8.0;

interface IERC4626Events {
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed sender,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );
}
