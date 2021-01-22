# stETH + Maker integration

TODO:
* [ ] Flipper
* [ ] Tests

### [LidoVault.vy](./contracts/LidoVault.vy)

Original repo: https://github.com/banteg/lido-vault.

A constant-balance wrapper ERC20 token (yvstETH) that converts stETH balances to the underlying
shares balances. As Lido oracles report ETH2 rewards, penalties, or slashings, stETH token balances
change but yvstETH token balances remain unchanged. Instead, the amount of stETH corresponding to
one yvstETH changes (and thus yvstETH price).

One wei of yvstETH can be at any time exchanged to the amount of stETH corresponding to one wei
of stETH token shares, and vice versa, by calling `withdraw` and `deposit` on the vault.

### [YvStETHOracle.sol](./contracts/YvStETHOracle.sol)

An oracle contract for quoting `yvstETH/USD` rate, modelled after the
[`Univ2LpOracle`](https://github.com/makerdao/univ2-lp-oracle/blob/master/src/Univ2LpOracle.sol).
Uses the following upstream sources:

* An oracle/medianizer for `ETH/USD` quote (e.g. [this one](https://etherscan.io/address/0x64de91f5a373cd4c28de3600cb34c7c6ce410c85)).
* stETH/ETH [Curve pool](https://etherscan.io/address/0xDC24316b9AE028F1497c275EB9192a3Ea0f67022) for `stETH/ETH` quote.
* stETH [token contract](https://etherscan.io/token/0xae7ab96520de3a18e5e111b5eaab095312d7fe84) for `yvstETH/stETH` rate.

Currently, almost all stETH/ETH liquidity is in the aforementioned Curve pool so it makes no sense
to query other stETH/ETH price sources.

### [GemJoin.sol](./contracts/GemJoin.sol)

The standard `GemJoin` contract.
