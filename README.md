# swap-experiment
> DeFi中各类swap协议合约的实践 src/

- `xp1`: 经典constant-product及stable交换池swap实现. (refer to Sushiswap)
    - 模板化部署
    - 去除了sushi的bento
- `xp2`: 带有ticks&ranges的swap (refer to uniswap v3)
- `xp3`: 基于v4 实现了一些常用的hooks.
- `xpy`: 使用orderbook的swap (refer to dYdX)
- `xpx`: intent-centric swap (refer to Cowswap & UniswapX)

开发工具: foundry