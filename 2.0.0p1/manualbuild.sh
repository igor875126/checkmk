#!/usr/bin/env bash
###########################################################################
# Builds docker image and pushes as latest to the registry
# Normally this is made by CI/CD automatically but in case it does not work
###########################################################################

# Variables
TAG=2.0.0p1
REPOSITORY=igor875126/checkmk
IMAGENAME=${REPOSITORY}:${TAG}

# Build
docker build -t ${IMAGENAME} .

# Push
docker push ${IMAGENAME}

# Cleanup
YELLOW='\033[0;33m'
NC='\033[0m'
echo -e "To clean up local image, type: ${YELLOW}docker rmi ${IMAGENAME}${NC}"