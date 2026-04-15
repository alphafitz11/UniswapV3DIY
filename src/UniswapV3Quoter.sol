// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./UniswapV3Pool.sol";
import "./interfaces/IUniswapV3Pool.sol";

contract UniswapV3Quoter {
    // 在用户真正兑换之前，根据输入的代币数量计算能够得到的代币数量
    // 为了计算swap数量，会初始化一个真正的swap过程，并在回调函数中中断，来获取pool合约计算的数量
    
    struct QuoteParams {
        address pool;
        uint256 amountIn;
        bool zeroForOne;
    }

    // quote函数模拟一个swap的过程，计算swap出的数量，适用于任何pool
    // 调用的pool.callback函数预计会revert，但quote函数不会revert
    // 在回调函数中主动实现revert会保证quote不会修改pool合约的状态，但是从客户端(Ethers.js和Web3.js等)调用quote将会触发一个交易
    // 为了解决这个问题，我们需要强制库进行静态调用(static call)
    function quote(QuoteParams memory params)
        public
        returns (
            uint256 amountOut,
            uint160 sqrtPriceX96After,
            int24 tickAfter
        )
    {
        try
            UniswapV3Pool(params.pool).swap(
                address(this),
                params.zeroForOne,
                params.amountIn,
                abi.encode(params.pool)
            )
        {} catch (bytes memory reason) {
            return abi.decode(reason, (uint256, uint160, int24));
        }
    }

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes memory data
    ) external view {
        address pool = abi.decode(data, (address));

        // 兑换后的代币数量
        uint256 amountOut = amount0Delta > 0
            ? uint256(-amount1Delta)
            : uint256(-amount0Delta);

        // 兑换后的价格
        (uint160 sqrtPriceX96After, int24 tickAfter) = IUniswapV3Pool(pool).slot0();

        // 在内联汇编(Yul)中保存这些值并revert
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, amountOut)
            mstore(add(ptr, 0x20), sqrtPriceX96After)
            mstore(add(ptr, 0x40), tickAfter)
            revert(ptr, 96)
        }
    }
}