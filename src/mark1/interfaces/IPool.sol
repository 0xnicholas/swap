// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IPool {
    
    function swap(bytes calldata data) external returns (uint256 finalAmountOut);

    function flashSwap(bytes calldata data) external returns (uint256 finalAmountOut);

    function mint(bytes calldata data) external returns (uint256 liquidity);

    function burn(bytes calldata data) external returns (TokenAmount[] memory withdrawnAmounts);

    function burnSingle(bytes calldata data) external returns (uint256 amountOut);

    function poolIdentifier() external pure returns (bytes32);

    function getAssets() external view returns (address[] memory);

    function getAmountOut(bytes calldata data) external view returns (uint256 finalAmountOut);

    function getAmountIn(bytes calldata data) external view returns (uint256 finalAmountIn);
    
    event Swap(
        address indexed recipient,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );
    
    struct TokenAmount {
        address token;
        uint256 amount;
    }
}