# Foundry Account Abstraction

基于 ERC-4337 的以太坊账户抽象实现，包含单签钱包、多签钱包和 Paymaster。

## 合约概述

| 合约 | 功能 |
|------|------|
| `MinimalAccount.sol` | 最小单签 AA 钱包，单 owner 验证 |
| `MultiSigAccount.sol` | 多签 AA 钱包，M-of-N 签名验证 |
| `BasicPaymaster.sol` | 代付 gas 的 Paymaster |

## 快速开始

### 安装依赖

```shell
forge install
```

### 构建

```shell
forge build
```

### 测试

```shell
forge test
```

### 格式检查

```shell
forge fmt --check
```

### 部署

```shell
# 部署到本地
anvil

forge script script/DeployMinimal.s.sol:DeployMinimal --rpc-url http://localhost:8545 --broadcast
```

## 目录结构

```
src/
├── MinimalAccount.sol      # 单签钱包
├── MultiSigAccount.sol    # 多签钱包
└── BasicPaymaster.sol     # Paymaster

script/
├── HelperConfig.s.sol      # 网络配置
├── DeployMinimal.s.sol     # 部署脚本
└── SendPackedUserOp.s.sol  # 构造 UserOp

test/
├── MinimalAccountTest.t.sol
├── MultiSigAccountTest.t.sol
└── BasicPaymasterTest.t.sol
```

## 核心概念

### ERC-4337 UserOp 流程

1. 用户构造 `PackedUserOperation` (含 callData、签名等)
2. Bundler 提交到 EntryPoint
3. EntryPoint 调用 `validateUserOp` 验证签名
4. EntryPoint 调用 `execute` 执行操作

### MinimalAccount

- 继承 `Ownable`，owner 可直接调用 `execute`
- EntryPoint 只能通过 `validateUserOp` 调用

### MultiSigAccount

- 支持 M-of-N 多签
- 签名需严格递增排序
- 可通过多签交易添加/移除 signer

### BasicPaymaster

- 无条件接受 UserOp (演示用)
- Owner 存入 ETH 到 EntryPoint 供用户使用
- 支持 stake、withdraw 操作

## 学习资源

详细学习指南见 [LEARNING_GUIDE.md](./LEARNING_GUIDE.md)