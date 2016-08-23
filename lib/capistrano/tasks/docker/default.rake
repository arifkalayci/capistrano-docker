namespace :docker do
  namespace :deploy do
    task :default do
      order = %w( prepare build run clean tag )
      order = %w( prepare build clean run tag ) if fetch(:docker_clean_before_run)
      order.each do |task|
        invoke "docker:deploy:default:#{task}"
      end
    end

    namespace :default do
      desc "Prepares docker for building"
      task :prepare do
        on roles(fetch(:docker_role)) do
          within release_path do
            fetch(:docker_copy_data).each do |file|
              execute :cp, " -aR #{shared_path}/#{file} #{release_path}/#{file}"
            end
          end
        end
      end

      task :build do
        on roles(fetch(:docker_role)) do
          within release_path do
            execute :docker, build_command
          end
        end
      end

      task :run do
        on roles(fetch(:docker_role)) do
          invoke 'docker:deploy:default:clean_current' if running?
          execute :docker, run_command
        end
      end
      before :run, "docker:current_revision"

      task :clean_current do
        on roles(fetch(:docker_role)) do
          execute stop_container(fetch(:docker_current_container))
          execute remove_container(fetch(:docker_current_container))
        end
      end
      before :clean_current, "docker:current_revision"

      task :clean do
        on roles(fetch(:docker_role)) do
          old_containers.each do |id, image, rev|
            if rev != fetch(:current_revision)
              execute stop_container(id)
              execute remove_container(id)
            end
          end
        end
      end
      before :clean, "docker:current_revision"

      task :tag do
        on roles(fetch(:docker_role)) do
          execute :docker, "tag #{fetch(:docker_image_full)} #{fetch(:docker_image)}:latest"
        end
      end
    end
  end

  def running?
    cmd = %(docker ps -f "name=#{fetch(:docker_current_container)}" --format '{{.Status}}')
    capture(cmd).match(/^Up.+/)
  end

  def old_containers
    cmd = %(docker ps -f "name=#{fetch(:application)}_" --format '{{.ID}} {{.Image}} {{.Label "git.revision.id"}}')
    resp = capture(cmd).split("\n").map { |x| x.split(" ") }
    resp.select { |a| a[1].index("#{fetch(:docker_image)}")}
  end

  def remove_container(container)
    "docker rm #{container}"
  end

  def run_command
    cmd = ["run"]
    cmd << "-d" if fetch(:docker_detach) == true
    cmd << "--name #{fetch(:docker_current_container)}"

    # attach volumes
    fetch(:docker_volumes).each do |volume|
      cmd << "-v #{volume}"
    end

    # attach links
    fetch(:docker_links).each do |link|
      cmd << "--link #{link}"
    end

    # attach labels
    fetch(:docker_labels).each do |label|
      cmd << "--label=#{label}"  ## example: com.example.key=value
    end

    # set cpu quota
    cmd << "--cpu-quota #{fetch(:docker_cpu_quota)}" unless fetch(:docker_cpu_quota).nil?

    # set custom apparmor profile
    cmd << "--security-opt apparmor:#{fetch(:docker_apparmor_profile)}" unless fetch(:docker_apparmor_profile).nil?

    # attach revision label
    cmd << "--label=git.revision.id=#{fetch(:current_revision)}"

    cmd << "--restart #{fetch(:docker_restart_policy)}" unless fetch(:docker_restart_policy).nil?
    cmd << fetch(:docker_additional_options)
    cmd << fetch(:docker_image_full)

    cmd.join(" ")
  end
end
