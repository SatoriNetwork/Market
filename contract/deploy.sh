#!/bin/bash

# Build the Docker image
docker compose build

# Run the deployment
docker compose run --rm deployer truffle migrate --f 2 --network base_mainnet
