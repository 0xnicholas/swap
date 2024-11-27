# Swap Experiment
> DeFi中各类swap协议合约的实践 -@nicholaslico

- [`xp1`](src/xp1/): 经典constant-product及stable交换池swap实现. (refer to Sushiswap)
    - 模板化部署
    - 去除了sushi的bento(可能会换成[vault-evo](https://github.com/0xnicholas/vault-evo))

- [`xp2`](src/xp2/): 带有ticks&range的swap (refer to uniswap v3/v4)
    - 使用v4的Singleton模式取代Factory/Pool. (Factory模式代码保留-未测试)
    - 使用v3的固定的fee/tick spacing，而不是v4的动态费率。（0.01%/2, 0.05%/10, 0.3%/60, 1%/200）
    - 将LP token(NFT)修改为了ERC20，由于同一个池的多个流动性并不能等价的问题，通过veToken的机制解决(liquidity mining, refer to Curve)。
    - 调整了`libraries`.
    - 未实现`Hooks`.

- [`xp3-hooks`](src/xp3-hooks/): 基于v4 实现了一些常用的Hooks应用.
    - stop-loss orders with v4
    - orderbbok, limit order hook for v4 with intent-based orderbook.

- [`xpy`](src/xpy/): 使用orderbook的swap, 链下匹配链上结算 (refer to dYdX)
- [`xpx`](src/xpx/): intent-centric swap (refer to Cowswap & UniswapX)

以及 [`_basic`](src/_basic/), swap基础; 相关计算示例[`swapmath.py`](_math/swapmath.py).

> 开发工具: foundry/hardhat(test), viem