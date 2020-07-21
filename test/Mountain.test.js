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

contract.only('Mountain', async (accounts) => {
  const n_coins = 4
  const alice = accounts[0]
  const bob = accounts[1]
  const SCALE_18 = scale(1, 18)
  const SCALE_36 = scale(1, 36)

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

  it('alice mints 10 (CurveSusdPeak)', async () => {
    await this.assertions({ dusd_total_supply: '0' })

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
    await this.assertions({ dusd_total_supply: toWei('10') })
  })

  it('bob mints 10 (CurveSusdPeak)', async () => {
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
    await this.assertions({ dusd_total_supply: toWei('20') })
  })

  it('alice stakes 4', async () => {
    await this.assertions({
      dusd_total_supply: toWei('20'),
      dusd_staked: '0',
      stakeLPToken_supply: '0',
      unitRewardForCurrentFeeWindow: '0',
      rewardPerTokenStored: '0'
    })

    const stake_amount = toWei('4')

    await this.dusd.approve(this.stakeLPToken.address, stake_amount)
    await this.stakeLPToken.stake(stake_amount)

    const dusd_bal = await this.dusd.balanceOf(alice)
    assert.equal(dusd_bal.toString(), toWei('6')) // 10 - 4

    const bal = await this.stakeLPToken.balanceOf(alice)
    assert.equal(bal.toString(), stake_amount)

    const earned = await this.stakeLPToken.earned(alice)
    assert.equal(earned.toString(), '0')

    await this.assertions({
      dusd_total_supply: toWei('20'),
      dusd_staked: stake_amount,
      stakeLPToken_supply: stake_amount,
      unitRewardForCurrentFeeWindow: SCALE_36.div(scale(4, 18)).toString(),
      rewardPerTokenStored: '0'
    })
  })

  it('CurveSusdPeak accrues income=4', async () => {
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

  it('sync system', async () => {
    await this.core.sync_system()
    await this.assertions({
      dusd_total_supply: toWei('20'),
      dusd_staked: toWei('4'),
      stakeLPToken_supply: toWei('4'),
      unitRewardForCurrentFeeWindow: SCALE_36.div(scale(4, 18)).toString(), // has been reset
      // income of 4 coins for 4 staked coins
      rewardPerTokenStored: toWei('1')
    })
  })

  it('alice has earned=4', async () => {
    const earned = await this.stakeLPToken.earned(alice)
    assert.equal(earned.toString(), toWei('4'))
  })

  it('bob stakes=6', async () => {
    const stake_amount = toWei('6')
    const from = bob
    await this.dusd.approve(this.stakeLPToken.address, stake_amount, { from })
    await this.stakeLPToken.stake(stake_amount, { from })

    const dusd_bal = await this.dusd.balanceOf(bob)
    assert.equal(dusd_bal.toString(), toWei('4')) // 10 - 6

    const bal = await this.stakeLPToken.balanceOf(bob)
    assert.equal(bal.toString(), stake_amount)

    await this.assertions({
      dusd_total_supply: toWei('20'),
      dusd_staked: toWei('10'),
      stakeLPToken_supply: toWei('10'),
      unitRewardForCurrentFeeWindow: SCALE_36
        .div(scale(4, 18))
        .add(SCALE_36.div(scale(10, 18))).toString(), // 1e36 / 4 + 1e36 / 10
      rewardPerTokenStored: toWei('1')
    })

    let earned = await this.stakeLPToken.earned(bob)
    assert.equal(earned.toString(), '0')
  })

  it('Alice claims reward=4', async () => {
    let earned = await this.stakeLPToken.earned(alice)
    assert.equal(earned.toString(), toWei('4'))

    await this.stakeLPToken.getReward()

    let dusd_bal = await this.dusd.balanceOf(alice)
    assert.equal(dusd_bal.toString(), toWei('10')) // 6 + 4 reward

    const bal = await this.stakeLPToken.balanceOf(alice)
    assert.equal(bal.toString(), toWei('4')) // original staked amount

    earned = await this.stakeLPToken.earned(alice)
    assert.equal(earned.toString(), '0')

    await this.assertions({
      dusd_total_supply: toWei('24'),
      dusd_staked: toWei('10'),
      stakeLPToken_supply: toWei('10'),
      unitRewardForCurrentFeeWindow: SCALE_36
        .div(scale(4, 18))
        .add(SCALE_36.div(scale(10, 18))).toString(), // 1e36 / 4 + 1e36 / 10
      rewardPerTokenStored: toWei('1')
    })
  })

  it('CurveSusdPeak accrues income=6', async () => {
    let inventory = await this.core.get_inventory()
    assert.equal(inventory.toString(), toWei('24'))
    this.mockCurveSusd = await MockCurveSusd.deployed()
    const income = [2, 1, 1, 2].map((n, i) => { // 5 tokens
      return toBN(n).mul(toBN(10 ** this.decimals[i]))
    })
    const tasks = []
    for (let i = 0; i < n_coins; i++) {
      tasks.push(this.reserves[i].mint(this.mockCurveSusd.address, income[i]))
    }
    await Promise.all(tasks)
    inventory = await this.core.get_inventory()
    assert.equal(inventory.toString(), toWei('30'))
  })

  it('update system stats', async () => {
    await this.core.update_system_stats()
    this.rewardPerTokenStored = SCALE_18
      .add(SCALE_36
      .div(scale(4, 18))
      .add(SCALE_36.div(scale(10, 18))).mul(toBN(2)))
    await this.assertions({
      dusd_total_supply: toWei('24'),
      dusd_staked: toWei('10'),
      stakeLPToken_supply: toWei('10'),
      unitRewardForCurrentFeeWindow: SCALE_36.div(scale(10, 18)).toString(), // has been reset
      rewardPerTokenStored: this.rewardPerTokenStored // earlier 1 + (1e36 / 4 + 1e36 / 10) * (6 - 4)
    })
  })

  it('Alice exits', async () => {
    let dusd_bal = await this.dusd.balanceOf(alice)
    assert.equal(dusd_bal.toString(), toWei('10'))

    let earned = await this.stakeLPToken.earned(alice)
    console.log({
      balanceOf: (await this.stakeLPToken.balanceOf(alice)).toString(),
      rewardPerTokenStored: (await this.stakeLPToken.rewardPerTokenStored()).toString(),
      userRewardPerTokenPaid: (await this.stakeLPToken.userRewardPerTokenPaid(alice)).toString(),
      earned: earned.toString()
    })

    // assert.equal(earned.toString(), '0')
    // await this.stakeLPToken.exit()

    // await this.assertions({
    //   dusd_total_supply: toWei('24'),
    //   dusd_staked: toWei('10'),
    //   stakeLPToken_supply: toWei('10'),
    //   unitRewardForCurrentFeeWindow: SCALE_36.div(scale(10, 18)).toString(), // has been reset
    //   rewardPerTokenStored: SCALE_18.add(SCALE_36
    //   .div(scale(4, 18))
    //   .add(SCALE_36.div(scale(10, 18))).mul(toBN(2))) // earlier 1 + (1e36 / 4 + 1e36 / 10) * (6 - 4)
    // })
    // dusd_bal = await this.dusd.balanceOf(alice)
    // assert.equal(dusd_bal.toString(), toWei('14')) // 10 + 4
    // const bal = await this.stakeLPToken.balanceOf(alice)
    // assert.equal(bal.toString(), '0')
  })

  this.assertions = async (vals) => {
    if (vals.dusd_total_supply) {
      assert((await this.dusd.totalSupply()).toString(), vals.dusd_total_supply)
    }
    if (vals.dusd_staked) {
      assert((await this.dusd.balanceOf(this.stakeLPToken.address)).toString(), vals.dusd_staked)
    }
    if (vals.stakeLPToken_supply) {
      assert((await this.stakeLPToken.totalSupply()).toString(), vals.stakeLPToken_supply)
    }
    if (vals.unitRewardForCurrentFeeWindow) {
      assert((await this.stakeLPToken.unitRewardForCurrentFeeWindow()).toString(), vals.unitRewardForCurrentFeeWindow)
    }
    if (vals.rewardPerTokenStored) {
      assert((await this.stakeLPToken.rewardPerTokenStored()).toString(), vals.rewardPerTokenStored)
    }
  }
})

function scale(num, decimals) {
  return toBN(num).mul(toBN(10).pow(toBN(decimals)))
}
