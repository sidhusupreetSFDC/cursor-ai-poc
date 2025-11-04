#!/bin/bash

##############################################################################
# Salesforce Authentication Script for GitHub Actions
#
# This script handles authentication to Salesforce orgs using JWT or
# SFDX Auth URL stored in GitHub Secrets.
#
# Usage:
#   ./sf-auth.sh <environment> <auth-method>
#
# Arguments:
#   environment: dev, staging, or prod
#   auth-method: sfdx-url or jwt (default: sfdx-url)
#
# Environment Variables Required:
#   For sfdx-url method:
#     - SFDX_AUTH_URL_DEV, SFDX_AUTH_URL_STAGING, or SFDX_AUTH_URL_PROD
#  
#   For jwt method:
#     - SF_JWT_KEY (base64 encoded private key)
#     - SF_CONSUMER_KEY
#     - SF_USERNAME_DEV, SF_USERNAME_STAGING, or SF_USERNAME_PROD
##############################################################################

set -e  # Exit on error

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
AUTH_METHOD="${2:-sfdx-url}"
ENVIRONMENT="${1}"

# Validate environment argument
if [ -z "$ENVIRONMENT" ]; then
    echo -e "${RED}Error: Environment argument required${NC}"
    echo "Usage: $0 <environment> [auth-method]"
    echo "  environment: dev, staging, prod"
    echo "  auth-method: sfdx-url (default) or jwt"
    exit 1
fi

# Normalize environment name
ENVIRONMENT=$(echo "$ENVIRONMENT" | tr '[:lower:]' '[:upper:]')

case "$ENVIRONMENT" in
    DEV|DEVELOPMENT)
        ENV="DEV"
        ALIAS="cicd-dev"
        ;;
    STAGING|STAGE|STG)
        ENV="STAGING"
        ALIAS="cicd-staging"
        ;;
    PROD|PRODUCTION)
        ENV="PROD"
        ALIAS="cicd-prod"
        ;;
    *)
        echo -e "${RED}Error: Invalid environment '$ENVIRONMENT'${NC}"
        echo "Valid values: dev, staging, prod"
        exit 1
        ;;
esac

echo -e "${BLUE}════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Salesforce Authentication${NC}"
echo -e "${BLUE}════════════════════════════════════════════════${NC}"
echo "Environment: $ENV"
echo "Alias: $ALIAS"
echo "Method: $AUTH_METHOD"
echo ""

# Function: Authenticate using SFDX Auth URL
auth_with_sfdx_url() {
    local env_var="SFDX_AUTH_URL_${ENV}"
    local auth_url="${!env_var}"
    
    if [ -z "$auth_url" ]; then
        echo -e "${RED}✗ Error: $env_var not set${NC}"
        echo "Please ensure the environment variable is configured in GitHub Secrets"
        exit 1
    fi
    
    echo -e "${GREEN}→ Authenticating using SFDX Auth URL...${NC}"
    
    # Write auth URL to temporary file
    echo "$auth_url" > ./SFDX_AUTH_URL.txt
    
    # Authenticate
    if sf org login sfdx-url --sfdx-url-file ./SFDX_AUTH_URL.txt --alias "$ALIAS" --set-default; then
        echo -e "${GREEN}✓ Authentication successful${NC}"
    else
        echo -e "${RED}✗ Authentication failed${NC}"
        rm -f ./SFDX_AUTH_URL.txt
        exit 1
    fi
    
    # Clean up
    rm -f ./SFDX_AUTH_URL.txt
}

# Function: Authenticate using JWT
auth_with_jwt() {
    local username_var="SF_USERNAME_${ENV}"
    local username="${!username_var}"
    
    if [ -z "$username" ]; then
        echo -e "${RED}✗ Error: $username_var not set${NC}"
        exit 1
    fi
    
    if [ -z "$SF_JWT_KEY" ]; then
        echo -e "${RED}✗ Error: SF_JWT_KEY not set${NC}"
        exit 1
    fi
    
    if [ -z "$SF_CONSUMER_KEY" ]; then
        echo -e "${RED}✗ Error: SF_CONSUMER_KEY not set${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}→ Authenticating using JWT Bearer Flow...${NC}"
    
    # Decode and write JWT key to temporary file
    echo "$SF_JWT_KEY" | base64 -d > ./server.key
    chmod 600 ./server.key
    
    # Determine instance URL based on environment
    if [ "$ENV" == "PROD" ]; then
        INSTANCE_URL="https://login.salesforce.com"
    else
        INSTANCE_URL="https://test.salesforce.com"
    fi
    
    echo "Instance URL: $INSTANCE_URL"
    echo "Username: $username"
    
    # Authenticate
    if sf org login jwt \
        --username "$username" \
        --jwt-key-file ./server.key \
        --client-id "$SF_CONSUMER_KEY" \
        --instance-url "$INSTANCE_URL" \
        --alias "$ALIAS" \
        --set-default; then
        echo -e "${GREEN}✓ Authentication successful${NC}"
    else
        echo -e "${RED}✗ Authentication failed${NC}"
        rm -f ./server.key
        exit 1
    fi
    
    # Clean up
    rm -f ./server.key
}

# Main authentication logic
case "$AUTH_METHOD" in
    sfdx-url)
        auth_with_sfdx_url
        ;;
    jwt)
        auth_with_jwt
        ;;
    *)
        echo -e "${RED}Error: Invalid auth method '$AUTH_METHOD'${NC}"
        echo "Valid values: sfdx-url, jwt"
        exit 1
        ;;
esac

# Verify authentication
echo ""
echo -e "${BLUE}════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Verifying Authentication${NC}"
echo -e "${BLUE}════════════════════════════════════════════════${NC}"

if sf org display --target-org "$ALIAS" --json; then
    echo ""
    echo -e "${GREEN}✓ Verification successful${NC}"
    echo ""
    
    # Display org info
    echo "Connected Org Details:"
    sf org display --target-org "$ALIAS"
else
    echo -e "${RED}✗ Verification failed${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Authentication Complete!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════${NC}"
echo ""
echo "You can now run Salesforce CLI commands using:"
echo "  sf <command> --target-org $ALIAS"
echo ""

