const { expect } = require("chai");
const { BigNumber } = ethers

constants = {
    _1e18: ethers.constants.WeiPerEther,
    _1e8: BigNumber.from(10).pow(8),
    _1e6: BigNumber.from(10).pow(6),
    ZERO: BigNumber.from(0),
}

const {
    setupMainnetContracts,
    impersonateAccount
} = require('./utils')

const dfdMultisig = '0x5b5cf8620292249669e1dcc73b753d01543d6ac7'

describe('Migration (mainnet-fork)', function() {
    before('setup contracts', async function() {
        signers = await ethers.getSigners()
        alice = signers[0].address
        peakProxy = await setupMainnetContracts()
    })

    it('migrate', async function() {
        ;([ YVaultPeak, peak, dusd, ycrv, yUSD, newYusd ] = await Promise.all([
            ethers.getContractFactory('YVaultPeak'),
            ethers.getContractAt('YVaultPeak', peakProxy.address),
            ethers.getContractAt('IERC20', '0x5BC25f649fc4e26069dDF4cF4010F9f706c23831'),
            ethers.getContractAt('IERC20', '0xdF5e0e81Dff6FAF3A7e52BA697820c5e32D806A8'),
            ethers.getContractAt('IERC20', '0x5dbcF33D8c2E976c6b560249878e6F1491Bca25c'),
            ethers.getContractAt('IERC20', '0x4B5BfD52124784745c1071dcB244C6688d2533d3')
        ]))
        // const peakImpl = await YVaultPeak.deploy()
        const peakImpl = await ethers.getContractAt('YVaultPeak', '0xee39e4a6820ffc4edaa80fd3b5a59788d515832b')
        await impersonateAccount(dfdMultisig)

        const ycrvBal = await ycrv.balanceOf(peak.address)
        const oldPV = await peak.portfolioValue()

        console.log({
            oldPV: oldPV.div(constants._1e18).toString(),
        })
        console.log(peakProxy.interface.encodeFunctionData('updateAndCall', [ peakImpl.address, peakImpl.interface.encodeFunctionData('migrate', []) ]))
        await peakProxy.connect(ethers.provider.getSigner(dfdMultisig)).updateAndCall(peakImpl.address, peakImpl.interface.encodeFunctionData('migrate', []))

        expect(await ycrv.balanceOf(peak.address)).to.eq(ycrvBal)
        expect(await yUSD.balanceOf('0x88ff54ed47402a97f6e603737f26bb9e4e6cb03d')).to.eq(constants.ZERO)

        console.log({
            newPV: (await peak.portfolioValue()).div(constants._1e18).toString(),
            dusd: (await dusd.totalSupply()).div(constants._1e18).toString(),
            newYusdBal: (await newYusd.balanceOf(peak.address)).div(constants._1e18).toString()
        })
    })

    it('mint', async function() {
        zap = await ethers.getContractAt('YVaultZap', '0xdE1F578292e75F26dfaebc78Aa0eCcca45b13521')
        const usdc = await ethers.getContractAt('IERC20', '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48')
        const amount = constants._1e6.mul(10000000)
        await getUsdc(alice, amount)
        await usdc.approve(zap.address, amount)
        await zap.mint([0,amount,0,0], 0)
        console.log({
            portfolioValue: (await peak.portfolioValue()).div(constants._1e18).toString(),
            dusd: (await dusd.totalSupply()).div(constants._1e18).toString(),
            bal: (await dusd.balanceOf(alice)).div(constants._1e18).toString(),
            newYusdBal: (await newYusd.balanceOf(peak.address)).div(constants._1e18).toString()
        })
    })

    it('redeem', async function() {
        const amount = await dusd.balanceOf(alice)
        await dusd.approve(zap.address, amount)
        await zap.redeem(amount, [0,0,0,0])
        const [dai, usdt, tusd] = await Promise.all([
            ethers.getContractAt('IERC20', '0x6B175474E89094C44Da98b954EedeAC495271d0F'),
            ethers.getContractAt('IERC20', '0xdAC17F958D2ee523a2206206994597C13D831ec7'),
            ethers.getContractAt('IERC20', '0x0000000000085d4780B73119b644AE5ecd22b376'),
        ])
        console.log((await dai.balanceOf(alice)).div(constants._1e18).toString())
        console.log((await usdt.balanceOf(alice)).div(constants._1e6).toString())
        console.log((await tusd.balanceOf(alice)).div(constants._1e18).toString())
    })

    it('savings.withdraw', async function() {
        const account = '0x6d3ee34a020e7565e78540c74300218104c8e4a9'
        const ibDusd = await ethers.getContractAt('ibDUSD', '0x42600c4f6d84aa4d246a3957994da411fa8a4e1c')
        const bal = await ibDusd.balanceOf(account)
        console.log({
            bal: (await dusd.balanceOf(account)).div(constants._1e18).toString()
        })
        await impersonateAccount(account)
        await ibDusd.connect(ethers.provider.getSigner(account)).withdraw(bal)
        console.log({
            bal: (await dusd.balanceOf(account)).div(constants._1e18).toString()
        })
    })
})

async function getUsdc(account, amount) {
    const usdcWhale = '0xBE0eB53F46cd790Cd13851d5EFf43D12404d33E8'
    const usdc = await ethers.getContractAt('IERC20', '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48')
    await impersonateAccount(usdcWhale)
    return usdc.connect(ethers.provider.getSigner(usdcWhale)).transfer(account, amount)
}
