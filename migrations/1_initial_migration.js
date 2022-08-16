const Objects = artifacts.require("Objects");
const AIMP_SC = artifacts.require("AIMP_SC");
const AINFT = artifacts.require("AINFT");

module.exports = function (deployer) {
  deployer.deploy(Objects);
  deployer.link(Objects, [AIMP_SC]);
  deployer.deploy(AIMP_SC).then(function () {
    return deployer.deploy(AINFT, AIMP_SC.address);
  });

  //const modelAddr = deployer.deploy(AIMP_SC);
  //deployer.deploy(AINFT, modelAddr);

};
