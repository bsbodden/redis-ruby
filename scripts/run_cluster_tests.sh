#!/bin/bash
# Script to run Redis Cluster integration tests
# Run this from the host machine (outside the devcontainer) for proper network access
#
# Usage: ./scripts/run_cluster_tests.sh [test_file]
#
# Examples:
#   ./scripts/run_cluster_tests.sh                    # Run all cluster tests
#   ./scripts/run_cluster_tests.sh cluster_basic_test # Run specific test file

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
COMPOSE_FILE="$PROJECT_DIR/docker/docker-compose.cluster.yml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== Redis Cluster Test Runner ===${NC}"
echo ""

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: Docker is not installed or not in PATH${NC}"
    exit 1
fi

# Check if docker-compose is available
if ! command -v docker-compose &> /dev/null; then
    echo -e "${RED}Error: docker-compose is not installed or not in PATH${NC}"
    exit 1
fi

# Function to start the cluster
start_cluster() {
    echo -e "${YELLOW}Starting Redis Cluster...${NC}"
    docker-compose -f "$COMPOSE_FILE" up -d

    echo -e "${YELLOW}Waiting for cluster to be ready...${NC}"
    local timeout=90
    local elapsed=0

    while [ $elapsed -lt $timeout ]; do
        if docker exec docker-redis-cluster-1 redis-cli -p 7000 cluster info 2>/dev/null | grep -q "cluster_state:ok"; then
            echo -e "${GREEN}Cluster is ready!${NC}"
            return 0
        fi
        echo "  Waiting... (${elapsed}s)"
        sleep 2
        elapsed=$((elapsed + 2))
    done

    echo -e "${RED}Timeout waiting for cluster to be ready${NC}"
    return 1
}

# Function to stop the cluster
stop_cluster() {
    echo -e "${YELLOW}Stopping Redis Cluster...${NC}"
    docker-compose -f "$COMPOSE_FILE" down
}

# Function to check cluster status
check_cluster() {
    echo -e "${YELLOW}Cluster Status:${NC}"
    docker exec docker-redis-cluster-1 redis-cli -p 7000 cluster info | head -5
    echo ""
    echo -e "${YELLOW}Cluster Nodes:${NC}"
    docker exec docker-redis-cluster-1 redis-cli -p 7000 cluster nodes
}

# Function to run tests
run_tests() {
    local test_file="$1"

    cd "$PROJECT_DIR"

    # Set environment variable for cluster URL
    # With host networking, cluster is available at localhost:7000-7005
    export REDIS_CLUSTER_URL="redis://localhost:7000,redis://localhost:7001,redis://localhost:7002"

    echo -e "${YELLOW}Running cluster tests...${NC}"
    echo "REDIS_CLUSTER_URL=$REDIS_CLUSTER_URL"
    echo ""

    if [ -n "$test_file" ]; then
        # Run specific test file
        if [[ "$test_file" != *".rb" ]]; then
            test_file="${test_file}.rb"
        fi
        if [[ "$test_file" != *"test/integration/cluster/"* ]]; then
            test_file="test/integration/cluster/${test_file}"
        fi
        echo "Running: $test_file"
        bundle exec ruby -Itest "$test_file"
    else
        # Run all cluster tests
        echo "Running all cluster tests..."
        bundle exec ruby -Itest -e "Dir['test/integration/cluster/*_test.rb'].each { |f| require File.expand_path(f) }"
    fi
}

# Parse command line arguments
case "${1:-}" in
    start)
        start_cluster
        ;;
    stop)
        stop_cluster
        ;;
    status)
        check_cluster
        ;;
    test)
        shift
        run_tests "$@"
        ;;
    *)
        # Default: start cluster, run tests, keep cluster running
        if ! docker exec docker-redis-cluster-1 redis-cli -p 7000 cluster info 2>/dev/null | grep -q "cluster_state:ok"; then
            start_cluster
        else
            echo -e "${GREEN}Cluster already running${NC}"
        fi

        echo ""
        run_tests "$1"

        echo ""
        echo -e "${GREEN}Tests complete!${NC}"
        echo -e "${YELLOW}Cluster is still running. Use '$0 stop' to stop it.${NC}"
        ;;
esac
