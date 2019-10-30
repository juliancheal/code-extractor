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

      @config[:upstream_branch] ||= "master"
      @config[:destination]       = File.expand_path(@config[:destination])

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

  class Runner
    def initialize config = nil
      @config = config || Config.new
    end

    def extract
      puts @config
      clone
      extract_branch
      remove_remote
      remove_tags
      filter_branch
    end

    def clone
      return if Dir.exist?(@config[:destination])
      puts 'Cloning…'
      system "git clone -o upstream #{@config[:upstream]} #{@config[:destination]}"
    end

    def extract_branch
      puts 'Extracting Branch…'
      Dir.chdir(@config[:destination])
      branch = "extract_#{@config[:name]}"
      `git checkout #{@config[:upstream_branch]}`
      `git fetch upstream && git rebase upstream/master`
      if system("git branch | grep #{branch}")
        `git branch -D #{branch}`
      end
      `git checkout -b #{branch}`
      extractions = @config[:extractions].join(' ')
      `git rm -r #{extractions}`
      `git commit -m "Extract #{@config[:name]}"`
    end

    def remove_remote
      `git remote rm upstream`
    end

    def remove_tags
      puts 'removing tags'
      tags = `git tag`
      tags.split.each do |tag|
        puts "Removing tag #{tag}"
        `git tag -d #{tag}`
      end
    end

    def filter_branch
      extractions = @config[:extractions].join(' ')
      `time git filter-branch --index-filter '
      git read-tree --empty
      git reset $GIT_COMMIT -- #{extractions}
      ' --msg-filter '
      cat -
      echo
      echo
      echo "(transferred from #{@config[:upstream_name]}@$GIT_COMMIT)"
      ' -- #{@config[:upstream_branch]} -- #{extractions}`
    end
  end
end

if $PROGRAM_NAME == __FILE__
  CodeExtractor.run
end
