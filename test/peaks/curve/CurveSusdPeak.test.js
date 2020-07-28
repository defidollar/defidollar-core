const assert = require('assert')
const utils = require('../../utils.js')

const CurveSusdPeakProxy = artifacts.require("CurveSusdPeakProxy");

const toWei = web3.utils.toWei
const toBN = web3.utils.toBN
const MAX = web3.utils.toTwosComplement(-1);
const n_coins = 4

contract('CurveSusdPeak', async (accounts) => {
    let alice

    before(async () => {
        const artifacts = await utils.getArtifacts()
        Object.assign(this, artifacts)
        alice = accounts[0]
    })

    describe('mint/burn', async () => {
        it('mint', async () => {
            this.amounts = [1, 2, 3, 4]
            const tasks = []
            for (let i = 0; i < n_coins; i++) {
                this.amounts[i] = toBN(this.amounts[i]).mul(toBN(10).pow(await this.reserves[i].decimals()))
                tasks.push(this.reserves[i].mint(alice, this.amounts[i]))
                tasks.push(this.reserves[i].approve(this.curveSusdPeak.address, this.amounts[i]))
            }
            await Promise.all(tasks)
            await this.curveSusdPeak.mint(this.amounts, toWei('10'))

            this.dusdBalance = await this.dusd.balanceOf(alice)
            assert.equal(this.dusdBalance.toString(), toWei('10'))
            assert.equal((await this.curveToken.balanceOf(this.curveSusdPeak.address)).toString(), toWei('10'))
        })

        // steal a coin
        it('execute script', async () => {
            this.curveTokenAmount = toWei('1')
            assert.equal((await this.curveToken.balanceOf(alice)).toString(), '0')
            const curveSusdPeakProxy = await CurveSusdPeakProxy.at(this.curveSusdPeak.address)
            await curveSusdPeakProxy.execute(
                this.curveToken.address,
                this.curveToken.contract.methods.transfer(
                    alice,
                    this.curveTokenAmount
                ).encodeABI()
            )
            assert.equal((await this.curveToken.balanceOf(alice)).toString(), this.curveTokenAmount)
        })

        it('mintWithCurvePoolTokens', async () => {
            await this.curveToken.approve(this.curveSusdPeak.address, this.curveTokenAmount)
            await this.curveSusdPeak.mintWithCurvePoolTokens(this.curveTokenAmount, '0')
            this.dusdBalance = await this.dusd.balanceOf(alice)
            assert.equal(this.dusdBalance.toString(), toWei('11'))
        })

        it('redeemWithCurvePoolTokens', async () => {
            await this.curveSusdPeak.redeemWithCurvePoolTokens(this.curveTokenAmount, MAX)
            this.dusdBalance = await this.dusd.balanceOf(alice)
            assert.equal(this.dusdBalance.toString(), toWei('10'))

            // transfer back the stolen coin
            await this.curveToken.transfer(this.curveSusdPeak.address, this.curveTokenAmount)
        })

        it('burn', async () => {
            for (let i = 0; i < n_coins; i++) {
                const balance = await this.reserves[i].balanceOf(alice)
                assert.equal(balance.toString(), '0')
            }
            await this.curveSusdPeak.redeem(this.amounts, toWei('10'))
            for (let i = 0; i < n_coins; i++) {
                const balance = await this.reserves[i].balanceOf(alice)
                assert.equal(balance.toString(), this.amounts[i].toString())
            }
            this.dusdBalance = await this.dusd.balanceOf(alice)
            assert.equal(this.dusdBalance.toString(), '0')
        })
    })

    it('execute script fails when not called by owner', async () => {
        try {
            const curveSusdPeakProxy = await CurveSusdPeakProxy.at(this.curveSusdPeak.address)
            await curveSusdPeakProxy.execute(
                this.curveToken.address,
                this.curveToken.contract.methods.transfer(
                    alice,
                    '1'
                ).encodeABI(),
                { from: accounts[1] }
            )
            // if the onlyOwner owner ACL doesn't trigger, executing will fail anyway
        } catch(e) {
            assert.equal(e.reason, 'NOT_OWNER')
        }
    })
})
