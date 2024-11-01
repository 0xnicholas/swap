// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./IDeployer.sol";

interface IPoolFactory {

    function getDeployData() external view returns (bytes memory, IDeployer);
}