// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./interfaces/IERC20.sol";
import "./interfaces/IUniswapV3MintCallback.sol";
import "./interfaces/IUniswapV3SwapCallback.sol";

import "./lib/Tick.sol";
import "./lib/Position.sol";

contract UniswapV3Pool {
    using Tick for mapping(int24 => Tick.Info);
    // 键是(owner, lowerTick, upperTick)的哈希
    using Position for mapping(bytes32 => Position.Info);
    using Position for Position.Info;

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
        uint128 amount    // 想要提供的流动性
    ) external returns (uint256 amount0, uint256 amount1) {
        if (
            lowerTick >= upperTick ||
            lowerTick < MIN_TICK ||
            upperTick > MAX_TICK
        ) revert InvalidTickRange();

        if (amount == 0) revert ZeroLiquidity();

        ticks.update(lowerTick, amount);
        ticks.update(upperTick, amount);

        Position.Info storage position = positions.get(
            owner,
            lowerTick,
            upperTick
        );

        position.update(amount);

        // 现阶段硬编码，后边章节替换为实际计算
        amount0 = 0.998976618347425280 ether;
        amount1 = 5000 ether;

        liquidity += uint128(amount);

        // 通过callback方式从用户处(msg.sender)收取代币
        uint256 balance0Before;
        uint256 balance1Before;
        if (amount0 > 0) balance0Before = balance0();
        if (amount1 > 0) balance1Before = balance1();
        IUniswapV3MintCallback(msg.sender).uniswapV3MintCallback(
            amount0,
            amount1
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
    function swap(address recipient)
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
            amount1
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