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
import {AutoSwapV5} from "autofarm-v3-core/Autoswap.sol";
import {DeployStrat} from "../../script/deploy-strat.sol";

contract TestStratDeployment is Test, DeployStrat {
  using stdJson for string;

  StratX4Compounding public strat;

  function setUp() public {
    vm.createSelectFork(vm.rpcUrl("evmos"));
    run();
    strat = StratX4Compounding(stratAddress);
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

  // TODO: test all reward tokens instead of only main
  function testCompound() public {
    deal(address(strat.mainRewardToken()), address(strat), 1 ether);

    console2.log('feeRate', strat.feeRate());

    address rewardToken = strat.mainRewardToken();
    vm.prank(vm.envAddress("KEEPER_ADDRESS"));
    (uint256 compoundedAssets,,) = strat.earn(rewardToken, 1);
    console2.log('compoundedAssets', compoundedAssets);
    assertGt(compoundedAssets, 0, "earn harvests less than expected harvest");
  }

  // TODO: test all reward tokens instead of only main
  function testEarn() public {
    uint256 amountIn = 1e18;
    deal(address(strat.asset()), address(this), amountIn);
    strat.asset().approve(address(strat), type(uint256).max);
    strat.deposit(amountIn, address(this));
    assertGt(strat.totalAssets(), 0, "Deposit did not increase totalAssets");
    vm.roll(block.number + 1000);
    vm.warp(block.timestamp + 1000);

    address rewardToken = strat.mainRewardToken();
    vm.prank(vm.envAddress("KEEPER_ADDRESS"));
    (uint256 compoundedAssets,uint256 earnedAmount,) = strat.earn(rewardToken, 1);
    assertGt(earnedAmount, 0, "Nothing earned");
    assertGt(compoundedAssets, 0, "earn harvests less than expected harvest");
  }
}
