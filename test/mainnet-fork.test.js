const assert = require('assert')
const utils = require('./utils.js');

const toWei = web3.utils.toWei
const toBN = web3.utils.toBN
const MAX = web3.utils.toTwosComplement(-1);
const n_coins = 4
let _artifacts

const daiABI = require('./abi/dai.json');

// userAddress must be unlocked using --unlock ADDRESS
const userAddress = '0x07bb41df8c1d275c4259cdd0dbf0189d6a9a5f32'
const daiAddress = '0x6B175474E89094C44Da98b954EedeAC495271d0F'

contract.skip('Mainnet fork', async (accounts) => {
	const alice = accounts[0]
    const bob = accounts[1]
    const dai = new web3.eth.Contract(daiABI, daiAddress);

    before(async () => {
		_artifacts = await utils.getArtifacts()
        Object.assign(this, _artifacts)
    })

    it('mint initial_coin', async () => {
        this.amount = toWei('100')
        let daiBalance = await dai.methods.balanceOf(alice).call();
        console.log({ daiBalance })
        await dai.methods
            .transfer(alice, this.amount)
            .send({ from: userAddress, gasLimit: 800000 });
        daiBalance = await dai.methods.balanceOf(alice).call();
        console.log({ daiBalance })
    })

    it('alice mints 110 dusd', async () => {
        this.amounts = [30, 30, 30, 20].map((n, i) => {
            return toBN(n).mul(toBN(10 ** this.decimals[i]))
        })
        const tasks = []
        for (let i = 0; i < n_coins; i++) {
            tasks.push(this.reserves[i].mint(bob, this.amounts[i]))
            tasks.push(this.reserves[i].approve(this.curveSusdPeak.address, this.amounts[i], { from: bob }))
        }
        await Promise.all(tasks)
        await this.curveSusdPeak.mint(this.amounts, toWei('110'), { from: bob })
    })
})
