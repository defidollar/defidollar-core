// const _deploy_contracts = require("../migrations/2_deploy_contracts");
const assert = require('assert')

const Core = artifacts.require("CoreAdminFunctions");
const DUSD = artifacts.require("DUSD");
const Reserve = artifacts.require("Reserve");
const MockSusdToken = artifacts.require("MockSusdToken");

const toWei = web3.utils.toWei
const toBN = web3.utils.toBN
const MAX = web3.utils.toTwosComplement(-1);

contract('Core', async (accounts) => {
  const n_coins = 4

  before(async () => {
    this.core = await Core.deployed()
    this.dusd = await DUSD.deployed()
    this.reserves = []
    for (let i = 0; i < n_coins; i++) {
      this.reserves.push(await Reserve.at((await this.core.system_coins(i)).token))
    }
    this.user = accounts[0]
  })

  it('mint', async () => {
    const amounts = []
    const deposit_amount = toBN('1')
    const approvals = []
    for (let i = 0; i < n_coins; i++) {
      const a = deposit_amount.mul(toBN(10).pow(await this.reserves[i].decimals()))
      amounts.push(a)
      approvals.push(this.reserves[i].mint(this.user, a))
      approvals.push(this.reserves[i].approve(this.core.address, a))
    }
    await Promise.all(approvals);
    await this.core.mint(0, amounts, toWei('4'))

    this.dusd_balanace = await this.dusd.balanceOf(this.user)
    assert.equal(this.dusd_balanace.toString(), toWei('4'))
    this.curve_token = await MockSusdToken.deployed()
    assert.equal((await this.curve_token.balanceOf(this.core.address)).toString(), toWei('1'))
  })

  it('burn', async () => {
    await this.dusd.approve(this.core.address, MAX)
    const amounts = []
    const withdraw_amount = toBN('1')
    assert.equal(this.dusd_balanace.toString(), toWei('4'))
    for (let i = 0; i < n_coins; i++) {
      const a = withdraw_amount.mul(toBN(10).pow(await this.reserves[i].decimals()))
      amounts.push(a)
      assert.equal((await this.reserves[i].balanceOf(this.user)).toString(), '0')
    }
    await this.core.burn(0, amounts, MAX)
    assert.equal((await this.dusd.balanceOf(this.user)).toString(), '0')
    for (let i = 0; i < n_coins; i++) {
      assert.equal((await this.reserves[i].balanceOf(this.user)).toString(), amounts[i].toString())
    }
  })
})

function printReceipt(r) {
  r.receipt.logs.forEach(l => {
    if (l.event === 'DebugUint') {
      console.log(l.args.a.toString())
    }
  })
}
