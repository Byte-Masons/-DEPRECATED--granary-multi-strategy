async function main() {
  const stratFactory = await ethers.getContractFactory('ReaperStrategyGeist');
  const stratContract = await hre.upgrades.upgradeProxy('0x78c436272fA7d3CFEf1cEE0B3c14d9f5C4856647', stratFactory, {
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
