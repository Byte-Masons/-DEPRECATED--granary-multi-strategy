async function main() {
  const stratFactory = await ethers.getContractFactory('ReaperStrategyGranary');
  const stratContract = await hre.upgrades.upgradeProxy('', stratFactory, {
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
