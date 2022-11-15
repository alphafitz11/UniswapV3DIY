// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./Math.sol";

library SwapMath {
    // 计算一个价格范围内的swap数量并考虑可用流动性
    // 返回新的当前价格以及输入和输出代币数量
    function computeSwapStep(
        uint160 sqrtPriceCurrentX96,
        uint160 sqrtPriceTargetX96,
        uint128 liquidity,
        uint256 amountRemaining
    ) internal pure returns (
        uint160 sqrtPriceNextX96,
        uint256 amountIn,
        uint256 amountOut
    )
    {
        bool zeroForOne = sqrtPriceCurrentX96 >= sqrtPriceTargetX96;

        sqrtPriceNextX96 = Math.getNextSqrtPriceFromInput(
            sqrtPriceCurrentX96,
            liquidity,
            amountRemaining,
            zeroForOne
        );

        amountIn = Math.calcAmount0Delta(
            sqrtPriceCurrentX96,
            sqrtPriceNextX96,
            liquidity
        );

        amountOut = Math.calcAmount1Delta(
            sqrtPriceCurrentX96,
            sqrtPriceNextX96,
            liquidity
        );

        if (!zeroForOne) {
            (amountIn, amountOut) = (amountOut, amountIn);
        }
    }
}