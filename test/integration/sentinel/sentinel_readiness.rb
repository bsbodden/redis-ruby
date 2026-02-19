# frozen_string_literal: true

# Sentinel readiness and health checking helpers
module SentinelReadiness
  def parse_sentinel_info(array)
    return {} unless array.is_a?(Array)

    hash = {}
    array.each_slice(2) do |key, value|
      hash[key] = value if key.is_a?(String)
    end
    hash
  end

  def wait_for_redis(container, port, timeout: 30)
    start_time = Time.now

    loop do
      raise "Timeout waiting for Redis to be ready" if Time.now - start_time > timeout
      break if ping_redis_container(container, port)

      sleep 0.5
    end
  end

  def ping_redis_container(container, port)
    mapped_port = container.mapped_port(port)
    conn = RR::Connection::TCP.new(host: container.host, port: mapped_port, timeout: 2.0)
    result = conn.call("PING")
    conn.close
    result == "PONG"
  rescue StandardError
    false
  end

  def sentinel_cluster_ready?(host, port)
    conn = RR::Connection::TCP.new(host: host, port: port, timeout: 5.0)
    result = conn.call("SENTINEL", "MASTER", SentinelTestContainerSupport::SERVICE_NAME)
    conn.close

    return false unless result.is_a?(Array) && result.any?

    info = parse_sentinel_info(result)
    info["flags"] && !info["flags"].include?("down")
  rescue StandardError => e
    puts "Waiting... (#{e.class})"
    false
  end
end
