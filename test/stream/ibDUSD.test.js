const assert = require('assert')

const ibDUSD = artifacts.require("ibDUSD");
const utils = require('../utils.js')

contract.only('ibDUSD', async (accounts) => {
    before(async () => {
        const artifacts = await utils.getArtifacts()
        Object.assign(this, artifacts)
        this.user = accounts[1]
        await this.core.whitelistPeak(accounts[0], [0, 1, 2, 3], utils.scale(10, 18), false)
    })

    it('authorizeController fails from non-admin account', async () => {
        try {
            await this.core.authorizeController(this.ibDusd.address, { from: accounts[1] })
            assert.fail('expected to revert')
        } catch (e) {
            assert.strictEqual(e.reason, 'NOT_OWNER')
        }
    })

    it('authorizeController ', async () => {
        assert.strictEqual(await this.core.authorizedController(), utils.ZERO_ADDRESS)
        await this.core.authorizeController(this.ibDusd.address)
        assert.strictEqual(await this.core.authorizedController(), this.ibDusd.address)
    })
})
