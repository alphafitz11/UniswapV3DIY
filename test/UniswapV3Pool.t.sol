// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "forge-std/Test.sol";
import "./ERC20Mintable.sol";
import "./TestUtils.sol";
import "../src/UniswapV3Pool.sol";

contract UniswapV3PoolTest is Test, TestUtils {
    ERC20Mintable token0;
    ERC20Mintable token1;
    UniswapV3Pool pool;

    bool transferInMintCallback = true;
    bool transferInSwapCallback = true;
    
    struct TestCaseParams {
        uint256 wethBalance;
        uint256 usdcBalance;
        int24 currentTick;
        int24 lowerTick;
        int24 upperTick;
        uint128 liquidity;
        uint160 currentSqrtP;
        bool transferInMintCallback;
        bool transferInSwapCallback;
        bool mintLiquidity;
    }

    // 设置测试用例：用于完成部署合约、铸造代币、初始化池等配置环境的操作
    function setUp() public {
        token0 = new ERC20Mintable("Ether", "ETH", 18);
        token1 = new ERC20Mintable("USDC", "USDC", 18);
    }

    // 测试Pool合约的mint函数，检查：
    // 1. 从我们手中获取正确数量的代币
    // 2. 使用正确的key和流动性创建position
    // 3. 初始化指定的上限和下限tick
    // 4. 有正确的sqrt_P和流动性L
    function testMintSuccess() public {
        TestCaseParams memory params = TestCaseParams({
            wethBalance: 1 ether,
            usdcBalance: 5000 ether,
            currentTick: 85176,
            lowerTick: 84222,
            upperTick: 86129,
            liquidity: 1517882343751509868544,
            currentSqrtP: 5602277097478614198912276234240,
            transferInMintCallback: true,
            transferInSwapCallback: true,
            mintLiquidity: true
        });

        (uint256 poolBalance0, uint256 poolBalance1) = setupTestCase(params);  // 在该函数中使用params创建了流动性池

        uint256 expectedAmount0 = 0.998833192822975409 ether;
        uint256 expectedAmount1 = 4999.187247111820044641 ether;

        // 检查提供的流动性对应的代币数量是否与计算的相同
        assertEq(
            poolBalance0,
            expectedAmount0,
            "incorrect token0 deposited amount"
        );
        assertEq(
            poolBalance1,
            expectedAmount1,
            "incorrect token1 deposited amount"
        );

        // 检查流动性对应的代币是否转入到pool中
        assertEq(token0.balanceOf(address(pool)), expectedAmount0);
        assertEq(token1.balanceOf(address(pool)), expectedAmount1);

        // 检查pool为我们创建的position
        bytes32 positionKey = keccak256(
            abi.encodePacked(address(this), params.lowerTick, params.upperTick)
        );
        uint128 posLiquidity = pool.positions(positionKey);
        assertEq(posLiquidity, params.liquidity);

        // 检查tick
        (bool tickInitialized, uint128 tickLiquidity) = pool.ticks(
            params.lowerTick
        );
        assertTrue(tickInitialized);
        assertEq(tickLiquidity, params.liquidity);

        (tickInitialized, tickLiquidity) = pool.ticks(params.upperTick);
        assertTrue(tickInitialized);
        assertEq(tickLiquidity, params.liquidity);

        // 检查sqrt_P和流动性L
        (uint160 sqrtPriceX96, int24 tick) = pool.slot0();
        assertEq(
            sqrtPriceX96,
            5602277097478614198912276234240,
            "invalid current sqrtP"
        );
        assertEq(tick, 85176, "invalid current tick");
        assertEq(
            pool.liquidity(),
            1517882343751509868544,
            "invalid current liquidity"
        );
    }

    // 测试Pool合约的swap函数：使用USDC兑换ETH
    function testSwapBuyEth() public {
        TestCaseParams memory params = TestCaseParams({
            wethBalance: 1 ether,
            usdcBalance: 5000 ether,
            currentTick: 85176,
            lowerTick: 84222,
            upperTick: 86129,
            liquidity: 1517882343751509868544,
            currentSqrtP: 5602277097478614198912276234240,
            transferInMintCallback: true,
            transferInSwapCallback: true,
            mintLiquidity: true
        });

        (uint256 poolBalance0, uint256 poolBalance1) = setupTestCase(params);

        uint256 swapAmount = 42 ether;
        token1.mint(address(this), swapAmount);
        token1.approve(address(this), swapAmount);

        bytes memory extra = encodeExtra(
            address(token0),
            address(token1),
            address(this)
        );

        int256 userBalance0Before = int256(token0.balanceOf(address(this)));
        int256 userBalance1Before = int256(token1.balanceOf(address(this)));

        (int256 amount0Delta, int256 amount1Delta) = pool.swap(
            address(this),
            false,
            swapAmount,
            extra
        );

        // 检查swap中使用的代币数量
        assertEq(amount0Delta, -0.008396714242162445 ether, "invalid ETH out");
        assertEq(amount1Delta, 42 ether, "invalid USDC in");

        // 检查代币余额
        assertEq(
            token0.balanceOf(address(this)),
            uint256(userBalance0Before - amount0Delta),
            "invalid user ETH balance"
        );
        assertEq(
            token1.balanceOf(address(this)),
            uint256(userBalance1Before - amount1Delta),
            "invalid user USDC balance"
        );

        // 检查发送到pool合约的代币数量
        assertEq(
            token0.balanceOf(address(pool)),
            uint256(int256(poolBalance0) + amount0Delta),
            "invalid pool ETH balance"
        );
        assertEq(
            token1.balanceOf(address(pool)),
            uint256(int256(poolBalance1) + amount1Delta),
            "invalid pool USDC balance"
        );

        // 检查pool状态是否被正确地更新
        (uint160 sqrtPriceX96, int24 tick) = pool.slot0();
        assertEq(
            sqrtPriceX96,
            5604469350942327889444743441197,
            "invalid current sqrtP"
        );
        assertEq(tick, 85184, "invalid current tick");
        assertEq(
            pool.liquidity(),
            1517882343751509868544,
            "invalid current liquidity"
        );
    }

    // 测试Pool合约的swap函数：使用ETH兑换USDC
    function testSwapBuyUSDC() public {
        TestCaseParams memory params = TestCaseParams({
            wethBalance: 1 ether,
            usdcBalance: 5000 ether,
            currentTick: 85176,
            lowerTick: 84222,
            upperTick: 86129,
            liquidity: 1517882343751509868544,
            currentSqrtP: 5602277097478614198912276234240,
            transferInMintCallback: true,
            transferInSwapCallback: true,
            mintLiquidity: true
        });
        (uint256 poolBalance0, uint256 poolBalance1) = setupTestCase(params);

        uint256 swapAmount = 0.01337 ether;
        token0.mint(address(this), swapAmount);
        token0.approve(address(this), swapAmount);

        bytes memory extra = encodeExtra(
            address(token0),
            address(token1),
            address(this)
        );

        int256 userBalance0Before = int256(token0.balanceOf(address(this)));
        int256 userBalance1Before = int256(token1.balanceOf(address(this)));

        (int256 amount0Delta, int256 amount1Delta) = pool.swap(
            address(this),
            true,
            swapAmount,
            extra
        );

        // 检查swap中使用的代币数量
        assertEq(amount0Delta, 0.01337 ether, "invalid ETH in");
        assertEq(
            amount1Delta,
            -66.808388890199406685 ether,
            "invalid USDC out"
        );

        // 检查代币余额
        assertEq(
            token0.balanceOf(address(this)),
            uint256(userBalance0Before - amount0Delta),
            "invalid user ETH balance"
        );
        assertEq(
            token1.balanceOf(address(this)),
            uint256(userBalance1Before - amount1Delta),
            "invalid user USDC balance"
        );

        // 检查发送到pool合约的代币数量
        assertEq(
            token0.balanceOf(address(pool)),
            uint256(int256(poolBalance0) + amount0Delta),
            "invalid pool ETH balance"
        );
        assertEq(
            token1.balanceOf(address(pool)),
            uint256(int256(poolBalance1) + amount1Delta),
            "invalid pool USDC balance"
        );

        // 检查pool状态是否被正确地更新
        (uint160 sqrtPriceX96, int24 tick) = pool.slot0();
        assertEq(
            sqrtPriceX96,
            5598789932670288701514545755210,
            "invalid current sqrtP"
        );
        assertEq(tick, 85163, "invalid current tick");
        assertEq(
            pool.liquidity(),
            1517882343751509868544,
            "invalid current liquidity"
        );        
    }


    /* Callback 函数 */
    // Mint对应的Callback函数
    function uniswapV3MintCallback(uint256 amount0, uint256 amount1, bytes calldata data) public {
        if (transferInMintCallback) {
            UniswapV3Pool.CallbackData memory extra = abi.decode(
                data,
                (UniswapV3Pool.CallbackData)
            );

            IERC20(extra.token0).transferFrom(extra.payer, msg.sender, amount0);
            IERC20(extra.token1).transferFrom(extra.payer, msg.sender, amount1);
        }
    }

    // Swap对应的Callback函数
    function uniswapV3SwapCallback(int256 amount0, int256 amount1, bytes calldata data) public {
        UniswapV3Pool.CallbackData memory extra = abi.decode(
            data,
            (UniswapV3Pool.CallbackData)
        );

        if (amount0 > 0) {
            IERC20(extra.token0).transferFrom(extra.payer, msg.sender, uint256(amount0));
        }

        if (amount1 > 0) {
            IERC20(extra.token1).transferFrom(extra.payer, msg.sender, uint256(amount1));
        }
    }


    /* 内部函数 */
    // 使用预定义的测试用例参数设定测试用例
    function setupTestCase(TestCaseParams memory params) 
        internal
        returns (uint256 poolBalance0, uint256 poolBalance1)
    {
        token0.mint(address(this), params.wethBalance);
        token1.mint(address(this), params.usdcBalance);

        // 根据提供的参数创建了新的池子
        pool = new UniswapV3Pool(
            address(token0),
            address(token1),
            params.currentSqrtP,
            params.currentTick
        );

        if (params.mintLiquidity) {
            token0.approve(address(this), params.wethBalance);
            token1.approve(address(this), params.usdcBalance);

            UniswapV3Pool.CallbackData memory extra = UniswapV3Pool
                .CallbackData({
                    token0: address(token0),
                    token1: address(token1),
                    payer: address(this)
                });
            
            (poolBalance0, poolBalance1) = pool.mint(
                address(this),
                params.lowerTick,
                params.upperTick,
                params.liquidity,
                abi.encode(extra)
            );
        }

        transferInMintCallback = params.transferInMintCallback;
        transferInSwapCallback = params.transferInSwapCallback;
    }
}