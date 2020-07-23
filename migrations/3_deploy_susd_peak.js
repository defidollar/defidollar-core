const Core = artifacts.require("Core");
const CoreProxy = artifacts.require("CoreProxy");
const CurveSusdPeak = artifacts.require("CurveSusdPeak");

const MockSusdToken = artifacts.require("MockSusdToken");
const MockSusdDeposit = artifacts.require("MockSusdDeposit");
const MockCurveSusd = artifacts.require("MockCurveSusd");

const toBN = web3.utils.toBN

module.exports = async function(deployer) {
  const coreProxy = await CoreProxy.deployed()
  const core = await Core.at(coreProxy.address)
  const tokens = []
  for (let i = 0; i < 4; i++) {
    tokens.push((await core.system_coins(i)).token)
  }

  // Deploy Mock sUSD pool
  const curveToken = await deployer.deploy(MockSusdToken)

  const curve = await deployer.deploy(
    MockCurveSusd,
    curveToken.address,
    tokens
  )

  const curve_deposit = await deployer.deploy(
    MockSusdDeposit,
    curve.address,
    curveToken.address,
    tokens
  )

  const curveSusdPeak = await deployer.deploy(CurveSusdPeak)
  await curveSusdPeak.initialize(
    curve_deposit.address, curve.address, curveToken.address,
    core.address,
    tokens
  )
  await curveSusdPeak.replenish_approvals()
  await core.whitelist_peak(CurveSusdPeak.address, [0, 1, 2, 3])
}
