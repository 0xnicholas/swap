// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

//import {Owned as Ownable} from "../../../lib/solmate/auth/Owned.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import {IPoolFactory} from "../interfaces/IPoolFactory.sol";

error InvalidPoolFee();
error ZeroAddress();
error NotWhitelisted();

contract Deployer is Ownable {
    event DeployPool(address indexed factory, address indexed pool, bytes deployData);
    event AddToWhitelist(address indexed factory);
    event RemoveFromWhitelist(address indexed factory);
    event PoolFeeUpdated(uint256 indexed poolFee);
    event PoolFeeToUpdated(address indexed poolFeeTo);

    uint256 public poolFee;
    address public poolFeeTo;
    address public immutable vault;

    uint256 internal constant MAX_FEE = 10000; // @dev 100%.

    mapping(address => bool) public pools;
    mapping(address => bool) public whitelistedFactories;

    constructor(
        uint256 _poolFee,
        address _poolFeeTo,
        address _vault
    ) {
        if (_poolFee > MAX_FEE) revert InvalidPoolFee();
        if (_poolFeeTo == address(0)) revert ZeroAddress();
        if (_vault == address(0)) revert ZeroAddress();

        poolFee = _poolFee;
        poolFeeTo = _poolFeeTo;
        vault = _vault;
    }

    function deployPool(address _factory, bytes calldata _deployData) external returns (address pool) {
        if (!whitelistedFactories[_factory]) revert NotWhitelisted();
        pool = IPoolFactory(_factory).deployPool(_deployData);
        pools[pool] = true;
        emit DeployPool(_factory, pool, _deployData);
    }

    function addToWhitelist(address _factory) external onlyOwner {
        whitelistedFactories[_factory] = true;
        emit AddToWhitelist(_factory);
    }

    function removeFromWhitelist(address _factory) external onlyOwner {
        whitelistedFactories[_factory] = false;
        emit RemoveFromWhitelist(_factory);
    }

    function setPoolFee(uint256 _poolFee) external onlyOwner {
        if (_poolFee > MAX_FEE) revert InvalidPoolFee();
        poolFee = _poolFee;
        emit PoolFeeUpdated(_poolFee);
    }

    function setPoolFeeTo(address _poolFeeTo) external onlyOwner {
        poolFeeTo = _poolFeeTo;
        emit PoolFeeToUpdated(_poolFeeTo);
    }
}