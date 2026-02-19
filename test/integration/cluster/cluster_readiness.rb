# frozen_string_literal: true

# Cluster readiness checking helpers
module ClusterReadiness
  def wait_for_cluster_state_ok(host, port, timeout: 90)
    start_time = Time.now

    loop do
      raise "Timeout waiting for Redis Cluster" if Time.now - start_time > timeout
      break if check_cluster_state(host, port)

      sleep 2
    end
  end

  def check_cluster_state(host, port)
    conn = RR::Connection::TCP.new(host: host, port: port, timeout: 5.0)
    result = conn.call("CLUSTER", "INFO")
    conn.close

    if result.include?("cluster_state:ok")
      puts "Cluster is ready!"
      return true
    end

    false
  rescue StandardError => e
    puts "Waiting... (#{e.class}: #{e.message})"
    false
  end
end
