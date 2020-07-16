const Core = artifacts.require("Core");
const CurveSusdPeak = artifacts.require("CurveSusdPeak");

const MockSusdToken = artifacts.require("MockSusdToken");
const MockSusdDeposit = artifacts.require("MockSusdDeposit");
const MockCurveSusd = artifacts.require("MockCurveSusd");

const toBN = web3.utils.toBN

module.exports = async function(deployer) {
  const core = await Core.deployed()
  const tokens = []
  for (let i = 0; i < 4; i++) {
    tokens.push((await core.system_coins(i)).token)
  }

  // Deploy Mock sUSD pool
  await deployer.deploy(MockSusdToken)
  const curve_token = await MockSusdToken.deployed()

  await deployer.deploy(MockCurveSusd, curve_token.address, tokens)
  const curve = await MockCurveSusd.deployed()

  await deployer.deploy(MockSusdDeposit, curve.address, curve_token.address, tokens)
  const curve_deposit = await MockSusdDeposit.deployed()
  
  const sUSDPool = await deployer.deploy(
    CurveSusdPeak,
    curve_deposit.address, curve.address, curve_token.address,
    core.address,
    tokens
  )
  await sUSDPool.replenish_approvals()
  await core.whitelist_peak(CurveSusdPeak.address, [0, 1, 2, 3])
}
