// SPDX-License-Identifier: UnLicense
pragma solidity ^0.8.27;

library Math {

    uint8 internal constant RESOLUTION = 96;
    uint256 internal constant Q96 = 2**96;

    /// @notice Calculates amount0 delta between two prices
    function calcAmount0Delta(
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96,
        uint128 liquidity
    ) internal pure returns (uint256 amount0) {
        
    }

}