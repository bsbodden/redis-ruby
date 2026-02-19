# frozen_string_literal: true

# Docker environment detection and networking for cluster tests
module ClusterDockerSupport
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

    system("docker network connect docker_default #{container_id} 2>/dev/null")
  end

  def docker_host
    if inside_docker? && @compose_started
      gateway = `ip route | grep default | awk '{print $3}'`.strip
      gateway.empty? ? "host.docker.internal" : gateway
    elsif system("getent hosts host.docker.internal >/dev/null 2>&1")
      "host.docker.internal"
    else
      "localhost"
    end
  rescue StandardError
    "localhost"
  end

  def host_translation
    return nil unless inside_docker? && @compose_started

    target = docker_host
    return nil if ["127.0.0.1", "localhost"].include?(target)

    { "127.0.0.1" => target }
  end
end
