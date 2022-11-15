// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./BitMath.sol";

library TickBitmap {
    
    // 计算tick的word位置以及该位在word中的位置
    function position(int24 tick) private pure returns (int16 wordPos, uint8 bitPos) {
        wordPos = int16(tick >> 8);
        bitPos = uint8(uint24(tick % 256));
    }

    // 设置刻度
    function flipTick(
        mapping(int16 => uint256) storage self,
        int24 tick,
        int24 tickSpacing
    ) internal {
        require(tick % tickSpacing == 0);  // tick必须被tickSpacing整除
        (int16 wordPos, uint8 bitPos) = position(tick / tickSpacing);
        uint256 mask = 1 << bitPos;
        self[wordPos] ^= mask;
    }

    // 找到一个在当前tick之前或之后的具有流动性的tick
    // 需要实现两个场景：(1)使用x换y，找到的下一个初始化的tick在当前tick右侧；(2)使用y换x，找到的tick在当前tick左侧
    // 在代码中，方向是相反的。但这只是在一个word中，word从左到右排序。
    function nextInitializedTickWithinOneWord(
        mapping(int16 => uint256) storage self,
        int24 tick,  // 当前tick
        int24 tickSpacing,  // 在milestone4开始使用之前都是1
        bool lte  // 兑换方向：如果为true则卖出token x并向右搜索，如果为false则相反
    ) internal view returns (int24 next, bool initialized) {
        int24 compressed = tick / tickSpacing;

        if(lte) {
            (int16 wordPos, uint8 bitPos) = position(compressed);
            // 当前位位置右侧的所有位都是1
            uint256 mask = (1 << bitPos) - 1 + (1 << bitPos);
            // 应用掩码，如果至少有一位设置为1，则maksed将不为0，有一个初始化的tick；如果没有，则不在当前word中
            uint256 masked = self[wordPos] & mask;
            
            initialized = masked != 0;
            // 要么返回下一个初始化tick的索引，要么返回下一个word中最左边的位
            next = initialized
                ? (compressed - int24(uint24(bitPos - BitMath.mostSignificantBit(masked)))) * tickSpacing
                : (compressed - int24(uint24(bitPos))) * tickSpacing;
        } else {
            (int16 wordPos, uint8 bitPos) = position(compressed + 1);
            // 下一个tick位位置左侧的所有位都是1，右侧的所有位均为0
            uint256 mask = ~((1 << bitPos) - 1);
            // 应用掩码
            uint256 masked = self[wordPos] & mask;

            initialized = masked != 0;
            next = initialized
                ? (compressed + 1 + int24(uint24((BitMath.leastSignificantBit(masked) - bitPos)))) * tickSpacing
                : (compressed + 1 + int24(uint24((type(uint8).max - bitPos)))) * tickSpacing;
        }
    }
}