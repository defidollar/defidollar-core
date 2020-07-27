const assert = require('assert')
const utils = require('../../utils.js')

const toWei = web3.utils.toWei
const toBN = web3.utils.toBN
const MAX = web3.utils.toTwosComplement(-1);

contract('CurveSusdPeak', async (accounts) => {
    const n_coins = 4

    before(async () => {
        const artifacts = await utils.getArtifacts()
        Object.assign(this, artifacts)
        this.user = accounts[0]
    })

    describe('mint/burn', async () => {
        it('mint', async () => {
            this.amounts = [1, 2, 3, 4]
            const tasks = []
            for (let i = 0; i < n_coins; i++) {
                this.amounts[i] = toBN(this.amounts[i]).mul(toBN(10).pow(await this.reserves[i].decimals()))
                tasks.push(this.reserves[i].mint(this.user, this.amounts[i]))
                tasks.push(this.reserves[i].approve(this.curveSusdPeak.address, this.amounts[i]))
            }
            await Promise.all(tasks)
            await this.curveSusdPeak.mint(this.amounts, toWei('10'))

            this.dusdBalance = await this.dusd.balanceOf(this.user)
            assert.equal(this.dusdBalance.toString(), toWei('10'))
            assert.equal((await this.curveToken.balanceOf(this.curveSusdPeak.address)).toString(), toWei('10'))
        })

        it('burn', async () => {
            for (let i = 0; i < n_coins; i++) {
                const balance = await this.reserves[i].balanceOf(this.user)
                assert.equal(balance.toString(), '0')
            }
            await this.curveSusdPeak.redeem(this.amounts, toWei('10'))
            for (let i = 0; i < n_coins; i++) {
                const balance = await this.reserves[i].balanceOf(this.user)
                assert.equal(balance.toString(), this.amounts[i].toString())
            }
            this.dusdBalance = await this.dusd.balanceOf(this.user)
            assert.equal(this.dusdBalance.toString(), '0')
        })
    })
})
