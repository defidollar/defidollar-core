const assert = require('assert')
const utils = require('../utils.js')

const toWei = web3.utils.toWei
const toBN = web3.utils.toBN
const MAX = web3.utils.toTwosComplement(-1);

contract.only('Core', async (accounts) => {

    before(async () => {
        const artifacts = await utils.getArtifacts()
        Object.assign(this, artifacts)
        this.user = accounts[1]
        await this.core.whitelistPeak(accounts[0], [0, 1, 2, 3], false)
    })

    describe('mint/redeem', async () => {
        it('mint', async () => {
            await this.core.mint(toWei('10'), this.user)
            const dusdBalance = await this.dusd.balanceOf(this.user)
            assert.equal(dusdBalance.toString(), toWei('10'))
        })

        it('redeem', async () => {
            await this.core.redeem(toWei('3'), this.user)
            const dusdBalance = await this.dusd.balanceOf(this.user)
            assert.equal(dusdBalance.toString(), toWei('7'))
        })

        it('setPeakStatus fails from non owner account', async () => {
            try {
                await this.core.setPeakStatus(accounts[0], '1', { from: accounts[1]})
            } catch(e) {
                assert.equal(e.reason, 'NOT_OWNER')
            }
        })

        it('set peak as dormant', async () => {
            await this.core.setPeakStatus(accounts[0], 2) // dormant
        })

        it('redeem is possible from dormant peak', async () => {
            await this.core.redeem(toWei('7'), this.user)
            const dusdBalance = await this.dusd.balanceOf(this.user)
            assert.equal(dusdBalance.toString(), '0')
        })

        it('mint fails for dormant peak', async () => {
            try {
                await this.core.mint(toWei('10'), this.user, { from: accounts[1] })
            } catch(e) {
                assert.equal(e.reason, 'Peak is inactive')
            }
        })

        it('set peak as extinct', async () => {
            await this.core.setPeakStatus(accounts[0], 0)
        })

        it('mint fails for dormant peak', async () => {
            try {
                await this.core.mint(toWei('10'), this.user, { from: accounts[1] })
            } catch(e) {
                assert.equal(e.reason, 'Peak is inactive')
            }
        })

        it('redeem fails from extinct peak', async () => {
            try {
                await this.core.redeem(toWei('10'), this.user, { from: accounts[1] })
            } catch(e) {
                assert.equal(e.reason, 'Peak is extinct')
            }
        })
    })
})
