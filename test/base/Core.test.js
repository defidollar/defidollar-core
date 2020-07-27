const assert = require('assert')
const utils = require('../utils.js')

const toWei = web3.utils.toWei
const toBN = web3.utils.toBN
const MAX = web3.utils.toTwosComplement(-1);

contract('Core', async (accounts) => {

    before(async () => {
        const artifacts = await utils.getArtifacts()
        Object.assign(this, artifacts)
        this.user = accounts[1]
        await this.core.whitelistPeak(accounts[0], [0, 1, 2, 3])
    })

    describe('mint/burn', async () => {
        it('mint', async () => {
            this.amounts = [1, 2, 3, 4].map((n, i) => {
                return toBN(n).mul(toBN(10 ** this.decimals[i])).toString()
            })
            let dusdBalance = await this.dusd.balanceOf(this.user)
            assert.equal(dusdBalance.toString(), '0')

            await this.core.mint(this.amounts, toWei('10'), this.user)

            dusdBalance = await this.dusd.balanceOf(this.user)
            assert.equal(dusdBalance.toString(), toWei('10'))
        })

        it('burn', async () => {
            await this.core.redeem(this.amounts, toWei('10'), this.user)

            dusdBalance = await this.dusd.balanceOf(this.user)
            assert.equal(dusdBalance.toString(), '0')
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
