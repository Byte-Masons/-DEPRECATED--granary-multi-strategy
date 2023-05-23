const { loadFixture, reset } = require("@nomicfoundation/hardhat-network-helpers");
const { ethers, upgrades } = require("hardhat");

const superAdminAddress = "0x04C710a1E8a738CDf7cAD3a52Ba77A784C35d8CE";
const strategistAddr = "0x1E71AEE6081f62053123140aacC7a06021D77348";

const wftmProxy = "0xeaC9d3DFD1AEa8C27FbA6B1A630d28Ad2a904E6e";
const strategyProxy = wftmProxy;
const wftmAddress = "0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83";
const grainAddress = "0x02838746d9e1413e07ee064fcbada57055417f21";
const usdcAddress = "0x04068DA6C83AFCFA0e13ba15A6696662335D5B75";
const oatsAndGrainsBalPoolId = "0x21bbfc5681d9e171677dbd1a85a9ab15df82ad86000100000000000000000708";
const VELODROME = 0;
const BEETHOVEN = 1;
const UNIV3 = 2;
const UNIV2 = 3;

describe("Vaults", function () {
  async function upgradeStrategy() {
    await reset("https://rpc.ftm.tools", 62521807);

    // get signers
    const [owner] = await ethers.getSigners();
    const strategist = await ethers.getImpersonatedSigner(strategistAddr);
    const superAdmin = await ethers.getImpersonatedSigner(superAdminAddress);

    // get artifacts
    const Strategy = await ethers.getContractFactory("ReaperStrategyGranary");
    const StrategyV2 = await ethers.getContractFactory("ReaperStrategyGranaryV2");
    const Want = await ethers.getContractFactory("ERC20");

    // prepare upgrade
    const deployedProxyContract = await upgrades.forceImport(strategyProxy, Strategy, { kind: "uups" });
    const newImplAddress = await upgrades.prepareUpgrade(
      deployedProxyContract,
      StrategyV2,
      { kind: "uups" },
    );

    // send gas to superAdmin
    const tx = await owner.sendTransaction({
      to: superAdminAddress,
      value: ethers.utils.parseEther("10"),
    });
    await tx.wait();

    // upgrade proxy
    await deployedProxyContract.connect(superAdmin).upgradeTo(newImplAddress);
    const strategy = await upgrades.forceImport(strategyProxy, StrategyV2, { kind: "uups" });
    const grain = Want.attach(grainAddress);

    return { strategy, grain, owner, strategist, superAdmin };
  }

  describe("Successful V2 upgrade", function () {
    it("can set new harvest steps and harvest", async function () {
      const { strategy, superAdmin, strategist, grain } = await loadFixture(upgradeStrategy);

      const step1 = {
        dex: BEETHOVEN,
        start: grainAddress,
        end: wftmAddress,
      };
      const steps = [step1];
      await strategy.connect(superAdmin).setHarvestSteps(steps);

      await strategy.connect(strategist).updateBalSwapPoolID(
        grainAddress, wftmAddress, oatsAndGrainsBalPoolId,
      );

      const stratInitGrainBal = await grain.balanceOf(strategy.address);
      console.log(`Strategy initial grain balance: ${ethers.utils.formatEther(stratInitGrainBal)}`);

      const anticipatedRoi = await strategy.connect(strategist).callStatic.harvest();
      await strategy.connect(strategist).harvest();
      const stratFinalGrainBal = await grain.balanceOf(strategy.address);
      console.log(`Strategy final grain balance: ${ethers.utils.formatEther(stratFinalGrainBal)}`);

      const grainConsumed = stratInitGrainBal.sub(stratFinalGrainBal);
      console.log(`Used ${ethers.utils.formatEther(grainConsumed)} grain`);
      console.log(`Produced ${ethers.utils.formatUnits(anticipatedRoi, 18)} wftm`);
    });

    it("can harvest using equalizer", async function () {
      const { strategy, superAdmin, strategist, grain } = await loadFixture(upgradeStrategy);

      const step1 = {
        dex: VELODROME,
        start: grainAddress,
        end: wftmAddress,
      };

      const steps = [step1];
      await strategy.connect(superAdmin).setHarvestSteps(steps);

      await strategy.connect(strategist).updateVeloSwapPath(
        grainAddress, wftmAddress, [grainAddress, wftmAddress],
      );

      const stratInitGrainBal = await grain.balanceOf(strategy.address);
      console.log(`Strategy initial grain balance: ${ethers.utils.formatEther(stratInitGrainBal)}`);

      const anticipatedRoi = await strategy.connect(strategist).callStatic.harvest();
      await strategy.connect(strategist).harvest();
      const stratFinalGrainBal = await grain.balanceOf(strategy.address);
      console.log(`Strategy final grain balance: ${ethers.utils.formatEther(stratFinalGrainBal)}`);

      const grainConsumed = stratInitGrainBal.sub(stratFinalGrainBal);
      console.log(`Used ${ethers.utils.formatEther(grainConsumed)} grain`);
      console.log(`Produced ${ethers.utils.formatUnits(anticipatedRoi, 18)} wftm`);
    });

    it("can harvest using spooky", async function () {
      const { strategy, superAdmin, strategist, grain } = await loadFixture(upgradeStrategy);

      const step1 = {
        dex: BEETHOVEN,
        start: grainAddress,
        end: usdcAddress,
      };

      const step2 = {
        dex: UNIV2,
        start: usdcAddress,
        end: wftmAddress,
      };

      const steps = [step1, step2];
      await strategy.connect(superAdmin).setHarvestSteps(steps);

      await strategy.connect(strategist).updateBalSwapPoolID(
        grainAddress, usdcAddress, oatsAndGrainsBalPoolId,
      );

      const stratInitGrainBal = await grain.balanceOf(strategy.address);
      console.log(`Strategy initial grain balance: ${ethers.utils.formatEther(stratInitGrainBal)}`);

      const anticipatedRoi = await strategy.connect(strategist).callStatic.harvest();
      await strategy.connect(strategist).harvest();
      const stratFinalGrainBal = await grain.balanceOf(strategy.address);
      console.log(`Strategy final grain balance: ${ethers.utils.formatEther(stratFinalGrainBal)}`);

      const grainConsumed = stratInitGrainBal.sub(stratFinalGrainBal);
      console.log(`Used ${ethers.utils.formatEther(grainConsumed)} grain`);
      console.log(`Produced ${ethers.utils.formatUnits(anticipatedRoi, 18)} wftm`);
    });
  });
});