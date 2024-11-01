// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Pool deployer interface.
interface IDeployer {
    function poolFee() external view returns (uint256);

    function poolFeeTo() external view returns (address);

    function vault() external view returns (address);

    function migrator() external view returns (address);

    function pools(address pool) external view returns (bool);

    function deployPool(address factory, bytes calldata deployData) external returns (address);
    
}