// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import './ipool/IUniswapV3PoolImmutables.sol';
import './ipool/IUniswapV3PoolState.sol';
import './ipool/IUniswapV3PoolDerivedState.sol';
import './ipool/IUniswapV3PoolActions.sol';
import './ipool/IUniswapV3PoolOwnerActions.sol';
import './ipool/IUniswapV3PoolEvents.sol';

/// @title The interface for a Uniswap V3 Pool
/// @notice A Uniswap pool facilitates swapping and automated market making between any two assets that strictly conform
/// to the ERC20 specification
/// @dev The pool interface is broken up into many smaller pieces
interface IUniswapV3Pool is
    IUniswapV3PoolImmutables,
    IUniswapV3PoolState,
    IUniswapV3PoolDerivedState,
    IUniswapV3PoolActions,
    IUniswapV3PoolOwnerActions,
    IUniswapV3PoolEvents
{

}
