ethereum-online-signer: Secure small ethereum signer
====================================================

Small API-based Ethereum signer, designed to securely operate with as little attack surface as possible

Functionality
-------------

* Key password is not stored on disk, requires manual input on startup
* Configurable maximum amount of ETH to accept transfers
* Configurable list of destinations, so that ETH cannot be transferred to other addresses

Installation
------------
```
$ git clone https://github.com/llmora/ethereum-online-signer
$ bundle install
```

Running
-------

```
$ bundle exec rackup config.ru
```

Configuration
-------------

The application supports configuration through a `settings.yml` on the same directory as the application. The settings file accepts a set of `key: value` parameters:

  *source*: source of the ETH transfers, must be the address assocaited with the key file
  *keyfile*: name of the file that contains the key, in web3 format
  *destination*: list of destination ETH addresses that we support trasnfers to, requests to sign transactions with another destination will be rejected  
  *transfer_limit_wei*: Maximum amount in WEI to transfer, requests to sign transactions above this amount will be rejected
  *gas_price*: (optional) Gas price in WEI we are willing to pay for the transaction to be added to a block (by default 41 Gwei)
  *etherscan_api_token*: (optional) EtherScan.io API token, in case you have an account. By default we use the anonymous interface, which has throttling restrictions - if you plan to make heavy use of the signer get an API token from them

An example content of `settings.yml`:
```
  source: "03969653c12...78563fd186dee62"
  keyfile: eth-key.json
  destinations: ["0xe3365D1a2...0CD181e0C22305", "0xfbc3DCf2567...8b2F7C1a2"]
  transfer_limit_wei: 1_000_000_000_000_000_000 # 1 ETH
```

TODO
----
* Create docker image for ease of deployment
* Write down threat analysis
