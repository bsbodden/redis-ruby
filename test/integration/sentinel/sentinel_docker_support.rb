# frozen_string_literal: true

# Docker environment detection and networking for sentinel tests
module SentinelDockerSupport
  def inside_docker?
    @inside_docker ||= begin
      File.exist?("/.dockerenv") || File.read("/proc/1/cgroup").include?("docker")
    rescue StandardError
      false
    end
  end

  def connect_to_network!
    return unless inside_docker?

    container_id = begin
      File.read("/etc/hostname").strip
    rescue StandardError
      nil
    end
    return unless container_id

    system("docker network connect docker_redis-sentinel-net #{container_id} 2>/dev/null")
    @docker_host = nil
  end

  def docker_host
    if inside_docker? && @compose_started
      ips = sentinel_ips
      ips&.first || "localhost"
    elsif system("getent hosts host.docker.internal >/dev/null 2>&1")
      "host.docker.internal"
    else
      "localhost"
    end
  rescue StandardError
    "localhost"
  end

  def sentinel_ips
    return nil unless inside_docker? && @compose_started

    %w[sentinel-1 sentinel-2 sentinel-3].map do |name|
      `docker inspect #{name} --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'`.strip
    end
  end
end
