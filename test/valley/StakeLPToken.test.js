const assert = require('assert')
const utils = require('../utils.js')

const toWei = web3.utils.toWei
const toBN = web3.utils.toBN
const MAX = web3.utils.toTwosComplement(-1);

contract('StakeLPToken', async (accounts) => {

    before(async () => {
        const artifacts = await utils.getArtifacts()
        Object.assign(this, artifacts)
        this.user = accounts[0]

        this.amounts = [1, 2, 3, 4].map((n, i) => {
            return toBN(n).mul(toBN(10 ** this.decimals[i])).toString()
        })
        await this.core.whitelistPeak(accounts[0], [0, 1, 2, 3])
        this.amount = toWei('10')
        await this.core.mint(this.amounts, this.amount, this.user)
    })

    describe('stake/withdraw', async () => {
        it('stake', async () => {
            let dusd_bal = await this.dusd.balanceOf(this.user)
            assert.equal(dusd_bal.toString(), this.amount)
            let bal = await this.stakeLPToken.balanceOf(this.user)
            assert.equal(bal.toString(), '0')

            await this.dusd.approve(this.stakeLPToken.address, MAX)
            await this.stakeLPToken.stake(this.amount)

            dusd_bal = await this.dusd.balanceOf(this.user)
            assert.equal(dusd_bal.toString(), '0')
            bal = await this.stakeLPToken.balanceOf(this.user)
            assert.equal(bal.toString(), this.amount)
        })

        it('withdraw', async () => {
            await this.stakeLPToken.withdraw(this.amount)

            dusd_bal = await this.dusd.balanceOf(this.user)
            assert.equal(dusd_bal.toString(), this.amount)
            bal = await this.stakeLPToken.balanceOf(this.user)
            assert.equal(bal.toString(), '0')
        })
    })
})
