#!/bin/bash

##############################################################################
# AI Client Library
#
# Provides a unified interface for calling different AI APIs
# (Anthropic Claude, OpenAI, etc.) from GitHub Actions workflows.
#
# Usage:
#   source .github/scripts/lib/ai-client.sh
#   ai_call "prompt text" "config_file.yml" > response.json
##############################################################################

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Default configuration
AI_PROVIDER="${AI_PROVIDER:-cursor}"
AI_MODEL="${AI_MODEL:-claude-3-5-sonnet-20241022}"
AI_TEMPERATURE="${AI_TEMPERATURE:-0.2}"
AI_MAX_TOKENS="${AI_MAX_TOKENS:-4096}"
CURSOR_API_URL="${CURSOR_API_URL:-https://api.cursor.sh/v1}"

##############################################################################
# Function: Call Anthropic Claude API
##############################################################################
call_anthropic() {
    local prompt="$1"
    local model="${2:-$AI_MODEL}"
    local temperature="${3:-$AI_TEMPERATURE}"
    local max_tokens="${4:-$AI_MAX_TOKENS}"
    
    if [ -z "$ANTHROPIC_API_KEY" ]; then
        echo -e "${RED}Error: ANTHROPIC_API_KEY not set${NC}" >&2
        return 1
    fi
    
    # Properly escape the prompt for JSON using jq
    local prompt_escaped=$(echo "$prompt" | jq -Rs .)
    
    local request_body=$(jq -n \
        --arg model "$model" \
        --argjson max_tokens "$max_tokens" \
        --argjson temperature "$temperature" \
        --argjson content "$prompt_escaped" \
        '{
            model: $model,
            max_tokens: $max_tokens,
            temperature: $temperature,
            messages: [
                {
                    role: "user",
                    content: $content
                }
            ]
        }')
    
    local response=$(curl -s -X POST "https://api.anthropic.com/v1/messages" \
        -H "Content-Type: application/json" \
        -H "x-api-key: $ANTHROPIC_API_KEY" \
        -H "anthropic-version: 2023-06-01" \
        -d "$request_body")
    
    # Check for errors
    if echo "$response" | jq -e '.error' > /dev/null 2>&1; then
        echo -e "${RED}API Error:${NC}" >&2
        echo "$response" | jq '.error' >&2
        return 1
    fi
    
    echo "$response"
}

##############################################################################
# Function: Call OpenAI API
##############################################################################
call_openai() {
    local prompt="$1"
    local model="${2:-gpt-4o}"
    local temperature="${3:-$AI_TEMPERATURE}"
    local max_tokens="${4:-$AI_MAX_TOKENS}"
    
    if [ -z "$OPENAI_API_KEY" ]; then
        echo -e "${RED}Error: OPENAI_API_KEY not set${NC}" >&2
        return 1
    fi
    
    # Properly escape the prompt for JSON using jq
    local prompt_escaped=$(echo "$prompt" | jq -Rs .)
    
    local request_body=$(jq -n \
        --arg model "$model" \
        --argjson temperature "$temperature" \
        --argjson max_tokens "$max_tokens" \
        --argjson user_content "$prompt_escaped" \
        '{
            model: $model,
            messages: [
                {
                    role: "system",
                    content: "You are an expert Salesforce developer and code reviewer."
                },
                {
                    role: "user",
                    content: $user_content
                }
            ],
            temperature: $temperature,
            max_tokens: $max_tokens
        }')
    
    local response=$(curl -s -X POST "https://api.openai.com/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $OPENAI_API_KEY" \
        -d "$request_body")
    
    # Check for errors
    if echo "$response" | jq -e '.error' > /dev/null 2>&1; then
        echo -e "${RED}API Error:${NC}" >&2
        echo "$response" | jq '.error' >&2
        return 1
    fi
    
    echo "$response"
}

##############################################################################
# Function: Call Cursor API
##############################################################################
call_cursor() {
    local prompt="$1"
    local model="${2:-$AI_MODEL}"
    local temperature="${3:-$AI_TEMPERATURE}"
    local max_tokens="${4:-$AI_MAX_TOKENS}"
    
    if [ -z "$CURSOR_API_KEY" ]; then
        echo -e "${RED}Error: CURSOR_API_KEY not set${NC}" >&2
        echo -e "${YELLOW}Note: Cursor API is currently in beta. Get your key from Cursor settings.${NC}" >&2
        echo -e "${YELLOW}Alternative: Use ANTHROPIC_API_KEY or OPENAI_API_KEY instead.${NC}" >&2
        return 1
    fi
    
    # Properly escape the prompt for JSON using jq
    local prompt_escaped=$(echo "$prompt" | jq -Rs .)
    
    # Cursor API uses OpenAI-compatible format
    local request_body=$(jq -n \
        --arg model "$model" \
        --argjson temperature "$temperature" \
        --argjson max_tokens "$max_tokens" \
        --argjson user_content "$prompt_escaped" \
        '{
            model: $model,
            messages: [
                {
                    role: "system",
                    content: "You are an expert Salesforce developer and code reviewer with deep knowledge of Apex, Lightning Web Components, and Salesforce best practices."
                },
                {
                    role: "user",
                    content: $user_content
                }
            ],
            temperature: $temperature,
            max_tokens: $max_tokens
        }')
    
    local response=$(curl -s -X POST "$CURSOR_API_URL/chat/completions" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $CURSOR_API_KEY" \
        -d "$request_body")
    
    # Check for errors
    if echo "$response" | jq -e '.error' > /dev/null 2>&1; then
        echo -e "${RED}API Error:${NC}" >&2
        echo "$response" | jq '.error' >&2
        return 1
    fi
    
    echo "$response"
}

##############################################################################
# Function: Parse AI response (provider-agnostic)
##############################################################################
parse_ai_response() {
    local response="$1"
    local provider="$2"
    
    case "$provider" in
        anthropic)
            echo "$response" | jq -r '.content[0].text'
            ;;
        openai|cursor)
            echo "$response" | jq -r '.choices[0].message.content'
            ;;
        *)
            echo "$response"
            ;;
    esac
}

##############################################################################
# Function: Main AI call interface
##############################################################################
ai_call() {
    local prompt="$1"
    local config_file="$2"
    
    # Load configuration if provided
    if [ -n "$config_file" ] && [ -f "$config_file" ]; then
        AI_PROVIDER=$(yq eval '.provider' "$config_file" 2>/dev/null || echo "$AI_PROVIDER")
        AI_MODEL=$(yq eval '.model' "$config_file" 2>/dev/null || echo "$AI_MODEL")
        AI_TEMPERATURE=$(yq eval '.temperature' "$config_file" 2>/dev/null || echo "$AI_TEMPERATURE")
        AI_MAX_TOKENS=$(yq eval '.max_tokens' "$config_file" 2>/dev/null || echo "$AI_MAX_TOKENS")
    fi
    
    echo -e "${BLUE}→ Calling $AI_PROVIDER API (model: $AI_MODEL)...${NC}" >&2
    
    local response
    case "$AI_PROVIDER" in
        cursor)
            response=$(call_cursor "$prompt" "$AI_MODEL" "$AI_TEMPERATURE" "$AI_MAX_TOKENS")
            ;;
        anthropic|claude)
            response=$(call_anthropic "$prompt" "$AI_MODEL" "$AI_TEMPERATURE" "$AI_MAX_TOKENS")
            ;;
        openai|gpt)
            response=$(call_openai "$prompt" "$AI_MODEL" "$AI_TEMPERATURE" "$AI_MAX_TOKENS")
            ;;
        *)
            echo -e "${RED}Error: Unknown AI provider '$AI_PROVIDER'${NC}" >&2
            echo "Supported providers: cursor, anthropic, openai" >&2
            return 1
            ;;
    esac
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ AI API call failed${NC}" >&2
        return 1
    fi
    
    echo -e "${GREEN}✓ AI response received${NC}" >&2
    
    # Return full response (caller can parse it)
    echo "$response"
}

##############################################################################
# Function: Extract JSON from AI response (handles markdown code blocks)
##############################################################################
extract_json_from_response() {
    local response="$1"
    
    # Try to extract JSON from markdown code block
    if echo "$response" | grep -q '```json'; then
        echo "$response" | sed -n '/```json/,/```/p' | sed '1d;$d'
    # Try to extract any JSON object
    elif echo "$response" | grep -q '{'; then
        echo "$response" | grep -oP '\{(?:[^{}]|(?R))*\}'  | head -1
    else
        echo "$response"
    fi
}

##############################################################################
# Function: Retry logic with exponential backoff
##############################################################################
ai_call_with_retry() {
    local prompt="$1"
    local config_file="$2"
    local max_retries="${3:-3}"
    local base_delay="${4:-2}"
    
    local attempt=1
    local delay=$base_delay
    
    while [ $attempt -le $max_retries ]; do
        echo -e "${BLUE}Attempt $attempt of $max_retries${NC}" >&2
        
        if ai_call "$prompt" "$config_file"; then
            return 0
        fi
        
        if [ $attempt -lt $max_retries ]; then
            echo -e "${YELLOW}⚠ Retrying in ${delay}s...${NC}" >&2
            sleep $delay
            delay=$((delay * 2))  # Exponential backoff
        fi
        
        attempt=$((attempt + 1))
    done
    
    echo -e "${RED}✗ All retry attempts failed${NC}" >&2
    return 1
}

##############################################################################
# Function: Calculate cost estimate
##############################################################################
estimate_cost() {
    local input_tokens="$1"
    local output_tokens="$2"
    local provider="$3"
    local model="$4"
    
    # Cost per 1M tokens (in dollars)
    local input_cost=0
    local output_cost=0
    
    case "$provider:$model" in
        anthropic:claude-3-5-sonnet*)
            input_cost=3
            output_cost=15
            ;;
        anthropic:claude-3-haiku*)
            input_cost=0.80
            output_cost=4
            ;;
        openai:gpt-4o)
            input_cost=2.5
            output_cost=10
            ;;
        openai:gpt-4o-mini)
            input_cost=0.15
            output_cost=0.6
            ;;
    esac
    
    local total_cost=$(echo "scale=6; ($input_tokens * $input_cost + $output_tokens * $output_cost) / 1000000" | bc)
    echo "$total_cost"
}

# Export functions
export -f call_anthropic
export -f call_openai
export -f parse_ai_response
export -f ai_call
export -f extract_json_from_response
export -f ai_call_with_retry
export -f estimate_cost

