# CloudAtCost Setup Scripts

An easy way to secure and setup your cloudatcost server.

## Usage:

on a newly created instance, login as `root`, enter the following commands:

```shell
wget https://raw.githubusercontent.com/jericbryledy/cloudatcost-setup-scripts/master/ubuntu.sh
chmod u+x ubuntu.sh
./ubuntu.sh
```

## What does the script do?

1. Set the machine name
1. Create a new account
1. Deletes the default account `user` created by cloudatcost
1. Updates the OS to the latest release version
1. Updates all packages to the latest version
1. Disables `root` ssh access
1. Changes ssh port number (most script kiddies attack the default port 22)
1. Regenerates new SSH Server keys
1. Deletes old kernels


