#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"

EXPECTED = {
  "home-edge" => %w[caddy],
  "home-control" => %w[spark homepage dozzle],
  "home-immich" => %w[immich-db immich-redis immich-server immich-machine-learning],
  "home-ai" => %w[new-api-db new-api lobe-chat-db lobe-chat portkeyai],
  "home-automation" => %w[n8n-db n8n],
  "home-media" => %w[alist aria2 ariang jellyfin jellyseerr sonarr radarr prowlarr],
  "home-tools" => %w[vaultwarden wallos memos it-tools searxng miniflux-db miniflux gitea-db],
  "home-monitor" => %w[speedtest speedtest-tracker scrutiny],
  "home-backup" => %w[restic]
}.freeze

DATABASES = %w[
  immich-db immich-redis new-api-db lobe-chat-db n8n-db miniflux-db gitea-db
].freeze

HEALTHY_DEPENDENCIES = {
  "immich-server" => %w[immich-db immich-redis],
  "new-api" => %w[new-api-db],
  "lobe-chat" => %w[lobe-chat-db],
  "n8n" => %w[n8n-db],
  "miniflux" => %w[miniflux-db]
}.freeze

TCP_VERIFIED = %w[
  caddy spark homepage dozzle immich-server immich-machine-learning lobe-chat portkeyai
  n8n alist aria2 ariang jellyfin jellyseerr sonarr radarr prowlarr vaultwarden wallos
  memos it-tools searxng speedtest speedtest-tracker scrutiny
].freeze

ALLOWED_BIND_ROOTS = %w[
  /root/zrr-compose/volumes
  /media/immich
  /etc/zrr-compose
  /etc/komodo
  /var/lib/zrr-backup
  /var/run/docker.sock
  /run/udev
  /dev/dri
  /dev/nvme0
].freeze

IMAGE_PATTERN = %r{\A[^\s:@]+(?:/[^\s:@]+)*:[^\s@]+@sha256:[0-9a-f]{64}\z}
FLOATING_TAGS = /\A(?:latest|next|master|master-.+)\z/i

def fail_check(message)
  warn "compose contract: #{message}"
  exit 1
end

def service_networks(service)
  case service["networks"]
  when Array then service["networks"]
  when Hash then service["networks"].keys
  else ["default"]
  end
end

def bind_sources(service)
  Array(service["volumes"]).filter_map do |volume|
    if volume.is_a?(String)
      volume.split(":", 2).first
    elsif volume.is_a?(Hash) && volume.fetch("type", "volume") == "bind"
      volume["source"]
    end
  end
end

def env_file_paths(service)
  Array(service["env_file"]).map do |entry|
    entry.is_a?(Hash) ? entry["path"] : entry
  end
end

def bind_allowed?(source)
  return false unless source&.start_with?("/")

  ALLOWED_BIND_ROOTS.any? do |root|
    source == root || source.start_with?("#{root}/")
  end
end

files = Dir["deployments/home/*/compose.yml"].sort
fail_check("expected 9 Stack files, found #{files.size}") unless files.size == 9

seen_projects = {}
seen_services = {}
parsed_services = {}

files.each do |path|
  document = YAML.safe_load_file(path, aliases: false)
  project = document["name"]
  directory = File.basename(File.dirname(path))
  fail_check("#{path}: name must be #{directory}") unless project == directory
  fail_check("duplicate project #{project}") if seen_projects[project]
  seen_projects[project] = path

  services = document.fetch("services")
  expected_services = EXPECTED.fetch(project) { fail_check("unexpected project #{project}") }
  unless services.keys.sort == expected_services.sort
    fail_check("#{project}: service set differs from contract")
  end

  services.each do |name, service|
    fail_check("duplicate service #{name}") if seen_services[name]
    seen_services[name] = project
    parsed_services[name] = service

    image = service["image"]
    fail_check("#{name}: image is not tag@sha256") unless image&.match?(IMAGE_PATTERN)
    tag = image.split("@", 2).first.split(":").last
    fail_check("#{name}: floating image tag #{tag}") if tag.match?(FLOATING_TAGS)

    bind_sources(service).each do |source|
      fail_check("#{name}: disallowed bind source #{source.inspect}") unless bind_allowed?(source)
    end

    env_file_paths(service).each do |env_file|
      unless env_file&.match?(%r{\A/etc/zrr-compose/env/[A-Za-z0-9._-]+\.env\z})
        fail_check("#{name}: env_file must be a named file under /etc/zrr-compose/env")
      end
    end

    labels = service.fetch("labels", {}) || {}
    if labels.key?("caddy")
      networks = service_networks(service)
      fail_check("#{name}: Caddy target is not connected to edge") unless networks.include?("edge")
      fail_check("#{name}: HTTP application is missing its Stack network") unless networks.include?("default")
    end
  end
end

fail_check("expected exactly 35 services, found #{seen_services.size}") unless seen_services.size == 35
fail_check("project set differs from contract") unless seen_projects.keys.sort == EXPECTED.keys.sort
unless service_networks(parsed_services.fetch("caddy")).sort == %w[default edge]
  fail_check("final Caddy service must use only its Stack network and edge")
end

DATABASES.each do |name|
  service = parsed_services.fetch(name)
  fail_check("#{name}: database must not connect to edge") if service_networks(service).include?("edge")
  fail_check("#{name}: database requires readiness healthcheck") unless service["healthcheck"]
end

HEALTHY_DEPENDENCIES.each do |service_name, dependencies|
  declared = parsed_services.fetch(service_name).fetch("depends_on", {})
  dependencies.each do |dependency|
    condition = declared.dig(dependency, "condition")
    fail_check("#{service_name}: #{dependency} must use service_healthy") unless condition == "service_healthy"
  end
end

verification_action = File.read("komodo/resources/actions.toml")
seen_services.each_key do |service|
  fail_check("home-verify does not name #{service}") unless verification_action.include?(%Q{"#{service}"})
end
parsed_services.each do |service_name, service|
  labels = service.fetch("labels", {}) || {}
  next unless labels["caddy"]

  labels["caddy"].split.each do |hostname|
    unless verification_action.include?(%Q{"https://#{hostname}"})
      fail_check("home-verify does not check #{hostname} for #{service_name}")
    end
  end
end

without_healthcheck = parsed_services.filter_map do |name, service|
  name unless service["healthcheck"] || name == "restic"
end
unless without_healthcheck.sort == TCP_VERIFIED.sort
  fail_check("services without healthchecks differ from the external TCP verification contract")
end

tcp_block = verification_action[/const TCP_CHECKS:.*?^};$/m]
fail_check("home-verify is missing TCP_CHECKS") unless tcp_block
TCP_VERIFIED.each do |service|
  fail_check("home-verify has no external TCP check for #{service}") unless tcp_block.include?(%Q{"#{service}":})
end
unless verification_action.include?("docker exec restic restic snapshots")
  fail_check("home-verify has no repository check for restic")
end

core_compose = YAML.safe_load_file("komodo/core/compose.yml", aliases: false)
core_services = core_compose.fetch("services")
unless core_services.keys.sort == %w[core mongo]
  fail_check("Komodo Core compose must contain only Core and MongoDB")
end
core_services.each do |name, service|
  fail_check("Komodo #{name}: image is not tag@sha256") unless service["image"]&.match?(IMAGE_PATTERN)
  fail_check("Komodo #{name}: missing komodo.skip label") unless service.fetch("labels", {}).key?("komodo.skip")
end

edge_base = File.read("deployments/home/home-edge/compose.yml")
edge_migration = File.read("deployments/home/home-edge/compose.migration.yml")
fail_check("final edge compose must not contain home_default") if edge_base.include?("home_default")
unless edge_migration.include?("CADDY_INGRESS_NETWORKS: edge,home_default")
  fail_check("edge migration overlay must preserve old home ingress")
end
stacks_resource = File.read("komodo/resources/stacks.toml")
unless stacks_resource.include?('file_paths = ["compose.yml", "compose.migration.yml"]')
  fail_check("home-edge Stack must include the migration overlay until cutover completes")
end
unless core_services.dig("core", "image").start_with?("ghcr.io/moghtech/komodo-core:2.2.0@")
  fail_check("Komodo Core must be pinned to 2.2.0")
end
unless File.read("komodo/periphery/install.sh").include?("readonly version=v2.2.0")
  fail_check("Periphery installer must be pinned to v2.2.0")
end

puts "compose contract: 9 projects, 35 unique services, Core 2.2.0, images, binds, networks, and readiness checks are valid"
