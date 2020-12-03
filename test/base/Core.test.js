const assert = require('assert')
const utils = require('../utils.js')

const toWei = web3.utils.toWei

contract('Core', async (accounts) => {

    before(async () => {
        const artifacts = await utils.getArtifacts()
        Object.assign(this, artifacts)
        this.user = accounts[1]
        await this.core.whitelistPeak(accounts[0], [0, 1, 2, 3], utils.scale(10, 18))
    })

    it('mint', async () => {
        await this.core.mint(toWei('10'), this.user)
        const dusdBalance = await this.dusd.balanceOf(this.user)
        assert.equal(dusdBalance.toString(), toWei('10'))
        const { amount } = await this.core.peaks(accounts[0])
        assert.equal(amount.toString(), toWei('10'))
    })

    it('redeem', async () => {
        await this.core.redeem(toWei('3'), this.user)
        const dusdBalance = await this.dusd.balanceOf(this.user)
        assert.equal(dusdBalance.toString(), toWei('7'))
        const { amount } = await this.core.peaks(accounts[0])
        assert.equal(amount.toString(), toWei('7'))
    })

    it('ceiling test', async () => {
        assert.equal((await this.core.peaks(accounts[0])).ceiling.toString(), toWei('10'))

        try {
            await this.core.mint(toWei('4'), this.user)
            assert.fail('expected to revert')
        } catch(e) {
            assert.equal(e.reason, 'ERR_MINT')
        }

        // raise ceiling
        await this.core.setPeakStatus(accounts[0], utils.scale(11, 18), '1')
        assert.equal((await this.core.peaks(accounts[0])).ceiling.toString(), toWei('11'))

        await this.core.mint(toWei('4'), this.user)
        const { amount } = await this.core.peaks(accounts[0])
        assert.equal(amount.toString(), toWei('11'))

        await this.core.redeem(toWei('4'), this.user)
        assert.equal((await this.core.peaks(accounts[0])).amount.toString(), toWei('7'))
        assert.equal((await this.core.peaks(accounts[0])).ceiling.toString(), toWei('11'))

        // reduce ceiling
        await this.core.setPeakStatus(accounts[0], utils.scale(6, 18), '1')
        assert.equal((await this.core.peaks(accounts[0])).ceiling.toString(), toWei('6'))
    })

    it('set peak as dormant', async () => {
        await this.core.setPeakStatus(accounts[0], 0, 2) // dormant and also reduces ceiling
    })

    // lower ceiling shouldn't affect redeem
    it('redeem is possible from dormant peak', async () => {
        await this.core.redeem(toWei('7'), this.user)
        const dusdBalance = await this.dusd.balanceOf(this.user)
        assert.equal(dusdBalance.toString(), '0')
    })

    it('mint fails for dormant peak', async () => {
        try {
            await this.core.mint(toWei('10'), this.user, { from: accounts[1] })
            assert.fail('expected to revert')
        } catch(e) {
            assert.equal(e.reason, 'ERR_MINT')
        }
    })

    it('set peak as extinct', async () => {
        await this.core.setPeakStatus(accounts[0], 0, 0)
    })

    it('mint fails for dormant peak', async () => {
        try {
            await this.core.mint(toWei('10'), this.user, { from: accounts[1] })
            assert.fail('expected to revert')
        } catch(e) {
            assert.equal(e.reason, 'ERR_MINT')
        }
    })

    it('redeem fails from extinct peak', async () => {
        try {
            await this.core.redeem(toWei('10'), this.user, { from: accounts[1] })
            assert.fail('expected to revert')
        } catch(e) {
            assert.equal(e.reason, 'ERR_REDEEM')
        }
    })

    it('adding a duplicate token fails', async () => {
        try {
            await this.core.whitelistTokens([this.reserves[3].address])
            assert.fail('expected to revert')
        } catch(e) {
            assert.equal(e.reason, 'Adding a duplicate token')
        }
    })

    describe('Only Owner', async () => {
        it('whitelistTokens fails', async () => {
            try {
                await this.core.whitelistTokens([this.reserves[3].address], { from: accounts[1]})
                assert.fail('expected to revert')
            } catch(e) {
                assert.equal(e.reason, 'NOT_OWNER')
            }
        })

        it('setPeakStatus fails', async () => {
            try {
                await this.core.setPeakStatus(accounts[0], 0, 1, { from: accounts[1]})
                assert.fail('expected to revert')
            } catch(e) {
                assert.equal(e.reason, 'NOT_OWNER')
            }
        })

        it('authorizeController fails', async () => {
        try {
            await this.core.authorizeController(accounts[0], { from: accounts[1] })
            assert.fail('expected to revert')
        } catch (e) {
            assert.strictEqual(e.reason, 'NOT_OWNER')
        }
    })
    })
})
