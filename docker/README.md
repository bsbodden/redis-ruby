# Docker Test Infrastructure

This directory contains Docker Compose configurations for running Redis Cluster and Redis Sentinel during integration tests.

## Overview

The test suite supports multiple ways to run integration tests:

1. **Docker Compose** (default for local development)
2. **TestContainers** (used in CI environments)
3. **External Redis** (via environment variables)

## Files

### Redis Cluster

**`docker-compose.cluster.yml`**
- Runs a 6-node Redis Cluster (3 masters + 3 replicas)
- Uses `redislabs/client-libs-test:8.4.0` image
- Ports: `17000-17005` (mapped from internal `17000-17005`)
- Used by: `test/integration/cluster/cluster_test_helper.rb`

**Usage:**
```bash
# Start cluster
docker-compose -f docker/docker-compose.cluster.yml up -d

# Stop cluster
docker-compose -f docker/docker-compose.cluster.yml down

# Set environment variable (optional)
export REDIS_CLUSTER_URL=redis://localhost:17000,redis://localhost:17001,redis://localhost:17002
```

### Redis Sentinel

**`docker-compose.sentinel.yml`**
- Runs Redis Sentinel with 1 master, 1 replica, and 3 sentinels
- Uses `redis:7.0` image
- Master port: `7379` (mapped from internal `6379`)
- Replica port: `7380` (mapped from internal `6380`)
- Sentinel ports: `26379`, `26380`, `26381`
- Used by: `test/integration/sentinel/sentinel_test_helper.rb`

**Supporting files:**
- `sentinel.conf` - Configuration for sentinel-1
- `sentinel2.conf` - Configuration for sentinel-2
- `sentinel3.conf` - Configuration for sentinel-3
- `sentinel-entrypoint.sh` - Entrypoint script that resolves master IP

**Usage:**
```bash
# Start sentinel cluster
docker-compose -f docker/docker-compose.sentinel.yml up -d

# Stop sentinel cluster
docker-compose -f docker/docker-compose.sentinel.yml down

# Set environment variable (optional)
export REDIS_SENTINEL_URL=localhost:26379,localhost:26380,localhost:26381
```

## Port Mappings

### Cluster Ports
- `17000-17005` - Cluster nodes (external and internal)

### Sentinel Ports
- `7379` - Master (external) → `6379` (internal)
- `7380` - Replica (external) → `6380` (internal)
- `26379` - Sentinel 1 (external and internal)
- `26380` - Sentinel 2 (external) → `26379` (internal)
- `26381` - Sentinel 3 (external) → `26379` (internal)

**Note:** Ports `7379`/`7380` are used to avoid conflicts with the devcontainer Redis on port `6379`.

## Test Integration

### Cluster Tests
Located in `test/integration/cluster/`:
- `cluster_basic_test.rb` - Basic cluster operations
- `cluster_redirect_test.rb` - MOVED/ASK redirect handling
- `cluster_failover_test.rb` - Failover scenarios

### Sentinel Tests
Located in `test/integration/sentinel/`:
- `sentinel_basic_test.rb` - Basic sentinel operations
- `sentinel_failover_test.rb` - Failover scenarios

## How Tests Use Docker

1. **Local Development** (default):
   - Tests check if Docker Compose files exist
   - Automatically start containers via `docker-compose up -d`
   - Run tests against containers
   - Automatically stop containers via `docker-compose down`

2. **CI Environment** (`ENV["CI"]` is set):
   - Uses TestContainers instead of Docker Compose
   - Creates ephemeral containers for each test run
   - Automatically cleans up after tests

3. **External Redis** (environment variables set):
   - `REDIS_CLUSTER_URL` - Use external cluster
   - `REDIS_SENTINEL_URL` - Use external sentinel
   - Skips container startup entirely

## Troubleshooting

### Cluster not starting
```bash
# Check cluster health
docker logs redis-cluster

# Verify cluster is ready
docker exec redis-cluster redis-cli -p 17000 cluster info
```

### Sentinel not starting
```bash
# Check sentinel logs
docker logs sentinel-1
docker logs sentinel-2
docker logs sentinel-3

# Check master/replica
docker logs redis-master
docker logs redis-replica

# Verify sentinel is monitoring
docker exec sentinel-1 redis-cli -p 26379 sentinel masters
```

### Port conflicts
If you see port binding errors, check for conflicting services:
```bash
# Check what's using the ports
lsof -i :17000-17005  # Cluster
lsof -i :7379,7380    # Master/Replica
lsof -i :26379-26381  # Sentinels
```

### Network issues
If containers can't communicate:
```bash
# Check networks
docker network ls
docker network inspect docker_redis-sentinel-net

# Reconnect devcontainer to network (if needed)
docker network connect docker_redis-sentinel-net <devcontainer-id>
```

## Maintenance

### Updating Redis Version
To update the Redis version used in tests:

1. **Cluster**: Edit `docker-compose.cluster.yml` and change the image version
2. **Sentinel**: Edit `docker-compose.sentinel.yml` and change the image version

### Cleaning Up
```bash
# Remove all containers and networks
docker-compose -f docker/docker-compose.cluster.yml down
docker-compose -f docker/docker-compose.sentinel.yml down

# Remove volumes (if any)
docker volume prune
```

## See Also

- [Cluster Test Helper](../test/integration/cluster/cluster_test_helper.rb)
- [Sentinel Test Helper](../test/integration/sentinel/sentinel_test_helper.rb)
- [Cluster Guide](../docs/guides/cluster.md)
- [Sentinel Guide](../docs/guides/sentinel.md)

