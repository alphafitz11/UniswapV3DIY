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

    struct CallbackData {
        address token0;
        address token1;
        address payer;
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
    // 目前版本只接受recipient参数，为了简单起见，在函数中直接硬编码价格和tick
    function swap(address recipient, bytes calldata data)
        public
        returns (int256 amount0, int256 amount1)
    {
        int24 nextTick = 85184;
        uint160 nextPrice = 5604469350942327889444743441197;

        amount0 = -0.008396714242162444 ether;
        amount1 = 42 ether;

        // 更新pool当前状态
        (slot0.tick, slot0.sqrtPriceX96) = (nextTick, nextPrice);

        // 合约发送代币给recipient，调用者发送token到合约
        IERC20(token0).transfer(recipient, uint256(-amount0));

        uint256 balance1Before = balance1();
        IUniswapV3SwapCallback(msg.sender).uniswapV3SwapCallback(
            amount0,
            amount1,
            data
        );
        if (balance1Before + uint256(amount1) < balance1())
            revert InsufficientInputAmount();

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