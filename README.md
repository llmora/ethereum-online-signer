ethereum-online-signer: Secure small ethereum signer
----------------------------------------------------

Small API-based Ethereum signer, designed to securely operate with as little attack surface as possible

Functionality
==

  * Key password is not stored on disk, requires manual input on startup
  * Configurable maximum amount of ETH to accept transfers
  * Configurable list of destinations, so that ETH cannot be transferred to other addresses

Configuration
==

The application supports configuration through a `settings.yml` on the same
directory as the application. The settings file accepts a set of `key:
value` parameters:

  transfer_limit_wei: Maximum amount in WEI to transfer, requests to sign transactions above this amount will be rejected
  keyfile: name of the file that contains the key, in web3 format
  source: source of the ETH transfers, must be the address assocaited with the key file
  destination: list of destination ETH addresses that we support trasnfers to, requests to sign transactions with another destination will be rejected  

An example content of `settings.yml`:

```
  transfer_limit_wei: 1_000_000_000_000_000_000 # 1 ETH
  keyfile: eth-key.json
  source: "03969653c12...78563fd186dee62"
  destinations: ["0xe3365D1a2...0CD181e0C22305", "0xfbc3DCf2567...8b2F7C1a2"]
```
