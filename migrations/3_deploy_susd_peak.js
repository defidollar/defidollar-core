const Core = artifacts.require("Core");
const CoreProxy = artifacts.require("CoreProxy");
const CurveSusdPeak = artifacts.require("CurveSusdPeak");
const CurveSusdPeakProxy = artifacts.require("CurveSusdPeakProxy");

const MockSusdToken = artifacts.require("MockSusdToken");
const MockSusdDeposit = artifacts.require("MockSusdDeposit");
const MockCurveSusd = artifacts.require("MockCurveSusd");

const toBN = web3.utils.toBN

module.exports = async function(deployer) {
  const coreProxy = await CoreProxy.deployed()
  const core = await Core.at(coreProxy.address)
  const tokens = []
  for (let i = 0; i < 4; i++) {
    tokens.push((await core.systemCoins(i)).token)
  }

  // Deploy Mock sUSD pool
  const curveToken = await deployer.deploy(MockSusdToken)

  const curve = await deployer.deploy(
    MockCurveSusd,
    curveToken.address,
    tokens
  )

  const curveDeposit = await deployer.deploy(
    MockSusdDeposit,
    curve.address,
    curveToken.address,
    tokens
  )

  await deployer.deploy(CurveSusdPeak)
  const curveSusdPeakProxy = await deployer.deploy(CurveSusdPeakProxy)
  const curveSusdPeak = await CurveSusdPeak.at(CurveSusdPeakProxy.address)
  await curveSusdPeakProxy.updateAndCall(
    CurveSusdPeak.address,
    curveSusdPeak.contract.methods.initialize(
      curveDeposit.address, curve.address, curveToken.address,
      core.address,
      tokens
    ).encodeABI()
  )
  await curveSusdPeak.replenish_approvals()
  await core.whitelistPeak(curveSusdPeakProxy.address, [0, 1, 2, 3])
}
