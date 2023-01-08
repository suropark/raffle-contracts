const ENTRANCE_FEE = ethers.utils.parseEther("0.1");

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  console.log(deploy, deployer);

  const args = [
    ENTRANCE_FEE,
    "300",
    "0x7a1bac17ccc5b313516c5e16fb24f7659aa5ebed",
    "0x4b09e658ed251bcafeebbc69400383d49f344ace09b9576fe248bb02c003fe9f",
    "2989",
    "500000",
  ];
  await deploy("SimpleRaffle", {
    from: deployer,
    args,
    log: true,
  });
};