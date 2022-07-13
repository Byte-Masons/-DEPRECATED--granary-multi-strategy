async function main() {
  const stratFactory = await ethers.getContractFactory('ReaperStrategyGeist');
  const stratContract = await hre.upgrades.upgradeProxy('0x303DF25f303376ebb84D0F2F0139E7b0C7F3Bf43', stratFactory, {
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
