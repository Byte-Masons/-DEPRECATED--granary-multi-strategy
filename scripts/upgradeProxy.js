async function main() {
  const stratFactory = await ethers.getContractFactory('ReaperStrategyGeist');
  const stratContract = await hre.upgrades.upgradeProxy('0xB85e3e31cC226218bFc3a43DE181370CfE3F96FA', stratFactory, {
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
