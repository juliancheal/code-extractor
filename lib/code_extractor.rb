require 'yaml'

# Class to extract files and folders from a git repository, while maintaining
# The git history.
module CodeExtractor
  def run
    Runner.new.run
  end
  module_function :run

  class Config
    def initialize(config_file = 'extractions.yml')
      @config = YAML.load_file(config_file)

      @config[:destination]       = File.expand_path(@config[:destination])
      @config[:upstream_branch] ||= "master"

      validate!
    end

    def [](key)
      @config[key]
    end

    def inspect
      @config.inspect
    end
    alias to_s inspect

    def validate!
      missing = %i[name destination upstream upstream_name extractions].reject { |k| @config[k] }
      raise ArgumentError, "#{missing.map(&:inspect).join(", ")} key(s) missing" if missing.any?
    end
  end

  class GitProject
    attr_reader :name, :url, :git_dir, :new_branch, :source_branch, :target_name

    def initialize name, url
      @name   = name
      @url    = url
    end

    def clone_to destination, origin_name = "upstream"
      @git_dir ||= destination

      if Dir.exist?(git_dir)
        raise "Not a git dir!" unless system "git -C #{git_dir} status"
      else
        puts 'Cloning…'
        system "git clone --origin #{origin_name} #{url} #{git_dir}"
      end
    end

    def extract_branch source_branch, new_branch, extractions
      puts 'Extracting Branch…'
      @new_branch    = new_branch
      @source_branch = source_branch
      Dir.chdir git_dir do
        `git checkout #{source_branch}`
        `git fetch upstream && git rebase upstream/#{source_branch}`
        if system("git branch | grep #{new_branch}")
          `git branch -D #{new_branch}`
        end
        `git checkout -b #{new_branch}`
        `git rm -r #{extractions}`
        `git commit -m "Extract #{name}"`
      end
    end

    def remove_remote
      Dir.chdir git_dir do
        `git remote rm upstream`
      end
    end

    def remove_tags
      puts 'removing tags'
      Dir.chdir git_dir do
        tags = `git tag`
        tags.split.each do |tag|
          puts "Removing tag #{tag}"
          `git tag -d #{tag}`
        end
      end
    end

    def extract_commits extractions, upstream_name
      Dir.chdir git_dir do
        `time git filter-branch --index-filter '
        git read-tree --empty
        git reset $GIT_COMMIT -- #{extractions}
        ' #{msg_filter upstream_name} -- #{source_branch} -- #{extractions}`
      end
    end

    def prune_commits extractions
      puts "Pruning commits…"

      build_prune_script extractions

      Dir.chdir git_dir do
        `git checkout -b #{prune_branch} #{@source_branch}`
        `git filter-branch -f --prune-empty --tree-filter #{@prune_script} HEAD`
        `git filter-branch -f --prune-empty --subdirectory-filter #{@keep_directory}`
      end
    end

    def add_target_remote target_name, target_remote
      puts "Add target repo as a remote…"
      @target_name = target_name

      Dir.chdir git_dir do
        puts "git remote add #{target_remote_name} #{target_remote}"
        `git remote add #{target_remote_name} #{target_remote}`
        `git fetch #{target_remote_name}`
      end
    end

    # "Inject" commits one repo's branch back into the target repo's
    #
    # Assuming the target remote has been added (see add_target_remote), this
    # method does so by doing the following to achieve the "injected" history:
    #
    # 1. Filters commits that already exist in the target repo.  Additionally,
    # the last commit that is shared between the two is actually used as the
    # "root" commit for the injected commits.  The rest are assumed to be new
    # from the new repository.
    #
    # The "root" commit has it's commit message modified to reflect this
    # change.
    #
    # The other part of the filter branch also applies the changes so they
    # exist within in context the target codebase, and not just in isolation
    # for itself (hence the `git reset #{@reference_target_branch} -- .` bit).
    # The changes from the upstream repo are then applied on top of the
    # existing code base.
    #
    # 2. A new branch is checked out that is based off the target remote's
    # target branch, but does not track that branch.
    #
    # 3. The commits that have been filtered are cherry-picked on to this new
    # branch, and the "root" commit assumes the parent of the current HEAD of
    # the target remote's (master) branch
    #
    def inject_commits target_base_branch, upstream_name
      puts "Injecting commits…"

      target_base_branch ||= 'master'
      commit_msg_filter    = "(transferred from #{upstream_name}"

      Dir.chdir git_dir do
        reference_target_branch      = "#{target_remote_name}/#{target_base_branch}"
        previously_extracted_commits = `git log --pretty="%H" --grep="#{commit_msg_filter}"`

        # special commit that will get renamed re-worded to:
        #
        #   Re-insert extractions from #{upstream_name}
        #
        last_extracted_commit = previously_extracted_commits.lines[0].chomp!
        first_injected_msg    = `git show -s --format="%s%n%n%b" #{last_extracted_commit}`
        first_injected_msg    = first_injected_msg.lines.reject { |line|
                                  line.include? commit_msg_filter
                                }.join
        first_injected_msg.prepend "*** Original Commit message shown below ***\n\n"
        first_injected_msg.prepend "Re-insert extractions from #{target_name}\n\n"
        File.write File.expand_path("../LAST_EXTRACTED_COMMIT_MSG", git_dir), first_injected_msg

        `time git filter-branch -f --commit-filter '
          export was_extracted=$(git show -s --format="%s%n%n%b" $GIT_COMMIT | grep -s "#{commit_msg_filter}")
          if [ "$GIT_COMMIT" = "#{last_extracted_commit}" ] || [ "$was_extracted" == ""  ]; then
            git commit-tree "$@";
          else
            skip_commit "$@";
          fi
        ' --index-filter '
        git read-tree --empty
        git reset #{reference_target_branch} -- .
        git checkout $GIT_COMMIT -- .
        ' --msg-filter '
          if [ "$GIT_COMMIT" = "#{last_extracted_commit}" ]; then
            cat #{File.expand_path File.join("..", "LAST_EXTRACTED_COMMIT_MSG"), git_dir}
          else
            cat -
          fi
          echo
          echo
          echo "(transferred from #{upstream_name}@$GIT_COMMIT)"
        ' -- #{prune_branch}`

        `git checkout --no-track -b #{inject_branch} #{reference_target_branch}`
        `git cherry-pick ..#{prune_branch}`
      end
    end

    def run_extra_cmds cmds
      Dir.chdir git_dir do
        cmds.each { |cmd| system cmd } if cmds
      end
    end

    private

    def target_remote_name
      @target_remote_name ||= "code_extractor_target_for_#{name}"
    end

    def prune_branch
      @prune_branch ||= "code_extractor_prune_#{name}"
    end
    alias prune_commits_remote prune_branch

    def inject_branch
      @inject_branch ||= "code_extractor_inject_#{name}"
    end
    alias inject_remote inject_branch

    # Given a list of extractions, build a script that will move a list of
    # files (extractions) from their current location in a given commit to a
    # unused directory.
    #
    # More complicated than it looks, this will be used as part of a two-phased
    # `git filter-branch` to:
    #
    #   1. move extractable files into a subdirectory with `--tree-filter`
    #   2. only keep commits for files moved into that subdirectory, and make
    #      the subdirectory the new project root.
    #
    # For consistency, we want to keep the subdirectories' structure in the
    # same line as what was there previously, so this script helps do that, and
    # also creates directories/files when they don't exist.
    #
    # Returns `true` at the end of the script incase the last `mv` fails (the
    # source doesn't exist in this commit, for example)
    #
    def build_prune_script extractions
      require 'set'
      require 'fileutils'

      @keep_directory = "code_extractor_git_keeps_#{Time.now.to_i}"
      git_log_follow  = "git log --name-only --format=format: --follow"
      prune_mkdirs    = Set.new
      prune_mvs       = []

      Dir.chdir git_dir do
        extractions.each do |file_or_dir|
          if Dir.exist? file_or_dir
            files = Dir.glob["#{file_or_dir}/**/*"]
          else
            files = [file_or_dir]
          end

          files.each do |extraction_file|
            file_and_ancestors = `#{git_log_follow} -- #{extraction_file}`.split("\n").uniq

            file_and_ancestors.reject! { |file| file.length == 0 }

            file_and_ancestors.each do |file|
              file_dir = File.dirname file
              prune_mkdirs.add file_dir
              prune_mvs << [file, "#{@keep_directory}/#{file_dir}"]
            end
          end
        end
      end

      @prune_script = File.join Dir.pwd, "code_extractor_#{name}_prune_script.sh"

      File.open @prune_script, "w" do |script|
        prune_mkdirs.each do |dir|
          script.puts "mkdir -p #{File.join @keep_directory, dir}"
        end

        script.puts
        prune_mvs.each do |(file, dir)|
          script.puts "mv #{file} #{dir} 2>/dev/null"
        end

        script.puts
        script.puts "true"
      end
      FileUtils.chmod "+x", @prune_script
    end

    def msg_filter upstream_name
      <<-MSG_FILTER.gsub(/^ {8}/, '').chomp
        --msg-filter '
        cat -
        echo
        echo
        echo "(transferred from #{upstream_name}@$GIT_COMMIT)"
        '
      MSG_FILTER
    end
  end

  class Runner
    def initialize config = nil
      @config         = config || Config.new
      @source_project = GitProject.new @config[:name], @config[:upstream]
    end

    # Either run `.reinsert` or `.extract`
    #
    # The `.reinsert` method will eject with `nil` unless the config setting to
    # run in that mode is set
    #
    def run
      puts @config

      @source_project.clone_to @config[:destination]
      @source_project.extract_branch @config[:upstream_branch], "extract_#{@config[:name]}", extractions
      @source_project.remove_remote
      @source_project.remove_tags

      reinsert || extract
    end

    def extractions
      @extractions ||= @config[:extractions].join(' ')
    end

    def extract
      @source_project.extract_commits extractions, @config[:upstream_name]
    end

    def reinsert
      return unless @config[:reinsert]

      @source_project.prune_commits @config[:extractions]
      @source_project.run_extra_cmds @config[:extra_cmds]
      @source_project.add_target_remote @config[:target_name], @config[:target_remote]
      @source_project.inject_commits @config[:target_base_branch], @config[:upstream_name]

      true
    end
  end
end

if $PROGRAM_NAME == __FILE__
  CodeExtractor.run
end
