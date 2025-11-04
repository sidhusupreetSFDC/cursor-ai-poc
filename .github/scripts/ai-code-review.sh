#!/bin/bash

##############################################################################
# AI-Powered Apex Code Review Script
#
# This script analyzes Apex code files using AI and generates detailed
# code review comments focusing on security, performance, and best practices.
#
# Usage:
#   ./ai-code-review.sh <files_list_or_directory>
#
# Arguments:
#   files_list_or_directory: Path to file containing list of .cls files,
#                            or directory containing Apex classes
#
# Environment Variables:
#   ANTHROPIC_API_KEY or OPENAI_API_KEY: Required for AI analysis
#   AI_PROVIDER: anthropic or openai (default: anthropic)
#   AI_CONFIG_FILE: Path to AI configuration file
##############################################################################

set -e

# Source the AI client library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/ai-client.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
INPUT="$1"
AI_CONFIG_FILE="${AI_CONFIG_FILE:-.github/config/ai-config.yml}"
PROMPT_TEMPLATE="${PROMPT_TEMPLATE:-.github/config/prompts/apex-code-review.md}"
OUTPUT_FILE="${OUTPUT_FILE:-review-results.json}"

echo -e "${BLUE}════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  AI-Powered Apex Code Review${NC}"
echo -e "${BLUE}════════════════════════════════════════════════${NC}"
echo ""

# Validate input
if [ -z "$INPUT" ]; then
    echo -e "${RED}Error: No input provided${NC}"
    echo "Usage: $0 <files_list_or_directory>"
    exit 1
fi

# Get list of files to review
FILES=()
if [ -f "$INPUT" ]; then
    # Input is a file containing list of paths
    while IFS= read -r line; do
        [ -n "$line" ] && FILES+=("$line")
    done < "$INPUT"
elif [ -d "$INPUT" ]; then
    # Input is a directory
    while IFS= read -r file; do
        FILES+=("$file")
    done < <(find "$INPUT" -type f -name "*.cls")
else
    echo -e "${RED}Error: Input '$INPUT' is neither a file nor directory${NC}"
    exit 1
fi

if [ ${#FILES[@]} -eq 0 ]; then
    echo -e "${YELLOW}⚠ No Apex files found to review${NC}"
    echo "[]" > "$OUTPUT_FILE"
    exit 0
fi

echo "Files to review: ${#FILES[@]}"
echo ""

# Load prompt template
if [ ! -f "$PROMPT_TEMPLATE" ]; then
    echo -e "${RED}Error: Prompt template not found: $PROMPT_TEMPLATE${NC}"
    exit 1
fi

PROMPT_BASE=$(cat "$PROMPT_TEMPLATE")

# Initialize results array
RESULTS="[]"

# Review each file
for file in "${FILES[@]}"; do
    echo -e "${BLUE}→ Reviewing: $file${NC}"
    
    if [ ! -f "$file" ]; then
        echo -e "${YELLOW}  ⚠ File not found, skipping${NC}"
        continue
    fi
    
    # Read file content
    CODE_CONTENT=$(cat "$file")
    
    # Escape special characters for JSON
    CODE_CONTENT_ESCAPED=$(echo "$CODE_CONTENT" | jq -Rs .)
    
    # Build prompt by replacing placeholders
    PROMPT="$PROMPT_BASE"
    PROMPT="${PROMPT//\{CODE_CONTENT\}/$CODE_CONTENT}"
    PROMPT="${PROMPT//\{FILE_NAME\}/$(basename "$file")}"
    PROMPT="${PROMPT//\{API_VERSION\}/60.0}"
    PROMPT="${PROMPT//\{ORG_TYPE\}/Sandbox}"
    PROMPT="${PROMPT//\{RELATED_FILES\}/}"
    PROMPT="${PROMPT//\{PR_DESCRIPTION\}/}"
    PROMPT="${PROMPT//\{PREVIOUS_ISSUES\}/}"
    
    # Call AI API with retry logic
    echo "  Calling AI API..."
    AI_RESPONSE=$(ai_call_with_retry "$PROMPT" "$AI_CONFIG_FILE" 3)
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}  ✗ Failed to get AI response${NC}"
        continue
    fi
    
    # Extract text content from AI response
    RESPONSE_TEXT=$(parse_ai_response "$AI_RESPONSE" "$AI_PROVIDER")
    
    # Extract JSON from response (handles markdown code blocks)
    REVIEW_JSON=$(extract_json_from_response "$RESPONSE_TEXT")
    
    # Validate JSON
    if ! echo "$REVIEW_JSON" | jq empty 2>/dev/null; then
        echo -e "${YELLOW}  ⚠ Could not parse AI response as JSON${NC}"
        echo "$RESPONSE_TEXT" > "review_${file##*/}.txt"
        echo "  Raw response saved to: review_${file##*/}.txt"
        continue
    fi
    
    # Add file path to result
    REVIEW_WITH_PATH=$(echo "$REVIEW_JSON" | jq --arg file "$file" '. + {file_path: $file}')
    
    # Append to results
    RESULTS=$(echo "$RESULTS" | jq --argjson review "$REVIEW_WITH_PATH" '. + [$review]')
    
    # Display summary
    SCORE=$(echo "$REVIEW_WITH_PATH" | jq -r '.overall_score // "N/A"')
    CRITICAL=$(echo "$REVIEW_WITH_PATH" | jq '[.issues[] | select(.severity == "critical")] | length')
    HIGH=$(echo "$REVIEW_WITH_PATH" | jq '[.issues[] | select(.severity == "high")] | length')
    MEDIUM=$(echo "$REVIEW_WITH_PATH" | jq '[.issues[] | select(.severity == "medium")] | length')
    
    echo -e "${GREEN}  ✓ Review complete${NC}"
    echo "    Score: $SCORE/10"
    echo "    Issues: Critical=$CRITICAL, High=$HIGH, Medium=$MEDIUM"
    echo ""
done

# Save results
echo "$RESULTS" | jq '.' > "$OUTPUT_FILE"

echo -e "${BLUE}════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Review Summary${NC}"
echo -e "${BLUE}════════════════════════════════════════════════${NC}"

TOTAL_FILES=$(echo "$RESULTS" | jq 'length')
TOTAL_CRITICAL=$(echo "$RESULTS" | jq '[.[].issues[] | select(.severity == "critical")] | length')
TOTAL_HIGH=$(echo "$RESULTS" | jq '[.[].issues[] | select(.severity == "high")] | length')
TOTAL_MEDIUM=$(echo "$RESULTS" | jq '[.[].issues[] | select(.severity == "medium")] | length')
TOTAL_LOW=$(echo "$RESULTS" | jq '[.[].issues[] | select(.severity == "low")] | length')
AVG_SCORE=$(echo "$RESULTS" | jq '[.[].overall_score // 0] | add / length')

echo "Files reviewed: $TOTAL_FILES"
echo "Average score: $AVG_SCORE/10"
echo ""
echo "Issues found:"
echo "  Critical: $TOTAL_CRITICAL"
echo "  High: $TOTAL_HIGH"
echo "  Medium: $TOTAL_MEDIUM"
echo "  Low: $TOTAL_LOW"
echo ""
echo "Results saved to: $OUTPUT_FILE"

# Exit with error if critical issues found
if [ "$TOTAL_CRITICAL" -gt 0 ]; then
    echo -e "${RED}✗ Critical issues found - blocking PR${NC}"
    exit 1
elif [ "$TOTAL_HIGH" -gt 5 ]; then
    echo -e "${YELLOW}⚠ High number of high-severity issues${NC}"
    exit 0  # Don't block, but warn
else
    echo -e "${GREEN}✓ No blocking issues found${NC}"
    exit 0
fi

