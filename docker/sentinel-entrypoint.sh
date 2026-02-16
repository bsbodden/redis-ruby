#!/bin/sh
# Wait for redis-master to be resolvable and get its IP
until MASTER_IP=$(getent hosts redis-master | awk '{ print $1 }' | head -1) && [ -n "$MASTER_IP" ]; do
  echo "Waiting for redis-master to be resolvable..."
  sleep 1
done

echo "redis-master resolved to $MASTER_IP"

# Copy config to writable location and replace hostname with IP
cp /etc/redis/sentinel.conf /tmp/sentinel.conf
sed -i "s/redis-master/$MASTER_IP/g" /tmp/sentinel.conf

# Set announce port from environment variable (defaults to 26379)
ANNOUNCE_PORT=${SENTINEL_ANNOUNCE_PORT:-26379}
sed -i "s/sentinel announce-port .*/sentinel announce-port $ANNOUNCE_PORT/g" /tmp/sentinel.conf

echo "Starting sentinel with resolved IP and announce port $ANNOUNCE_PORT..."
exec redis-sentinel /tmp/sentinel.conf

