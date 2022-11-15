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

## Milestone 2 Second Swap
本节内容对应分支 milestone2。

在第一节中，我们计算并硬编码了所有数量。在本节中，将使其变为动态，进行第二次互换，即相反方向的互换：卖出 ETH 买入 USDC。并对合约进行改进：
1. 使用第三方库在 Solidity 中实现数学计算；
2. 让用户选择交换方向，并且使pool合约支持双向交换；
3. 更新 UI 以支持双向交换和输出量计算，实现另一个合约 Quoter。

Solidity 中的数学计算难在：只支持有符号整型和无符号整型、需要让高级计算过程(指数、对数、平方根)尽可能高效以节约 gas、防止上溢/下溢。我们将使用第三方数学库来实现高级数学运算：[PRBMath](https://github.com/paulrberg/prb-math) 和 [TickMath](https://github.com/Uniswap/v3-core/blob/main/contracts/libraries/TickMath.sol)。前者是一个高级定点数学算法库，我们将使用 `mulDiv` 处理整数乘除时的溢出，后者来自 Uniswap V3 官方项目，实现了 `getSqrtRatioAtTick` 和 `getTickAtSqrtRatio` 函数，用于 sqrt_P 和 tick 之间的转换。
