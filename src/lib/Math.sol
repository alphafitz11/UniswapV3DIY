// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./FixedPoint96.sol";
import "prb-math/PRBMath.sol";

library Math {
    // 根据流动性L和价格计算代币x数量差，同unimath.py中的calc_amount0函数
    function calcAmount0Delta(
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96,
        uint128 liquidity
    ) internal pure returns (uint256 amount0) {
        if (sqrtPriceAX96 > sqrtPriceBX96) {
            (sqrtPriceAX96, sqrtPriceBX96) = (sqrtPriceBX96, sqrtPriceAX96);
        }

        require(sqrtPriceAX96 > 0);

        amount0 = divRoundingUp(
            // 使用mulDivRoundingUp在一次操作中进行乘法和除法
            mulDivRoundingUp(
                (uint256(liquidity) << FixedPoint96.RESOLUTION),
                (sqrtPriceBX96 - sqrtPriceAX96),
                sqrtPriceBX96
            ),
            sqrtPriceAX96
        );
    }

    // 根据流动性L和价格计算代币y数量差，同unimath.py中的calc_amount1函数
    function calcAmount1Delta(
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96,
        uint128 liquidity
    ) internal pure returns (uint256 amount1) {
        if (sqrtPriceAX96 > sqrtPriceBX96) {
            (sqrtPriceAX96, sqrtPriceBX96) = (sqrtPriceBX96, sqrtPriceAX96);
        }

        amount1 = mulDivRoundingUp(
                liquidity,
                (sqrtPriceBX96 - sqrtPriceAX96),
                FixedPoint96.Q96
            );
    }

    // 在给定当前价格和流动性的情况下，计算兑换指定数量的输入token之后的价格
    // 处理双向兑换，并在单独的函数中实现
    function getNextSqrtPriceFromInput(
        uint160 sqrtPriceX96,
        uint128 liquidity,
        uint256 amountIn,
        bool zeroForOne
    ) internal pure returns (uint160 sqrtPriceNextX96) {
        sqrtPriceNextX96 = zeroForOne
            ? getNextSqrtPriceFromAmount0RoundingUp(
                sqrtPriceX96,
                liquidity,
                amountIn
            )
            : getNextSqrtPriceFromAmount1RoundingDown(
                sqrtPriceX96,
                liquidity,
                amountIn
            );
    }

    function getNextSqrtPriceFromAmount0RoundingUp(
        uint160 sqrtPriceX96,
        uint128 liquidity,
        uint256 amountIn
    ) internal pure returns (uint160) {
        uint256 numerator = uint256(liquidity) << FixedPoint96.RESOLUTION;
        uint256 product = amountIn * sqrtPriceX96;

        if (product / amountIn == sqrtPriceX96) {
            uint256 denominator = numerator + product;
            if (denominator >= numerator) {
                // 最精确的公式，但可能在amountIn*sqrtPriceX96时发生溢出
                return
                    uint160(
                        mulDivRoundingUp(numerator, sqrtPriceX96, denominator)
                    );
            }
        }

        // 发生溢出时的代替公式，精度更低
        return
            uint160(
                divRoundingUp(numerator, (numerator / sqrtPriceX96) + amountIn)
            );
    }

    function getNextSqrtPriceFromAmount1RoundingDown(
        uint160 sqrtPriceX96,
        uint128 liquidity,
        uint256 amountIn
    ) internal pure returns (uint160) {
        return 
            sqrtPriceX96 +
            uint160((amountIn << FixedPoint96.RESOLUTION) / liquidity);
    }

    // 在一次操作中进行乘法和除法，此函数基于 PRBMath 中的 mulDiv
    function mulDivRoundingUp(
        uint256 a,
        uint256 b,
        uint256 denominator
    ) internal pure returns (uint256 result) {
        result = PRBMath.mulDiv(a, b, denominator);
        if (mulmod(a, b, denominator) > 0) {
            require(result < type(uint256).max);
            result++;
        }
    }

    function divRoundingUp(uint256 numerator, uint256 denominator)
        internal
        pure
        returns (uint256 result)
    {
        assembly {
            result := add(
                div(numerator, denominator),
                gt(mod(numerator, denominator), 0)
            )
        }
    }
}