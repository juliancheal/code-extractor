require 'yaml'

# Class to extract files and folders from a git repository, while maintaining
# The git history.
class CodeExtractor
  attr_reader :extraction

  def initialize(extraction = 'extractions.yml')
    @extraction = YAML.load_file(extraction)
    @extraction[:upstream_branch] ||= "master"

    missing = %i[name destination upstream upstream_name extractions].reject { |k| @extraction[k] }
    raise ArgumentError, "#{missing.map(&:inspect).join(", ")} key(s) missing" if missing.any?
  end

  def extract
    puts @extraction
    clone
    extract_branch
    remove_remote
    remove_tags
    filter_branch
  end

  def clone
    return if Dir.exist?(@extraction[:destination])
    puts 'Cloning…'
    system "git clone -o upstream #{@extraction[:upstream]} #{@extraction[:destination]}"
  end

  def extract_branch
    puts 'Extracting Branch…'
    Dir.chdir(@extraction[:destination])
    branch = "extract_#{@extraction[:name]}"
    `git checkout #{@extraction[:upstream_branch]}`
    `git fetch upstream && git rebase upstream/master`
    if system("git branch | grep #{branch}")
      `git branch -D #{branch}`
    end
    `git checkout -b #{branch}`
    extractions = @extraction[:extractions].join(' ')
    `git rm -r #{extractions}`
    `git commit -m "Extract #{@extraction[:name]}"`
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
    extractions = @extraction[:extractions].join(' ')
    `time git filter-branch --index-filter '
    git read-tree --empty
    git reset $GIT_COMMIT -- #{extractions}
    ' --msg-filter '
    cat -
    echo
    echo
    echo "(transferred from #{@extraction[:upstream_name]}@$GIT_COMMIT)"
    ' -- #{@extraction[:upstream_branch]} -- #{extractions}`
  end
end

code_extractor = CodeExtractor.new

code_extractor.extract
