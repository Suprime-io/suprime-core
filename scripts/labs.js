const hre = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();

  const labsRegistry = await hre.ethers.deployContract("LabsRegistry", [])
  await labsRegistry.waitForDeployment();
  console.log(
    `LabsRegistry was deployed to ${await labsRegistry.getAddress()}`
  );

  //verify
  if (hre.network.name !== 'localhost') {
    console.log('Waiting before verification....')
    const delay = ms => new Promise(res => setTimeout(res, ms));
    await delay(15000);

    await hre.run("verify:verify", {
      address: await labsRegistry.getAddress()
    });

    await hre.tenderly.persistArtifacts({
      name: "LabsRegistry",
      address: await labsRegistry.getAddress(),
    })
  }

}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
