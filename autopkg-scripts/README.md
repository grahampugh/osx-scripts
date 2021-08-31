# autopkg-scripts

A collection of helper scripts for AutoPkg.

## autopkg-cache-clean.sh

This script removes all but the most recent versions of packages and downloads in an AutoPkg cache.

For help:

```
./autopkg-cache-clean.sh --help
```

## autopkg-update-trust-info-recipe-list.sh

This script attempts to update the trust information for all recipes in a recipe list. Note that this should not be used without first satisfying yourself that you trust the changes off all the recipes in the list. run with `--check-only` to verify the trusts before updating if you are not sure.

For help:

```
./autopkg-update-trust-info-recipe-list.sh --help
```
