async function main() {
    const YVaultPeak = await ethers.getContractFactory('YVaultPeak')
    const peak = await YVaultPeak.deploy()
    console.log(peak.address)
}

main()
.then(() => process.exit(0))
.catch(error => {
    console.error(error);
    process.exit(1);
});
