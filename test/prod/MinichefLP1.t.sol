// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";

import {LibString} from "solmate/utils/LibString.sol";
import {MultiRolesAuthority} from
  "solmate/auth/authorities/MultiRolesAuthority.sol";

import {StratX4Compounding} from "autofarm-v3-core/StratX4Compounding.sol";
import {
  StratConfigJsonLib,
  EarnConfig
} from "../../src/json-parsers/StratConfigJsonLib.sol";

string constant STRAT_CONFIG_FILE = "/vaults-config/evmos/diffusion-WEVMOS-ceUSDC.json";

contract TestStrat is Test {
  using stdJson for string;

  StratX4Compounding public strat;

  function setUp() public {
    vm.createSelectFork(vm.rpcUrl("evmos"));
    deployStrat();
  }

  function deploy(bytes memory creationCode, bytes memory args) internal returns (address deployed) {
    bytes memory bytecode = abi.encodePacked(creationCode, args);
    assembly {
      deployed := create(0, add(bytecode, 0x20), mload(bytecode))
    }
  }

  function deployStrat() internal {
    string memory root = vm.projectRoot();
    string memory path = string.concat(root, STRAT_CONFIG_FILE);
    string memory json = vm.readFile(path);
    string memory stratContract = json.readString(".StratContract");
    bytes memory creationCode = vm.getCode(stratContract);
    (
      address asset,
      address farmContractAddress,
      uint256 pid,
      EarnConfig[] memory earnConfigs
    ) = StratConfigJsonLib.parse(vm, json);

    console2.log("asset", asset);
    console2.log("farmContractAddress", farmContractAddress);
    console2.log("pid", pid);

    bytes memory args = abi.encode(
      asset,
      vm.envAddress("FEES_CONTROLLER_ADDRESS"),
      MultiRolesAuthority(vm.envAddress("AUTHORITY_ADDRESS")),
      farmContractAddress,
      pid,
      earnConfigs[0].rewardToken,
      earnConfigs[0].swapRoute,
      earnConfigs[0].zapLiquidityConfig
    );
    vm.startPrank(vm.envAddress("KEEPER_CALLER_ADDRESS"));
    strat = StratX4Compounding(deploy(creationCode, args));

    for (uint256 i = 1; i < earnConfigs.length; i++) {
      StratX4Compounding(strat).addEarnConfig(
        earnConfigs[i].rewardToken,
        abi.encode(earnConfigs[i].swapRoute, earnConfigs[i].zapLiquidityConfig)
      );
    }
    vm.stopPrank();
  }

  function testDepositAndWithdraw(uint96 amountIn, uint96 amountOut) public {
    vm.assume(amountIn > 1e18);

    address user = makeAddr("user");
    vm.startPrank(user);

    deal(address(strat.asset()), user, amountIn);
    strat.asset().approve(address(strat), type(uint256).max);
    uint256 initialBalance = strat.asset().balanceOf(user);

    strat.deposit(amountIn, user);

    uint256 shares = ERC20(address(strat)).balanceOf(user);
    uint256 balance = strat.asset().balanceOf(user);
    amountOut = uint96(bound(amountOut, 1e16, strat.totalAssets()));

    assertApproxEqRel(
      strat.totalAssets(), amountIn, 0.1e18, "totalAssets must increase"
    );
    assertEq(shares, amountIn, "shares must be minted");
    assertEq(initialBalance - balance, amountIn, "user balance must decrease");

    strat.withdraw(amountOut, user, user);
    shares = ERC20(address(strat)).balanceOf(user);
    balance = strat.asset().balanceOf(user);
    // TODO: restore
    assertApproxEqRel(
      shares, amountIn - amountOut, 0.1e18, "remaining shares wonky"
    );
    assertApproxEqRel(balance, amountOut, 0.1e18, "final balance wonky");
  }

  function testEarn() public {
    deal(address(strat.mainRewardToken()), address(strat), 1 ether);

    console2.log('feeRate', strat.feeRate());

    address rewardToken = strat.mainRewardToken();
    vm.prank(vm.envAddress("KEEPER_ADDRESS"));
    (uint256 compoundedAssets,,) = strat.earn(rewardToken, 1);
    console2.log('compoundedAssets', compoundedAssets);
    assertGt(compoundedAssets, 0, "earn harvests less than expected harvest");
  }

  function testHarvestAndEarn() public {
    uint256 amountIn = 1e18;
    deal(address(strat.asset()), address(this), amountIn);
    strat.asset().approve(address(strat), type(uint256).max);
    strat.deposit(amountIn, address(this));
    vm.roll(block.number + 5000);

    address rewardToken = strat.mainRewardToken();
    vm.prank(vm.envAddress("KEEPER_ADDRESS"));
    (uint256 compoundedAssets,,) = strat.earn(rewardToken, 1);
    assertGt(compoundedAssets, 0, "earn harvests less than expected harvest");
  }

  /*
  function testLeverage() public {
    uint256 amountIn = 1e18;

    deal(address(strat.asset()), address(this), amountIn);
    strat.asset().approve(address(strat), type(uint256).max);
    uint256 initialBalance = strat.asset().balanceOf(address(this));

    strat.deposit(amountIn, address(this));

    uint256 shares = ERC20(address(strat)).balanceOf(address(this));
    uint256 balance = strat.asset().balanceOf(address(this));
    strat.leverage();
    strat.leverage();
    vm.roll(block.number + 1000);
  }

  function testGetRate() public {
    uint256 borrowRate = strat.getBorrowRateAtLeverageDepth(0.9e18, 2);
    emit log_named_decimal_uint("borrowRate", borrowRate, 18);
  }
  */
}
