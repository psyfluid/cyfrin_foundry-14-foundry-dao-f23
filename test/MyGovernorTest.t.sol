// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {MyGovernor} from "src/MyGovernor.sol";
import {Box} from "src/Box.sol";
import {TimeLock} from "src/TimeLock.sol";
import {GovToken} from "src/GovToken.sol";

contract MyGovernorTest is Test {
    MyGovernor governor;
    Box box;
    GovToken govToken;
    TimeLock timelock;

    address[] proposers;
    address[] executors;

    address[] targets;
    uint256[] values;
    bytes[] calldatas;

    address public user = makeAddr("user");
    uint256 public constant INITIAL_SUPPLY = 100 ether;
    uint256 public constant MIN_DELAY = 3600;
    uint256 public constant VOTING_DELAY = 7200;
    uint256 public constant VOTING_PERIOD = 50400;

    function setUp() public {
        govToken = new GovToken(address(this));
        govToken.mint(user, INITIAL_SUPPLY);

        vm.startPrank(user);
        govToken.delegate(user);
        timelock = new TimeLock(MIN_DELAY, proposers, executors, user);
        governor = new MyGovernor(govToken, timelock);

        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        bytes32 adminRole = timelock.DEFAULT_ADMIN_ROLE();

        timelock.grantRole(proposerRole, address(governor));
        timelock.grantRole(executorRole, address(0));
        timelock.revokeRole(adminRole, user);
        vm.stopPrank();

        box = new Box(address(timelock));
    }

    function testCantUpdateBoxWithoutGovernance() public {
        vm.expectRevert();
        box.store(1);
    }

    function testGovernanceUpdateBox() public {
        // 1. Propose to the DAO
        uint256 valueToStore = 888;
        string memory description = "Store 1 in Box";
        bytes memory encodedFunctionCall = abi.encodeWithSignature("store(uint256)", valueToStore);

        values.push(0);
        calldatas.push(encodedFunctionCall);
        targets.push(address(box));

        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        // View the proposal state
        console.log("Proposal state: ", uint256(governor.state(proposalId)));

        vm.warp(block.timestamp + VOTING_DELAY + 1);
        vm.roll(block.number + VOTING_DELAY + 1);

        console.log("Proposal state: ", uint256(governor.state(proposalId)));

        // 2. Vote
        string memory reason = "because";
        uint8 voteWay = 1; // support = voting FOR

        vm.prank(user);
        governor.castVoteWithReason(proposalId, voteWay, reason);

        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        vm.roll(block.number + VOTING_PERIOD + 1);

        // 3. Queue the TX
        bytes32 descriptionHash = keccak256(abi.encodePacked(description));
        governor.queue(targets, values, calldatas, descriptionHash);

        vm.warp(block.timestamp + MIN_DELAY + 1);
        vm.roll(block.number + MIN_DELAY + 1);

        // 4. Execute
        governor.execute(targets, values, calldatas, descriptionHash);

        console.log("Box value: ", box.getNumber());
        assertEq(box.getNumber(), valueToStore, "Box value should be 888");
    }
}
