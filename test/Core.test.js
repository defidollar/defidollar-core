const assert = require('assert')

const Core = artifacts.require("Core");
const DUSD = artifacts.require("DUSD");
const Reserve = artifacts.require("Reserve");
const MockSusdToken = artifacts.require("MockSusdToken");
const SUSDPool = artifacts.require('SUSDPool')

const toWei = web3.utils.toWei
const toBN = web3.utils.toBN
const MAX = web3.utils.toTwosComplement(-1);

contract.only('Core', async (accounts) => {
  const n_coins = 4

  before(async () => {
    this.core = await Core.deployed()
    this.dusd = await DUSD.deployed()
    this.reserves = []
    for (let i = 0; i < n_coins; i++) {
      this.reserves.push(await Reserve.at((await this.core.system_coins(i)).token))
    }
    this.user = accounts[0]
    this.pool = await SUSDPool.deployed()
  })

  describe('staking', async () => {
    it('mint', async () => {
      this.amounts = [1, 2, 3, 4]
      const tasks = []
      for (let i = 0; i < n_coins; i++) {
        this.amounts[i] = toBN(this.amounts[i]).mul(toBN(10).pow(await this.reserves[i].decimals()))
        tasks.push(this.reserves[i].mint(this.user, this.amounts[i]))
        tasks.push(this.reserves[i].approve(this.pool.address, this.amounts[i]))
      }
      await Promise.all(tasks)
      await this.pool.mint(this.amounts, toWei('10'))

      this.dusd_balance = await this.dusd.balanceOf(this.user)
      assert.equal(this.dusd_balance.toString(), toWei('10'))
      this.curve_token = await MockSusdToken.deployed()
      assert.equal((await this.curve_token.balanceOf(this.pool.address)).toString(), toWei('10'))
    })

    it('stake', async () => {
      const stake_amount = toWei('5') // 50% supply
      await this.dusd.approve(this.core.address, stake_amount)
      console.log(await this.core.get_inventory())
      // await this.core.stake(stake_amount)
    })
  })
})

function printReceipt(r) {
  r.receipt.logs.forEach(l => {
    if (l.event === 'DebugUint') {
      console.log(l.args.a.toString())
    }
  })
}
