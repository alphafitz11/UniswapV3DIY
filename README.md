# UniswapV3DIY

本项目遵循《[Uniswap V3 Development Book](https://uniswapv3book.com/)》进行构建。

《[Uniswap V3 Development Book](https://uniswapv3book.com/)》可以指导开发者使用 [Foundry](https://github.com/foundry-rs/foundry) 从头构建一个 Uniswap V3 项目。

本项目会涉及的内容：
- 智能合约开发 (Solidity)
- 合约测试和部署 (Foundry 中的 Forge 和 Anvil)
- 去中心化交易所的设计和数学
- 用于交易所的前端应用程序 (React 和 MetaMask)

## Milestone 1 First Swap
本节内容对应分支 milestone1。

本节中，我们将会构建一个可以从用户获得流动性并在价格范围内进行交换(swap)的池合约。为了让合约尽可能简单，本节将仅在一个价格范围内提供流动性，并且只允许在一个方向进行交换。本节中我们还将手动计算价格和流动性，这些计算过程会在后面章节中在合约中实现。本节的目标是使用预先计算和硬编码的值进行第一次交换。

本节假设在 ETH/USDC 池中，使用 USDC 兑换 ETH，并且池中初始价格为 ETH/USDC=5000。因此在设定流动性时，假设价格的下限和上限分别是 4545 和 5500。根据 Uniswap V3 中 price-tick 的计算公式，当前tick: t_c = 85176，下限tick: t_l = 84222，上限tick: t_u = 86129。使用 Python 实现的计算方法见 [unimath.py](./unimath.py)。需要注意，Uniswap 使用 Q64.96 数字来存储 sqrt_P，即整数部分64位、小数部分96位的定点数。将浮点数计算为 Q64.96 只需要将其乘以 2^96。对于代币数量，我们存储任意数量，这里假设存入 1 ETH 和 5000 USDC。

池中的初始流动性 L 可以根据 x/y 代币数量、假设的当前价格和价格区间的上限/下限计算得到([unimath.py](./unimath.py) 中的 liquidity0 和 liquidity1)。相应地，为了获得流动性 L 需要存入的 x/y 代币数量也可以根据 L、假设的当前价格和价格区间的上限/下限计算得到([unimath.py](./unimath.py) 中的 calc_amount0 和 calc_amount1)。
