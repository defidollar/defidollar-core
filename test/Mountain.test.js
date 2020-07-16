const assert = require('assert')

const Core = artifacts.require("Core");
const DUSD = artifacts.require("DUSD");
const Reserve = artifacts.require("Reserve");
const StakeLPToken = artifacts.require("StakeLPToken");

const MockCurveSusd = artifacts.require('MockCurveSusd')
const MockSusdToken = artifacts.require("MockSusdToken");
const CurveSusdPeak = artifacts.require('CurveSusdPeak')

const toWei = web3.utils.toWei
const toBN = web3.utils.toBN
const MAX = web3.utils.toTwosComplement(-1);

contract('Mountain', async (accounts) => {
  const n_coins = 4
  const alice = accounts[0]
  const bob = accounts[1]

  before(async () => {
    this.core = await Core.deployed()
    this.dusd = await DUSD.deployed()
    this.stakeLPToken = await StakeLPToken.deployed()
    this.reserves = []
    this.decimals = []
    for (let i = 0; i < n_coins; i++) {
      this.reserves.push(await Reserve.at((await this.core.system_coins(i)).token))
      this.decimals.push(await this.reserves[i].decimals())
    }
    this.pool = await CurveSusdPeak.deployed()

    this.amounts = [1, 2, 3, 4].map((n, i) => {
      return toBN(n).mul(toBN(10 ** this.decimals[i]))
    })
  })

  it('alice mints (CurveSusdPeak)', async () => {
    const tasks = []
    for (let i = 0; i < n_coins; i++) {
      tasks.push(this.reserves[i].mint(alice, this.amounts[i]))
      tasks.push(this.reserves[i].approve(this.pool.address, this.amounts[i]))
    }
    await Promise.all(tasks)
    await this.pool.mint(this.amounts, toWei('10'))

    const dusd_balance = await this.dusd.balanceOf(alice)
    assert.equal(dusd_balance.toString(), toWei('10'))
    this.curve_token = await MockSusdToken.deployed()
    assert.equal((await this.curve_token.balanceOf(this.pool.address)).toString(), toWei('10'))
  })

  it('bob mints (CurveSusdPeak)', async () => {
    const tasks = []
    const from = bob
    for (let i = 0; i < n_coins; i++) {
      tasks.push(this.reserves[i].mint(from, this.amounts[i]))
      tasks.push(this.reserves[i].approve(this.pool.address, this.amounts[i], { from }))
    }
    await Promise.all(tasks)
    await this.pool.mint(this.amounts, toWei('10'), { from })

    this.dusd_balance = await this.dusd.balanceOf(from)
    assert.equal(this.dusd_balance.toString(), toWei('10'))
    this.curve_token = await MockSusdToken.deployed()
    assert.equal((await this.curve_token.balanceOf(this.pool.address)).toString(), toWei('20'))
  })

  it('alice stakes', async () => {
    const stake_amount = toWei('4')

    await this.dusd.approve(this.stakeLPToken.address, stake_amount)
    await this.stakeLPToken.stake(stake_amount)

    const dusd_bal = await this.dusd.balanceOf(alice)
    assert.equal(dusd_bal.toString(), toWei('6')) // 10 - 4

    const bal = await this.stakeLPToken.balanceOf(alice)
    assert.equal(bal.toString(), stake_amount)

    const earned = await this.stakeLPToken.earned(alice)
    assert.equal(earned.toString(), '0')
  })

  it('CurveSusdPeak accrues income', async () => {
    this.mockCurveSusd = await MockCurveSusd.deployed()
    const income = [1, 1, 1, 1].map((n, i) => {
      return toBN(n).mul(toBN(10 ** this.decimals[i]))
    })
    const tasks = []
    for (let i = 0; i < n_coins; i++) {
      tasks.push(this.reserves[i].mint(this.mockCurveSusd.address, income[i]))
    }
    await Promise.all(tasks)
  })

  it('update system stats', async () => {
    let rewardPerTokenStored = await this.stakeLPToken.rewardPerTokenStored()
    assert.equal(rewardPerTokenStored.toString(), '0')

    await this.core.sync_system()

    rewardPerTokenStored = await this.stakeLPToken.rewardPerTokenStored()
    // income of 4 coins for 4 staked coins
    assert.equal(rewardPerTokenStored.toString(), toWei('1'))
    const earned = await this.stakeLPToken.earned(alice)
    assert.equal(earned.toString(), toWei('4'))
  })

  it('Alice exits', async () => {
    await this.stakeLPToken.exit()

    let dusd_bal = await this.dusd.balanceOf(alice)
    assert.equal(dusd_bal.toString(), toWei('14')) // 10 + 4
    const bal = await this.stakeLPToken.balanceOf(alice)
    assert.equal(bal.toString(), '0')
  })
})
