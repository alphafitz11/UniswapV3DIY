# 使用 Python 实现的 UniswapV3DIY 中的数学操作

import math

min_tick = -887272
max_tick = 887272

q96 = 2**96
eth = 10**18


# 将价格转换为tick
def price_to_tick(p):
    return math.floor(math.log(p, 1.0001))


# 将价格转换为Q64.96表示的sqrt_P
def price_to_sqrtp(p):
    return int(math.sqrt(p)* q96)


# 将Q64.96表示的sqrt_P转换为价格
def sqrtp_to_price(sqrtp):
    return (sqrtp / q96) ** 2


# 将tick转换为Q64.96表示的sqrt_P
def tick_to_sqrtp(t):
    return int((1.0001 ** (t / 2)) * q96)


# 根据代币x数量、当前价格和价格区间上限计算能够提供的流动性
def liquidity0(amount, pa, pb):
    if pa > pb:
        pa, pb = pb, pa
    return (amount * (pa * pb) / q96) / (pb - pa)


# 根据代币y数量、当前价格和价格区间下限计算能够提供的流动性
def liquidity1(amount, pa, pb):
    if pa > pb:
        pa, pb = pb, pa
    return amount * q96 / (pb - pa)


# 根据流动性和价格计算代币x数量
def calc_amount0(liq, pa, pb):
    if pa > pb:
        pa, pb = pb, pa
    return int(liq * q96 * (pb - pa) / pa / pb)


# 根据流动性和价格计算代币y数量
def calc_amount1(liq, pa, pb):
    if pa > pb:
        pa, pb = pb, pa
    return int(liq * (pb - pa) / q96)


# 提供流动性
price_low = 4545
price_cur = 5000
price_upp = 5500

print("\nmilestone1: First Swap")
print(f"价格区间: {price_low} - {price_upp}，当前价格: {price_cur}")

sqrtp_low = price_to_sqrtp(price_low)
sqrtp_cur = price_to_sqrtp(price_cur)
sqrtp_upp = price_to_sqrtp(price_upp)

amount_eth = 1 * eth
amount_usdc = 5000 * eth

liq0 = liquidity0(amount_eth, sqrtp_cur, sqrtp_upp)
liq1 = liquidity1(amount_usdc, sqrtp_cur, sqrtp_low)
liq = int(min(liq0, liq1))
print(f"存入 {amount_eth/eth} ETH 和 {amount_usdc/eth} USDC 所能提供的流动性: {liq}")

# 获取流动性L需要存入的代币数量
amount0 = calc_amount0(liq, sqrtp_upp, sqrtp_cur)
amount1 = calc_amount1(liq, sqrtp_low, sqrtp_cur)
print(f"获取上述流动性需要存入的代币数量为 代币x: {amount0}, 代币y: {amount1}")


# 假设用 42 USDC 换取 ETH
amount_in = 42 * eth
price_diff = (amount_in * q96) // liq
price_next = sqrtp_cur + price_diff
print("新的价格: ", (price_next / q96) ** 2)
print("新的 sqrt_P: ", price_next)
print("新的 tick: ", price_to_tick((price_next / q96) ** 2))

amount_in = calc_amount1(liq, price_next, sqrtp_cur)
amount_out = calc_amount0(liq, price_next, sqrtp_cur)
print("USDC in: ", amount_in / eth)
print("ETH out:", amount_out / eth)
print("---------------------")

#实现swap数量的计算
print("\nmilestone2: Second Swap")

# 使用 ETH 兑换 USDC
amount_in = 0.01337 * eth

print(f"卖出 {amount_in/eth} ETH")

# 使用当前sqrt_P、流动性L和要卖出的代币x数量计算出兑换后的价格
price_next = int((liq * q96 * sqrtp_cur) // (liq * q96 + amount_in * sqrtp_cur))
# 当卖出代币y时需要使用下面的公式计算价格
# price_next = sqrtp_cur + (amount_in * q96) // liq

print("新的价格: ", (price_next / q96) ** 2)
print("新的 sqrt_P: ", price_next)
print("新的 tick: ", price_to_tick((price_next / q96) ** 2))

# 计算某个流动性L下价格变化对应的代币数量变化
amount_in = calc_amount0(liq, price_next, sqrtp_cur)
amount_out = calc_amount1(liq, price_next, sqrtp_cur)

print("ETH in: ", amount_in / eth)
print("USDC out: ", amount_out / eth)
# 对于以上这些数学计算，我们将在Solidity中实现

# 计算tick对应的word位置和该位在word中的位置
tick = 85176
word_pos = tick >> 8  # or tick // 2**8
bit_pos = tick % 256
print(f"tick {tick} 对应的 Word 和 bit: Word {word_pos}, bit {bit_pos}")

mask = 2**bit_pos  # or 1 << bit_pos
print("位掩码:", bin(mask))

word = (2**256) - 1  # 设为全1
print(bin(word ^ mask))

word = 0  # 设为全0
print(bin(word ^ mask))