// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";
import "forge-std/Test.sol";
import "forge-std/console2.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";

import {MultiRolesAuthority} from
  "solmate/auth/authorities/MultiRolesAuthority.sol";

import {StratX4MasterchefLP1} from "../src/MasterchefLP1.sol";
import {
  StratConfigJsonLib,
  EarnConfig
} from "../src/json-parsers/StratConfigJsonLib.sol";

contract DeployStrat is Script, Test {
  using stdJson for string;

  StratX4MasterchefLP1 public strat;

  function run() public {
    vm.startBroadcast();
    deployStrat();
    vm.stopBroadcast();
  }

  function deployStrat() internal {
    string memory root = vm.projectRoot();
    string memory path = string.concat(root, vm.envString("STRAT_CONFIG_FILE"));
    string memory json = vm.readFile(path);

    (
      address asset,
      address farmContractAddress,
      uint256 pid,
      EarnConfig[] memory earnConfigs
    ) = StratConfigJsonLib.parse(vm, json);

    console2.log("asset", asset);
    console2.log("farmContractAddress", farmContractAddress);
    console2.log("pid", pid);

    strat = new StratX4MasterchefLP1(
      asset,
      vm.envAddress("FEES_CONTROLLER_ADDRESS"),
      MultiRolesAuthority(vm.envAddress("AUTHORITY_ADDRESS")),
      farmContractAddress,
      pid,
      earnConfigs[0].rewardToken,
      earnConfigs[0].swapRoute,
      earnConfigs[0].zapLiquidityConfig
    );
    for (uint256 i = 1; i < earnConfigs.length; i++) {
      strat.addEarnConfig(
        earnConfigs[i].rewardToken,
        abi.encode(earnConfigs[i].swapRoute, earnConfigs[i].zapLiquidityConfig)
      );
    }
  }
}
