// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {TaikoL2} from "../contracts/L2/TaikoL2.sol";
import {
    SafeCastUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";

contract TestTaikoL2 is Test {
    using SafeCastUpgradeable for uint256;
    uint32 public constant BLOCK_GAS_LIMIT = 30000000; // same as `block_gas_limit` in foundry.toml

    TaikoL2 public L2;
    uint private logIndex;

    function setUp() public {
        uint16 rand = 2;
        TaikoL2.EIP1559Params memory param1559 = TaikoL2.EIP1559Params({
            basefee: (uint(BLOCK_GAS_LIMIT * 10) * rand).toUint64(),
            gasIssuedPerSecond: 1000000,
            gasExcessMax: (uint(15000000) * 256 * rand).toUint64(),
            gasTarget: (uint(6000000) * rand).toUint64(),
            ratio2x1x: 111
        });

        L2 = new TaikoL2();
        L2.init(address(1), param1559); // Dummy address manager address.

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 30);

        // console2.log("basefee =", uint256(L2.basefee()));
        // console2.log("xscale =", uint256(L2.xscale()));
        // console2.log("yscale =", uint256(L2.yscale()));
        // console2.log("gasExcess =", uint256(L2.gasExcess()));
    }

    function testAnchorTxsBlocktimeConstant() external {
        uint64 firstBasefee;
        for (uint256 i = 0; i < 100; i++) {
            uint64 basefee = _getBasefeeAndPrint(0, BLOCK_GAS_LIMIT);
            vm.fee(basefee);

            if (firstBasefee == 0) {
                firstBasefee = basefee;
            } else {
                assertEq(firstBasefee, basefee);
            }

            vm.prank(L2.GOLDEN_TOUCH_ADDRESS());
            L2.anchor(12345, keccak256("a"), keccak256("b"));

            vm.roll(block.number + 1);
            vm.warp(block.timestamp + 30);
        }
    }

    function testAnchorTxsBlocktimeDecreasing() external {
        uint64 prevBasefee;

        for (uint256 i = 0; i < 32; i++) {
            uint64 basefee = _getBasefeeAndPrint(0, BLOCK_GAS_LIMIT);
            vm.fee(basefee);

            assertGe(basefee, prevBasefee);
            prevBasefee = basefee;

            vm.prank(L2.GOLDEN_TOUCH_ADDRESS());
            L2.anchor(12345, keccak256("a"), keccak256("b"));

            vm.roll(block.number + 1);
            vm.warp(block.timestamp + 30 - i);
        }
    }

    function testAnchorTxsBlocktimeIncreasing() external {
        uint64 prevBasefee;

        for (uint256 i = 0; i < 30; i++) {
            uint64 basefee = _getBasefeeAndPrint(0, BLOCK_GAS_LIMIT);
            vm.fee(basefee);

            if (prevBasefee != 0) {
                assertLe(basefee, prevBasefee);
            }
            prevBasefee = basefee;

            vm.prank(L2.GOLDEN_TOUCH_ADDRESS());
            L2.anchor(12345, keccak256("a"), keccak256("b"));

            vm.roll(block.number + 1);

            vm.warp(block.timestamp + 30 + i);
        }
    }

    // calling anchor in the same block more than once should fail
    function testAnchorTxsFailInTheSameBlock() external {
        uint64 expectedBasefee = _getBasefeeAndPrint(0, BLOCK_GAS_LIMIT);
        vm.fee(expectedBasefee);

        vm.prank(L2.GOLDEN_TOUCH_ADDRESS());
        L2.anchor(12345, keccak256("a"), keccak256("b"));

        vm.prank(L2.GOLDEN_TOUCH_ADDRESS());
        vm.expectRevert();
        L2.anchor(12345, keccak256("a"), keccak256("b"));
    }

    // calling anchor in the same block more than once should fail
    function testAnchorTxsFailByNonTaikoL2Signer() external {
        uint64 expectedBasefee = _getBasefeeAndPrint(0, BLOCK_GAS_LIMIT);
        vm.fee(expectedBasefee);
        vm.expectRevert();
        L2.anchor(12345, keccak256("a"), keccak256("b"));
    }

    function testAnchorSigning(bytes32 digest) external {
        (uint8 v, uint256 r, uint256 s) = L2.signAnchor(digest, uint8(1));
        address signer = ecrecover(digest, v + 27, bytes32(r), bytes32(s));
        assertEq(signer, L2.GOLDEN_TOUCH_ADDRESS());

        (v, r, s) = L2.signAnchor(digest, uint8(2));
        signer = ecrecover(digest, v + 27, bytes32(r), bytes32(s));
        assertEq(signer, L2.GOLDEN_TOUCH_ADDRESS());

        vm.expectRevert();
        L2.signAnchor(digest, uint8(0));

        vm.expectRevert();
        L2.signAnchor(digest, uint8(3));
    }

    function testGetBasefee1() external {
        assertEq(_getBasefeeAndPrint(0, 0), 317609019);
        assertEq(_getBasefeeAndPrint(0, 1), 317609019);
        assertEq(_getBasefeeAndPrint(0, 1000000), 320423332);
        assertEq(_getBasefeeAndPrint(0, 5000000), 332018053);
        assertEq(_getBasefeeAndPrint(0, 10000000), 347305199);
    }

    function testGetBasefee2() external {
        assertEq(_getBasefeeAndPrint(100, 0), 54544902);
        assertEq(_getBasefeeAndPrint(100, 1), 54544902);
        assertEq(_getBasefeeAndPrint(100, 1000000), 55028221);
        assertEq(_getBasefeeAndPrint(100, 5000000), 57019452);
        assertEq(_getBasefeeAndPrint(100, 10000000), 59644805);
    }


    function _getBasefeeAndPrint( uint32 timeSinceNow,
        uint64 gasLimit) private returns (uint64 _basefee) {



      uint256 timeSinceParent=  timeSinceNow + block.timestamp - L2.parentTimestamp();
      uint256 gasIssued = L2.gasIssuedPerSecond() * timeSinceParent;
        string memory msg = string.concat("#",
            Strings.toString(logIndex++),
            ": gasExcess=", Strings.toString(L2.gasExcess()),
            ", timeSinceParent=", Strings.toString(timeSinceParent),
            ", gasIssued=", Strings.toString(gasIssued),
            ", gasLimit=", Strings.toString(gasLimit)
            );
        _basefee = L2.getBasefee(timeSinceNow, gasLimit);

        msg = string.concat(msg,
", gasExcess(changed)=", Strings.toString(L2.gasExcess()),
", basefee=", Strings.toString(_basefee)
            );

        console2.log(msg);
    }
}
