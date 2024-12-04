// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

interface ISwapCallback {
    function swapCallback(int256 amount0, int256 amount1, bytes calldata data) external;
}