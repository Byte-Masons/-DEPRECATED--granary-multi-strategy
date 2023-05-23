async function main() {
  const oathAddr = '0x21ada0d2ac28c3a5fa3cd2ee30882da8812279b6';
  // const staderAddr = '0x412a13C109aC30f0dB80AD3Bd1DeFd5D0A6c0Ac6';
  const usdcAddr = '0x04068DA6C83AFCFA0e13ba15A6696662335D5B75';
  const stratAddress = '0xc99911Af7594964C399f605840d1107E98602aD4';
  const wantAddress = '0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83';
  const Strat = await ethers.getContractFactory('ReaperStrategyGranary');
  const strat = Strat.attach(stratAddress);

  // step 1: swap all of OATH -> wFTM using path OATH -> USDC -> wFTM
  const step1 = [oathAddr, usdcAddr, wantAddress];
  // step 2: swap all of SD -> USDC using path SD -> USDC
  // const step2 = [staderAddr, usdcAddr];
  // step 3: convert all remaining USDC -> wFTM
  // const step3 = [usdcAddr, wantAddress];

  await strat.setHarvestSteps([step1 /*, step2, step3 */]);
  console.log('Harvest Steps Added');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
