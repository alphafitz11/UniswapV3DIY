// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "forge-std/console.sol";
import "forge-std/Script.sol";
import "../src/UniswapV3Pool.sol";
import "../src/UniswapV3Manager.sol";
import "../test/ERC20Mintable.sol";

contract DeployDevelopment is Script {

    // 部署脚本的主体部分
    function run() public {
        // 定义deployment的参数
        // 与现阶段之前使用的值相同，将铸造5042USDC，向池中提供5000USDC作为流动性，并在swap中换出42USDC
        uint256 wethBalance = 1 ether;
        uint256 usdcBalance = 5042 ether;
        int24 currentTick = 85176;
        uint160 currentSqrtP = 5602277097478614198912276234240;

        // 定义一组部署的transactions，使用startBroadcast/endBroadcast(cheat code)
        // 这些 cheat code 由Foundry提供，通过forge-std/Script.sol继承得到
        // `broadcast()`之后或`startBroadcast()/stopBroadcast()`之间的所有内容都将转换为transaction
        // 这些transactions将发送到执行脚本的节点
        // 两个 cheat code 之间放置了真正的部署
        vm.startBroadcast();
        ERC20Mintable token0 = new ERC20Mintable("Wrapped Ether", "WETH", 18);
        ERC20Mintable token1 = new ERC20Mintable("USD Coin", "USDC", 18);
        // 部署到本地开发网络需要自己部署代币；在主网和测试网中已经创建了代币
        // 要部署到这些网络需要编写用于特定网络的部署脚本

        UniswapV3Pool pool = new UniswapV3Pool(
            address(token0),
            address(token1),
            currentSqrtP,
            currentTick
        );

        UniswapV3Manager manager = new UniswapV3Manager();

        token0.mint(msg.sender, wethBalance);
        token1.mint(msg.sender, usdcBalance);

        vm.stopBroadcast();

        console.log("WETH address:", address(token0));
        console.log("USDC address:", address(token1));
        console.log("Pool address:", address(pool));
        console.log("Manager address:", address(manager));
    }
    // 运行部署脚本(确保Anvil在另一个终端窗口中运行):
    // forge script scripts/DeployDevelopment.s.sol --broadcast --fork-url http://localhost:8545 --private-key $PRIVATE_KEY
    // --broadcast 启用交易广播，默认情况下关闭，因为并非每个脚本都会发送交易
    // --fork-url 设置交易发送到的节点地址
    // --private-key 设置签名交易的私钥，可以选择 Anvil 在启动时打印的私钥的其中之一
    // 运行命令后可以看到共发送了6个交易；前4个用于创建合约，可以看到对应的交易哈希和合约地址；后2个用于执行mint函数，可以看到对应的交易哈希
    // 运行 cast call 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0 "slot0()" | xargs cast --abi-decode "a()(uint160,int24)" 命令
    // 可以查看pool合约的slot0变量，并将其解析为两个返回值
    // 为了简化和合约之间的交互，Solidity编译器能输出ABI(JSON文件)，使用forge获取ABI可以使用如下命令返回JSON文件：
    // forge inspect UniswapV3Pool abi
}