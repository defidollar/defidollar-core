const assert = require('assert')

const Core = artifacts.require("Core");
const DUSD = artifacts.require("DUSD");
const Reserve = artifacts.require("Reserve");

const toWei = web3.utils.toWei
const toBN = web3.utils.toBN
const MAX = web3.utils.toTwosComplement(-1);

const n_coins = 4

contract('Core', async (accounts) => {

  before(async () => {
    this.core = await Core.deployed()
    this.dusd = await DUSD.deployed()
    this.reserves = []
    this.decimals = []
    for (let i = 0; i < n_coins; i++) {
      this.reserves.push(await Reserve.at((await this.core.system_coins(i)).token))
      this.decimals.push(await this.reserves[i].decimals())
    }
    this.user = accounts[1]
    await this.core.whitelist_peak(accounts[0], [0, 1, 2, 3])
  })

  describe('mint/burn', async () => {
    it('mint', async () => {
      this.amounts = [1, 2, 3, 4].map((n, i) => {
        return toBN(n).mul(toBN(10 ** this.decimals[i])).toString()
      })
      let dusd_balance = await this.dusd.balanceOf(this.user)
      assert.equal(dusd_balance.toString(), '0')

      await this.core.mint(this.amounts, toWei('10'), this.user)

      dusd_balance = await this.dusd.balanceOf(this.user)
      assert.equal(dusd_balance.toString(), toWei('10'))
    })

    it('burn', async () => {
      await this.core.burn(this.amounts, toWei('10'), this.user)

      dusd_balance = await this.dusd.balanceOf(this.user)
      assert.equal(dusd_balance.toString(), '0')
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
