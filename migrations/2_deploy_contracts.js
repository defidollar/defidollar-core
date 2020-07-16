const Core = artifacts.require("Core");
const StakeLPToken = artifacts.require("StakeLPToken");
const DUSD = artifacts.require("DUSD");
const CurveSusdPeak = artifacts.require("CurveSusdPeak");
const Aggregator = artifacts.require("MockAggregator");
const Oracle = artifacts.require("Oracle");
const Reserve = artifacts.require("Reserve");

const MockSusdToken = artifacts.require("MockSusdToken");
const MockSusdDeposit = artifacts.require("MockSusdDeposit");
const MockCurveSusd = artifacts.require("MockCurveSusd");

const toBN = web3.utils.toBN
const toWei = web3.utils.toWei

module.exports = async function(deployer) {
  await deployer.deploy(Core);
  const core = await Core.deployed()
  await deployer.deploy(DUSD, Core.address);

  // initialize system with 4 coins
  const reserves = [
    await Reserve.new(18), // dai
    await Reserve.new(6), // usdc
    await Reserve.new(6), // usdt
    await Reserve.new(18) // susd
  ]
  const tokens = reserves.map(a => a.address)

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

  const stakeLPToken = await deployer.deploy(StakeLPToken, Core.address, DUSD.address)
  await core.initialize(
    DUSD.address,
    stakeLPToken.address,
    Oracle.address,
    10000 // 0 redeem fee
    // 10005 // .05% redeem fee
  )
  const initial_price = toWei('1')
  await core.whitelist_tokens(tokens, [18, 6, 6, 18], new Array(4).fill(initial_price))
  await core.sync_system()
};
