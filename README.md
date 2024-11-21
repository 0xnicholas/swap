# swap-experiment
> DeFi中各类swap协议合约的实践 -@nicholaslico

- `xp1`: 经典constant-product及stable交换池swap实现. (refer to Sushiswap)
    - 模板化部署
    - 去除了sushi的bento

- `xp2`: 带有ticks&range的swap (refer to uniswap v3/v4)
    - 使用v4的Singleton模式取代Factory/Pool. (Factory模式代码保留)
    - 使用v3的固定的fee/tick spacing，而不是v4的动态费率。（0.01%/2, 0.05%/10, 0.3%/60, 1%/200）
    - 将LP token(NFT)修改为了ERC20，由于同一个池的多个流动性并不能等价的问题，通过veToken的机制解决(liquidity mining, refer to Curve)。
    - 调整了`libraries`.
    - 未实现`Hooks`.

- `xp3-hooks`: 基于v4 实现了一些常用的Hooks应用.
    - stop-loss orders with v4
    - orderbbok, limit order hook for v4 with intent-based orderbook.

- `xpy`: 使用orderbook的swap (refer to dYdX)
- `xpx`: intent-centric swap (refer to Cowswap & UniswapX)

> 开发工具: foundry/hardhat