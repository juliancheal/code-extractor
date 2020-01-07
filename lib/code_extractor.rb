require 'yaml'

# Class to extract files and folders from a git repository, while maintaining
# The git history.
module CodeExtractor
  def run
    Runner.new.extract
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
    attr_reader :name, :url, :git_dir, :new_branch, :source_branch

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
        `git fetch upstream && git rebase upstream/master`
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

    def filter_branch extractions, upstream_name
      Dir.chdir git_dir do
        `time git filter-branch --index-filter '
        git read-tree --empty
        git reset $GIT_COMMIT -- #{extractions}
        ' --msg-filter '
        cat -
        echo
        echo
        echo "(transferred from #{upstream_name}@$GIT_COMMIT)"
        ' -- #{source_branch} -- #{extractions}`
      end
    end
  end

  class Runner
    def initialize config = nil
      @config         = config || Config.new
      @source_project = GitProject.new @config[:name], @config[:upstream]
    end

    def extractions
      @extractions ||= @config[:extractions].join(' ')
    end

    def extract
      puts @config
      @source_project.clone_to @config[:destination]
      @source_project.extract_branch @config[:upstream_branch], "extract_#{@config[:name]}", extractions
      @source_project.remove_remote
      @source_project.remove_tags
      @source_project.filter_branch extractions, @config[:upstream_name]
    end
  end
end

if $PROGRAM_NAME == __FILE__
  CodeExtractor.run
end
