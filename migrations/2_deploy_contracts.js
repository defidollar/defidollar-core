const Core = artifacts.require("CoreAdminFunctions");
const DUSD = artifacts.require("DUSD");
const Aggregator = artifacts.require("MockAggregator");
const Oracle = artifacts.require("Oracle");
const Reserve = artifacts.require("Reserve");

const MockSusdToken = artifacts.require("MockSusdToken");
const MockSusdDeposit = artifacts.require("MockSusdDeposit");
const MockCurveSusd = artifacts.require("MockCurveSusd");

const toBN = web3.utils.toBN

module.exports = async function(deployer) {
  await deployer.deploy(Core);
  await deployer.deploy(DUSD, Core.address);
  // initialize system with 4 coins
  const reserves = await Promise.all([
    Reserve.new(18), // dai
    Reserve.new(6), // usdc
    Reserve.new(6), // usdt
    Reserve.new(18) // susd
  ])

  // Deploy oracle
  const ethPrice = toBN(200)
  const ethUsdAgg = await Aggregator.new()
  // The latestAnswer value for all USD reference data contracts is multiplied by 100000000 before being written on-chain and
  await ethUsdAgg.setLatestAnswer(ethPrice.mul(toBN('100000000')))
  const aggregators = []

  for(let i = 0; i < 4; i++) {
    aggregators.push(await Aggregator.new())
    // set price = $1 but relative to eth
    await aggregators[i].setLatestAnswer(toBN(web3.utils.toWei('1')).div(ethPrice))
  }

  await deployer.deploy(Oracle, aggregators.map(a => a.address), ethUsdAgg.address)

  const core = await Core.deployed()
  await core.initialize(DUSD.address, Oracle.address, 102) // collateralization_ratio

  // Deploy Mock sUSD pool
  const tokens = reserves.map(a => a.address)
  await deployer.deploy(MockSusdToken)
  const curve_token = await MockSusdToken.deployed()
  const curve = await MockCurveSusd.new(curve_token.address, tokens)
  const curve_deposit = await MockSusdDeposit.new(curve.address, curve_token.address, tokens)
  await core.whitelistTokens(tokens, [18, 6, 6, 18])
  await core.addSupportedPool(
    curve_deposit.address,
    curve.address,
    curve_token.address,
    [0, 1, 2, 3] // system_coin_ids
  )
  await core.replenish_approvals()
  await core.updatePrices()
};
