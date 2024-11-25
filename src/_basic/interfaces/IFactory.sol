// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.27;

interface IFactory {
    function pairs(address, address) external pure returns (address);

    function createPair(address, address) external returns (address);
}