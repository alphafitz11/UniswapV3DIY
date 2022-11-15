// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./interfaces/IERC20.sol";
import "./interfaces/IUniswapV3MintCallback.sol";
import "./interfaces/IUniswapV3SwapCallback.sol";

import "./lib/Position.sol";
import "./lib/Tick.sol";
import "./lib/TickBitmap.sol";
import "./lib/TickMath.sol";
import "./lib/Math.sol";
import "./lib/SwapMath.sol";
import "./lib/FixedPoint96.sol";

contract UniswapV3Pool {
    using Tick for mapping(int24 => Tick.Info);
    // 键是(owner, lowerTick, upperTick)的哈希
    using Position for mapping(bytes32 => Position.Info);
    using Position for Position.Info;
    using TickBitmap for mapping(int16 => uint256);

    error InsufficientInputAmount();
    error InvalidTickRange();
    error ZeroLiquidity();

    event Mint(
        address sender,
        address indexed owner,
        int24 indexed tickLower,
        int24 indexed tickUpper,
        uint128 amount,
        uint256 amount0,
        uint256 amount1
    );

    event Swap(
        address indexed sender,
        address indexed recipient,
        int256 amount0,
        int256 amount1,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        int24 tick
    );


    int24 internal constant MIN_TICK = -887272;
    int24 internal constant MAX_TICK = -MIN_TICK;

    // 池代币地址，不可变
    address public immutable token0;
    address public immutable token1;

    // 同时读取的打包变量
    struct Slot0 {
        // 当前的sqrt_P
        uint160 sqrtPriceX96;
        // 当前的tick
        int24 tick;
    }

    struct CallbackData {
        address token0;
        address token1;
        address payer;
    }

    // 当前兑换的状态
    struct SwapState {
        uint256 amountSpecifiedRemaining;  // 池需要购买的剩余代币数量，为0表示完成swap
        uint256 amountCalculated;  // 合约计算的兑换出的数量
        uint160 sqrtPriceX96;  // swap完成后的新的当前价格
        int24 tick;  // swap完成后的新的当前tick
    }

    // 当前兑换步骤的状态，跟踪一个"order filling"的一次迭代的状态
    struct StepState {
        uint160 sqrtPriceStartX96;  // 迭代开始的价格
        int24 nextTick;  // 将要为swap提供流动性的下一个初始化tick
        uint160 sqrtPriceNextX96;  // 下一个tick的价格
        uint256 amountIn;  // 当前迭代的流动性可以提供的数量
        uint256 amountOut;  // 当前迭代的流动性可以提供的数量
    }

    Slot0 public slot0;

    // 流动性数量 L
    uint128 public liquidity;

    // Tick信息
    mapping(int24 => Tick.Info) public ticks;
    // Position信息
    mapping(bytes32 => Position.Info) public positions;
    // Tick的位图信息：其中值是word(uint256)，可以想象为一个0/1的无限连续数组
    // n = tickIndex // 256, i = tickIndex % 256 => n是word的编号，i是tick在word中的编号
    mapping(int16 => uint256) public tickBitmap;

    constructor(
        address token0_,
        address token1_,
        uint160 sqrtPriceX96,
        int24 tick
    ) {
        token0 = token0_;
        token1 = token1_;

        slot0 = Slot0({sqrtPriceX96: sqrtPriceX96, tick: tick});
    }


    // 铸币，指定提供的流动性数量，外围合约会提前将代币数量转换为流动性数量
    function mint(
        address owner,    // 流动性所有者地址
        int24 lowerTick,  // 流动性价格区间上界
        int24 upperTick,  // 流动性价格区间下界
        uint128 amount,   // 想要提供的流动性
        bytes calldata data  // 传递给回调函数的数据
    ) external returns (uint256 amount0, uint256 amount1) {
        if (
            lowerTick >= upperTick ||
            lowerTick < MIN_TICK ||
            upperTick > MAX_TICK
        ) revert InvalidTickRange();

        if (amount == 0) revert ZeroLiquidity();

        bool flippedLower = ticks.update(lowerTick, amount);
        bool flippedUpper = ticks.update(upperTick, amount);

        if (flippedLower) {
            tickBitmap.flipTick(lowerTick, 1);
        }

        if (flippedUpper) {
            tickBitmap.flipTick(upperTick, 1);
        }

        Position.Info storage position = positions.get(
            owner,
            lowerTick,
            upperTick
        );

        position.update(amount);

        Slot0 memory slot0_ = slot0;

        amount0 = Math.calcAmount0Delta(
            TickMath.getSqrtRatioAtTick(slot0_.tick),
            TickMath.getSqrtRatioAtTick(upperTick),
            amount
        );

        amount1 = Math.calcAmount1Delta(
            TickMath.getSqrtRatioAtTick(slot0_.tick),
            TickMath.getSqrtRatioAtTick(lowerTick),
            amount
        );

        liquidity += uint128(amount);

        // 通过callback方式从用户处(msg.sender)收取代币
        uint256 balance0Before;
        uint256 balance1Before;
        if (amount0 > 0) balance0Before = balance0();
        if (amount1 > 0) balance1Before = balance1();
        IUniswapV3MintCallback(msg.sender).uniswapV3MintCallback(
            amount0,
            amount1,
            data
        );
        if (amount0 > 0 && balance0Before + amount0 > balance0()) {
            revert InsufficientInputAmount();
        }
        if (amount1 > 0 && balance1Before + amount1 > balance1()) {
            revert InsufficientInputAmount();
        }

        emit Mint(msg.sender, owner, lowerTick, upperTick, amount, amount0, amount1);
    }

    // 兑换，使用一种代币兑换另一种代币
    function swap(
        address recipient,  // 接收者
        bool zeroForOne,    // 兑换方向：true表示token0换为token1，false表示token1换为token0
        uint256 amountSpecified,  // 用户想要出售的代币数量
        bytes calldata data
    ) public returns (int256 amount0, int256 amount1) {
        Slot0 memory slot0_  = slot0;

        SwapState memory state = SwapState({
            amountSpecifiedRemaining: amountSpecified,
            amountCalculated: 0,
            sqrtPriceX96: slot0_.sqrtPriceX96,
            tick: slot0_.tick
        });

        // 循环直到amountSpecifiedRemaining为0，即池有足够的流动性从用户购买amountSpecified的代币
        while (state.amountSpecifiedRemaining > 0) {
            StepState memory step;

            step.sqrtPriceStartX96 = state.sqrtPriceX96;

            (step.nextTick, ) = tickBitmap.nextInitializedTickWithinOneWord(
                state.tick,
                1,
                zeroForOne
            );

            step.sqrtPriceNextX96 = TickMath.getSqrtRatioAtTick(step.nextTick);

            (state.sqrtPriceX96, step.amountIn, step.amountOut) = SwapMath
                .computeSwapStep(
                    state.sqrtPriceX96,
                    step.sqrtPriceNextX96,
                    liquidity,
                    state.amountSpecifiedRemaining
                );

            state.amountSpecifiedRemaining -= step.amountIn;
            state.amountCalculated += step.amountOut;
            state.tick = TickMath.getTickAtSqrtRatio(state.sqrtPriceX96);
        }

        // 更新pool的当前状态
        if (state.tick != slot0_.tick) {
            (slot0.sqrtPriceX96, slot0.tick) = (state.sqrtPriceX96, state.tick);
        }

        (amount0, amount1) = zeroForOne
            ? (
                int256(amountSpecified - state.amountSpecifiedRemaining),
                -int256(state.amountCalculated)
            )
            : (
                -int256(state.amountCalculated),
                int256(amountSpecified - state.amountSpecifiedRemaining)
            );

        // 根据兑换方向和兑换循环中计算的数量来计算兑换数量
        if (zeroForOne) {
            IERC20(token1).transfer(recipient, uint256(-amount1));

            uint256 balance0Before = balance0();
            IUniswapV3SwapCallback(msg.sender).uniswapV3SwapCallback(
                amount0,
                amount1,
                data
            );
            if (balance0Before + uint256(amount0) > balance0())
                revert InsufficientInputAmount();
        } else {
            IERC20(token0).transfer(recipient, uint256(-amount0));

            uint256 balance1Before = balance1();
            IUniswapV3SwapCallback(msg.sender).uniswapV3SwapCallback(
                amount0,
                amount1,
                data
            );
            if (balance1Before + uint256(amount1) > balance1())
                revert InsufficientInputAmount();
        }

        emit Swap(
            msg.sender,
            recipient,
            amount0,
            amount1,
            slot0.sqrtPriceX96,
            liquidity,
            slot0.tick
        );
    }




    /* 内部函数 */
    function balance0() internal returns (uint256 balance) {
        balance = IERC20(token0).balanceOf(address(this));
    }

    function balance1() internal returns (uint256 balance) {
        balance = IERC20(token1).balanceOf(address(this));
    }

}