// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {BasicPaymaster} from "src/BasicPaymaster.sol";
import {MinimalAccount} from "src/MinimalAccount.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {PackedUserOperation} from "lib/account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {IEntryPoint} from "lib/account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {EntryPoint} from "lib/account-abstraction/contracts/core/EntryPoint.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract BasicPaymasterTest is Test {
    using MessageHashUtils for bytes32;

    EntryPoint entryPoint;
    MinimalAccount minimalAccount;
    BasicPaymaster paymaster;
    ERC20Mock usdc;

    uint256 ownerKey;
    address owner;
    address randomuser = makeAddr("randomUser");
    uint256 constant AMOUNT = 1e18;

    function setUp() public {
        (owner, ownerKey) = makeAddrAndKey("owner");

        // Deploy EntryPoint
        entryPoint = new EntryPoint();

        // Deploy MinimalAccount owned by `owner`
        vm.prank(owner);
        minimalAccount = new MinimalAccount(address(entryPoint));

        // Deploy Paymaster
        paymaster = new BasicPaymaster(address(entryPoint));

        usdc = new ERC20Mock();

        // Fund the paymaster's deposit in EntryPoint
        paymaster.deposit{value: 10e18}();

        // Stake the paymaster (required by EntryPoint for validation)
        paymaster.addStake{value: 1e18}(1);
    }

    function testPaymasterDeposit() public view {
        // Assert
        uint256 deposit = paymaster.getDeposit();
        assertEq(deposit, 10e18);
    }

    function testPaymasterPaysForUser() public {
        // Arrange: user's account has NO ETH
        assertEq(address(minimalAccount).balance, 0);
        assertEq(usdc.balanceOf(address(minimalAccount)), 0);

        bytes memory functionData = abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), AMOUNT);
        bytes memory executeCallData =
            abi.encodeWithSelector(MinimalAccount.execute.selector, address(usdc), 0, functionData);

        PackedUserOperation memory userOp = _generateUnsignedUserOp(executeCallData, address(minimalAccount));

        // Set paymasterAndData to point to our paymaster
        userOp.paymasterAndData = _encodePaymasterAndData(address(paymaster));

        bytes32 userOpHash = entryPoint.getUserOpHash(userOp);
        bytes32 digest = userOpHash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, digest);
        userOp.signature = abi.encodePacked(r, s, v);

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;

        // Act: anyone can submit (the user doesn't need ETH)
        vm.prank(randomuser);
        entryPoint.handleOps(ops, payable(randomuser));

        // Assert: mint happened, user never had ETH
        assertEq(usdc.balanceOf(address(minimalAccount)), AMOUNT);
    }

    function testOwnerCanWithdrawFromPaymaster() public {
        // Arrange
        uint256 depositBefore = paymaster.getDeposit();
        address payable withdrawTo = payable(makeAddr("withdrawTo"));

        // Act
        paymaster.withdrawTo(withdrawTo, 5e18);

        // Assert
        assertEq(paymaster.getDeposit(), depositBefore - 5e18);
        assertEq(withdrawTo.balance, 5e18);
    }

    /*//////////////////////////////////////////////////////////////
                               HELPERS
    //////////////////////////////////////////////////////////////*/
    function _generateUnsignedUserOp(bytes memory callData, address sender)
        internal
        view
        returns (PackedUserOperation memory)
    {
        uint256 nonce = entryPoint.getNonce(sender, 0);
        uint128 verificationGasLimit = 16777216;
        uint128 callGasLimit = verificationGasLimit;
        uint128 maxPriorityFeePerGas = 256;
        uint128 maxFeePerGas = maxPriorityFeePerGas;

        return PackedUserOperation({
            sender: sender,
            nonce: nonce,
            initCode: hex"",
            callData: callData,
            accountGasLimits: bytes32(uint256(verificationGasLimit) << 128 | callGasLimit),
            preVerificationGas: verificationGasLimit,
            gasFees: bytes32(uint256(maxPriorityFeePerGas) << 128 | maxFeePerGas),
            paymasterAndData: hex"",
            signature: hex""
        });
    }

    function _encodePaymasterAndData(address paymasterAddr) internal pure returns (bytes memory) {
        // ERC-4337 v0.7 paymasterAndData format:
        // [paymaster address (20 bytes)][paymasterVerificationGasLimit (16 bytes)][paymasterPostOpGasLimit (16 bytes)][paymasterData (variable)]
        uint128 paymasterVerificationGasLimit = 16777216;
        uint128 paymasterPostOpGasLimit = 16777216;
        return abi.encodePacked(paymasterAddr, paymasterVerificationGasLimit, paymasterPostOpGasLimit);
    }
}
