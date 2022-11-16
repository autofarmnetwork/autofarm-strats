const { program } = require('commander')
const { ethers } = require('ethers')
const { chainConfigs } = require('autofarm-sdk')
const fs = require('fs')

/*
 * CLI DOCUMENTATION
 * Use with `node ./config-builders/minichef-v2.js -c 56 pcs 0x.. 0x.. 0x..
 */
program
  .description('Generates a MinichefV2 StratX4 config')
  .option('-c, --chain-id <number>', 'Chain ID')
  .option('-w, --write', 'Automatically write file to vaults-config')
  .argument('<farm-name>', 'Farm name')
  .argument('<farm-contract-address>', 'Farm contract address (MinichefV2)')
  .argument('<pid>', 'pid of pool')
  .argument('<reward-addresses...>', 'Reward addresses')
  .action(main)

program.parse();

const IMinichefV2 = [
  'function lpToken(uint256 pid) view returns (address)',
  'function poolInfo(uint256 pid) view returns (uint128, uint64, uint64)',
]
const IPair = [
  'function token0() view returns (address)',
  'function token1() view returns (address)',
  'function factory() view returns (address)',
  'function getReserves() view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast)',
]
const IFactory = [
  'function getPair(address tokenA, address tokenB) view returns (address pair)'
]
const IERC20 = [
  'function symbol() view returns (string)',
  'function decimals() view returns (uint256)',
]


async function main(farmName, farmContractAddress, pid, rewardAddresses, options) {
  const { provider, WETHAddress, multicall, key } = chainConfigs[options.chainId]
  const chainKey = key.toLowerCase()
  const minichef = new ethers.Contract(farmContractAddress, IMinichefV2, provider)

  const assetAddress = await minichef.lpToken(pid)
  const poolInfo = await minichef.poolInfo(pid)

  const asset = new ethers.Contract(assetAddress, IPair, provider)
  const factoryAddress = await asset.factory()

  const token0Address = await asset.token0()
  const token1Address = await asset.token1()

  const token0 = new ethers.Contract(token0Address, IERC20, provider)
  const token1 = new ethers.Contract(token1Address, IERC20, provider)

  const token0Symbol = await token0.symbol()
  const token1Symbol = await token1.symbol()
  const token0Decimals = await token0.decimals()
  const token1Decimals = await token1.decimals()

  console.error({ token0Address, token1Address })
  console.error({ token0Symbol, token1Symbol })

  async function getEarnConfigForReward(reward) {
    if (reward === token0Address || reward === token1Address) {
      return {
        rewardToken: reward,
        swapRoute: {
          feeFactors: [],
          pairsPath: [],
          tokensPath: [],
        },
        zapLiquidityConfig: {
          feeFactor: 9970,
          lpSubtokenIn: reward,
          lpSubtokenOut: reward === token0Address
            ? token1Address
            : token0Address
        }
      }
    }
    const bestRoute = await getRewardLiquidity(reward, token0Address, token1Address)
    const swapRoute = {
      feeFactors: bestRoute.pairsPath.map(() => 9970),
      pairsPath: bestRoute.pairsPath,
      tokensPath: bestRoute.path
    }
    const zapLiquidityConfig = (() => {
      const [lpSubtokenIn, lpSubtokenOut] = bestRoute.path[bestRoute.path.length - 1] === token0Address
        ? [token0Address, token1Address]
        : [token1Address, token0Address]
      return {
        feeFactor: 9970,
        lpSubtokenIn,
        lpSubtokenOut
      }
    })()
    return {
      rewardToken: reward,
      swapRoute,
      zapLiquidityConfig
    }
  }

  const earnConfigs = await Promise.all(
    rewardAddresses.map(rewardAddress => getEarnConfigForReward(rewardAddress))
  )

  const stratConfig = {
    StratContract: "MinichefLP1.sol:StratX4MinichefLP1",
    strat: {
      asset: assetAddress,
      pid: parseInt(pid),
      farmContractAddress: farmContractAddress,
    },
    earnConfigs
  }

  const stratConfigStr = JSON.stringify(stratConfig, null, 2)
  console.log(stratConfigStr)
  fs.writeFileSync(
    `./vaults-config/${chainKey}/${farmName}-${token0Symbol}-${token1Symbol}.json`,
    stratConfigStr
  )

  async function getRewardLiquidity(rewardAddress, token0Address, token1Address) {
    const factory = new ethers.Contract(factoryAddress, IFactory, provider)

    // Direct
    const pairsDirect = await Promise.all(
      [token0Address, token1Address].map(async base => {
        const pairAddress = await factory.getPair(rewardAddress, base)
        const pair = new ethers.Contract(pairAddress, IPair, provider)
        const [reserve0, reserve1] = await pair.getReserves()
        const [reserveIn, reserveOut] = parseInt(rewardAddress) < parseInt(base)
          ? [reserve0, reserve1]
          : [reserve1, reserve0]
        return {
          pairsPath: [pair],
          path: [rewardAddress, base],
          base: base,
          pairAddress,
          reserveIn,
          reserveOut,
          normalizedReserveIn: reserveIn
        }
      })
    )


    // 1 Hop
    // TODO: implement more bases

    const rewardWETHPairInfo = await (async () => {
      const rewardWETHpairAddress = await factory.getPair(rewardAddress, WETHAddress)
      const rewardWETHPair = new ethers.Contract(rewardWETHpairAddress, IPair, provider)
      const [reserve0, reserve1] = await rewardWETHPair.getReserves()
      const [reserveIn, reserveOut] = parseInt(rewardAddress) < parseInt(WETHAddress)
        ? [reserve0, reserve1]
        : [reserve1, reserve0]
      return { pairAddress: rewardWETHpairAddress, reserveIn, reserveOut }
    })()

    // const bases = [token0Address, token1Address]
    const pairs1Hop = await Promise.all(
      [token0Address, token1Address].map(async base => {
        const pairAddress = await factory.getPair(WETHAddress, base)
        const pair = new ethers.Contract(pairAddress, IPair, provider)
        const [reserve0, reserve1] = await pair.getReserves()
        const [reserveIn, reserveOut] = parseInt(rewardAddress) < parseInt(base)
          ? [reserve0, reserve1]
          : [reserve1, reserve0]

        // The reserve level of a 1 hop route is given by:
        // r0 + r'0 / r'0 + r1
        const normalizedReserveIn = rewardWETHPairInfo.reserveIn.mul(reserveIn)
          .div(reserveIn.add(rewardWETHPairInfo.reserveOut))

        return {
          pairsPath: [rewardWETHPairInfo.pairAddress, pairAddress],
          path: [rewardAddress, WETHAddress, base],
          base: base,
          pairAddress,
          reserveIn,
          reserveOut,
          normalizedReserveIn
        }
      })
    )

    const routes = [...pairsDirect, ...pairs1Hop]
    // console.error('Possible routes', routes)

    const bestRoute = routes.reduce((acc, route) => {
      if (!acc) {
        return route
      }
      if (acc.normalizedReserveIn.gt(route.normalizedReserveIn)) {
        return acc
      }
      return route
    })


    return bestRoute
  }
}

