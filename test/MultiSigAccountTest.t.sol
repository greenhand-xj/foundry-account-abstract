// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {MultiSigAccount} from "src/MultiSigAccount.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {PackedUserOperation} from "lib/account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {IEntryPoint} from "lib/account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {EntryPoint} from "lib/account-abstraction/contracts/core/EntryPoint.sol";

contract MultiSigAccountTest is Test {
    using MessageHashUtils for bytes32;

    MultiSigAccount multiSigAccount;
    IEntryPoint entryPoint;
    ERC20Mock usdc;

    uint256 signer1Key;
    uint256 signer2Key;
    uint256 signer3Key;
    address signer1;
    address signer2;
    address signer3;

    address randomuser = makeAddr("randomUser");
    uint256 constant AMOUNT = 1e18;

    function setUp() public {
        // Create 3 signers with known private keys
        (signer1, signer1Key) = makeAddrAndKey("signer1");
        (signer2, signer2Key) = makeAddrAndKey("signer2");
        (signer3, signer3Key) = makeAddrAndKey("signer3");

        // Deploy EntryPoint
        entryPoint = new EntryPoint();

        // Sort signers by address (ascending) for consistent test ordering
        address[] memory signers = _sortSigners(signer1, signer2, signer3);

        // Deploy MultiSigAccount: 2-of-3
        multiSigAccount = new MultiSigAccount(address(entryPoint), signers, 2);

        usdc = new ERC20Mock();
    }

    function testValidMultiSigPassesValidation() public {
        // Arrange
        bytes memory functionData = abi.encodeWithSelector(ERC20Mock.mint.selector, address(multiSigAccount), AMOUNT);
        bytes memory executeCallData =
            abi.encodeWithSelector(MultiSigAccount.execute.selector, address(usdc), 0, functionData);

        PackedUserOperation memory userOp = _generateUnsignedUserOp(executeCallData, address(multiSigAccount));
        bytes32 userOpHash = entryPoint.getUserOpHash(userOp);

        // Sign with 2 signers (sorted by address ascending)
        userOp.signature = _signWithTwoSigners(userOpHash);

        vm.deal(address(multiSigAccount), 1e18);

        // Act
        vm.prank(address(entryPoint));
        uint256 validationData = multiSigAccount.validateUserOp(userOp, userOpHash, 1e18);

        // Assert
        assertEq(validationData, 0);
    }

    function testInsufficientSignaturesFails() public {
        // Arrange
        bytes memory functionData = abi.encodeWithSelector(ERC20Mock.mint.selector, address(multiSigAccount), AMOUNT);
        bytes memory executeCallData =
            abi.encodeWithSelector(MultiSigAccount.execute.selector, address(usdc), 0, functionData);

        PackedUserOperation memory userOp = _generateUnsignedUserOp(executeCallData, address(multiSigAccount));
        bytes32 userOpHash = entryPoint.getUserOpHash(userOp);

        // Sign with only 1 signer (need 2)
        bytes32 digest = userOpHash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer1Key, digest);
        bytes[] memory sigs = new bytes[](1);
        sigs[0] = abi.encodePacked(r, s, v);
        userOp.signature = abi.encode(sigs);

        vm.deal(address(multiSigAccount), 1e18);

        // Act
        vm.prank(address(entryPoint));
        uint256 validationData = multiSigAccount.validateUserOp(userOp, userOpHash, 1e18);

        // Assert: SIG_VALIDATION_FAILED = 1
        assertEq(validationData, 1);
    }

    function testInvalidSignerFails() public {
        // Arrange
        (address fakeSigner, uint256 fakeKey) = makeAddrAndKey("fakeSigner");

        bytes memory functionData = abi.encodeWithSelector(ERC20Mock.mint.selector, address(multiSigAccount), AMOUNT);
        bytes memory executeCallData =
            abi.encodeWithSelector(MultiSigAccount.execute.selector, address(usdc), 0, functionData);

        PackedUserOperation memory userOp = _generateUnsignedUserOp(executeCallData, address(multiSigAccount));
        bytes32 userOpHash = entryPoint.getUserOpHash(userOp);
        bytes32 digest = userOpHash.toEthSignedMessageHash();

        // Sign with one valid signer and one fake signer, sorted by address
        address[] memory pair = new address[](2);
        uint256[] memory keys = new uint256[](2);
        if (uint160(signer1) < uint160(fakeSigner)) {
            pair[0] = signer1;
            keys[0] = signer1Key;
            pair[1] = fakeSigner;
            keys[1] = fakeKey;
        } else {
            pair[0] = fakeSigner;
            keys[0] = fakeKey;
            pair[1] = signer1;
            keys[1] = signer1Key;
        }

        bytes[] memory sigs = new bytes[](2);
        for (uint256 i = 0; i < 2; i++) {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(keys[i], digest);
            sigs[i] = abi.encodePacked(r, s, v);
        }
        userOp.signature = abi.encode(sigs);

        vm.deal(address(multiSigAccount), 1e18);

        // Act
        vm.prank(address(entryPoint));
        uint256 validationData = multiSigAccount.validateUserOp(userOp, userOpHash, 1e18);

        // Assert: should fail
        assertEq(validationData, 1);
    }

    function testMultiSigFullFlow() public {
        // Arrange
        assertEq(usdc.balanceOf(address(multiSigAccount)), 0);
        bytes memory functionData = abi.encodeWithSelector(ERC20Mock.mint.selector, address(multiSigAccount), AMOUNT);
        bytes memory executeCallData =
            abi.encodeWithSelector(MultiSigAccount.execute.selector, address(usdc), 0, functionData);

        PackedUserOperation memory userOp = _generateUnsignedUserOp(executeCallData, address(multiSigAccount));
        bytes32 userOpHash = entryPoint.getUserOpHash(userOp);
        userOp.signature = _signWithTwoSigners(userOpHash);

        vm.deal(address(multiSigAccount), 1e18);
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;

        // Act
        vm.prank(randomuser);
        entryPoint.handleOps(ops, payable(randomuser));

        // Assert
        assertEq(usdc.balanceOf(address(multiSigAccount)), AMOUNT);
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

    function _signWithTwoSigners(bytes32 userOpHash) internal view returns (bytes memory) {
        bytes32 digest = userOpHash.toEthSignedMessageHash();

        // We need to pick 2 signers and sort them by address ascending
        // Use signer1, signer2, signer3 — pick two whose addresses are in ascending order
        address[] memory sorted = _sortSigners(signer1, signer2, signer3);
        uint256[] memory sortedKeys = new uint256[](3);
        for (uint256 i = 0; i < 3; i++) {
            if (sorted[i] == signer1) sortedKeys[i] = signer1Key;
            else if (sorted[i] == signer2) sortedKeys[i] = signer2Key;
            else sortedKeys[i] = signer3Key;
        }

        // Sign with the first two (lowest addresses)
        bytes[] memory sigs = new bytes[](2);
        for (uint256 i = 0; i < 2; i++) {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(sortedKeys[i], digest);
            sigs[i] = abi.encodePacked(r, s, v);
        }
        return abi.encode(sigs);
    }

    function _sortSigners(address a, address b, address c) internal pure returns (address[] memory) {
        address[] memory arr = new address[](3);
        arr[0] = a;
        arr[1] = b;
        arr[2] = c;
        // Simple bubble sort for 3 elements
        if (arr[0] > arr[1]) (arr[0], arr[1]) = (arr[1], arr[0]);
        if (arr[1] > arr[2]) (arr[1], arr[2]) = (arr[2], arr[1]);
        if (arr[0] > arr[1]) (arr[0], arr[1]) = (arr[1], arr[0]);
        return arr;
    }
}
