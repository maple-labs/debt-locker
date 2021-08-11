#!/usr/bin/env bash
set -e

while getopts v: flag
do
    case "${flag}" in
        v) version=${OPTARG};;
    esac
done

echo $version

./build.sh -c ./config/prod.json

rm -rf ./package
mkdir -p package

echo "{
  \"name\": \"@maplelabs/debt-locker\",
  \"version\": \"${version}\",
  \"description\": \"Debt Locker Artifacts and ABIs\",
  \"author\": \"Maple Labs\",
  \"license\": \"AGPLv3\",
  \"repository\": {
    \"type\": \"git\",
    \"url\": \"https://github.com/maple-labs/debt-locker.git\"
  },
  \"bugs\": {
    \"url\": \"https://github.com/maple-labs/debt-locker/issues\"
  },
  \"homepage\": \"https://github.com/maple-labs/debt-locker\"
}" > package/package.json

mkdir -p package/artifacts
mkdir -p package/abis

cat ./out/dapp.sol.json | jq '.contracts | ."contracts/DebtLockerFactory.sol" | .DebtLockerFactory' > package/artifacts/DebtLockerFactory.json
cat ./out/dapp.sol.json | jq '.contracts | ."contracts/DebtLockerFactory.sol" | .DebtLockerFactory | .abi' > package/abis/DebtLockerFactory.json
cat ./out/dapp.sol.json | jq '.contracts | ."contracts/DebtLocker.sol" | .DebtLocker' > package/artifacts/DebtLocker.json
cat ./out/dapp.sol.json | jq '.contracts | ."contracts/DebtLocker.sol" | .DebtLocker | .abi' > package/abis/DebtLocker.json

npm publish ./package --access public

rm -rf ./package
