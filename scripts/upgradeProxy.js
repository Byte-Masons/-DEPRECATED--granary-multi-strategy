async function main() {
  const stratFactory = await ethers.getContractFactory('ReaperStrategyGranary');
  const stratContract = await hre.upgrades.upgradeProxy('0x6613B0772F9841A0a21e14B7ce422760F7f22CAB', stratFactory, {
    timeout: 0,
  });
  console.log('Strategy upgraded!');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
