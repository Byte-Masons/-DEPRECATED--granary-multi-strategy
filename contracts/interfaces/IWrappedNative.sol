// SPDX-License-Identifier: agpl-3.0

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IWrappedNative is IERC20 {
    function ERR_INVALID_ZERO_VALUE() external view returns (uint256);

    function ERR_NO_ERROR() external view returns (uint256);

    function deposit() external payable returns (uint256);

    function withdraw(uint256 amount) external returns (uint256);
}
