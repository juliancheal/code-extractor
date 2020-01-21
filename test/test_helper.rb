$LOAD_PATH.unshift File.expand_path(File.join("..", "..", "lib"), __FILE__)

require 'code_extractor'

require 'yaml'
require 'fileutils'
require 'pathname'
require 'rugged'
require 'minitest/autorun'

TEST_DIR     = File.expand_path "..", __FILE__
TEST_SANDBOX = File.join TEST_DIR, "tmp", "sandbox"

FileUtils.mkdir_p TEST_SANDBOX

module CodeExtractor
  # Base class for all test classes.
  #
  # Will create a sandbox directory in `test/tmp/sandbox`, uniq to each test
  # method, and will initialize the source repo and common settings for every
  # test, and clean up when it is done.
  #
  class TestCase < Minitest::Test
    attr_writer :extractions, :extractions_hash, :reference_repo_dir
    attr_reader :extracted_dir, :repo_dir, :sandbox_dir

    # Create a sandbox for the given test, and name it after the test class and
    # method name
    def setup
      @extractions   = []
      @sandbox_dir   = Dir.mktmpdir "#{self.class.name}_#{@NAME}", TEST_SANDBOX
      @repo_dir      = File.join @sandbox_dir, "repo.git"
      @extracted_dir = File.join @sandbox_dir, "extracted.git"
    end

    def teardown
      FileUtils.remove_entry @sandbox_dir unless ENV["DEBUG"]
    end

    def create_base_repo
      repo_structure = %w[
        foo/bar
        baz
      ]

      create_repo repo_structure do
        update_file "foo/bar", "Bar Content"
        commit "add Bar content"
        tag "v1.0"

        add_file "qux", "QUX!!!"
        commit
        tag "v2.0"
      end
    end

    # Custom Assertions

    def assert_no_tags
      tags = destination_repo.tags.map(&:name)
      assert tags.empty?, "Expected there to be no tags, but got `#{tags.join ', '}'"
    end

    TRANSFERRED_FROM_REGEXP = /\(transferred from (?<UPSTREAM>[^@]*)@(?<SHA>[^\)]*)\)/
    def assert_commits expected_commits
      start_commit   = destination_repo.last_commit
      sorting        = Rugged::SORT_TOPO # aka:  sort like git-log
      actual_commits = destination_repo.walk(start_commit, sorting).map {|c| c }
      commit_msgs    = actual_commits.map { |commit| commit.message.lines.first.chomp }

      assert_equal expected_commits, commit_msgs

      # Check that the "transferred from ..." reference line is correct
      actual_commits.map do |commit|
        [
          commit,
          commit.message.lines.last.match(TRANSFERRED_FROM_REGEXP)
        ]
      end.each do |commit, transfered|
        next unless transfered

        transferred_commit = reference_repo.lookup(transfered[:SHA])
        assert transferred_commit.is_a?(Rugged::Commit),
          "'transfered from' of #{transfered[:SHA]} from #{commit} is not a valid commit"
        assert_equal commit.message.lines.first.chomp,
          transferred_commit.message.lines.first.chomp
      end
    end

    # Helper methods

    def original_repo
      @original_repo ||= Rugged::Repository.new @repo_dir
    end

    def destination_repo
      @destination_repo ||= Rugged::Repository.new @extracted_dir
    end

    def reference_repo
      @reference_repo ||= Rugged::Repository.new @reference_repo_dir
    end

    def current_commit_message
      destination_repo.head.target.message
    end

    def in_git_dir
      Dir.chdir @extracted_dir do
        yield
      end
    end

    def on_branch new_branch, &block
      current_branch = destination_repo.head.name
      destination_repo.checkout new_branch

      in_git_dir(&block)
    ensure
      destination_repo.checkout current_branch
    end

    def create_repo file_structure, &block
      TestRepo.generate repo_dir, file_structure, &block
    end

    def run_extraction
      pwd = Dir.pwd

      extractions_yml = File.join sandbox_dir, "extractions.yml"
      File.write extractions_yml, extractions_yaml

      capture_subprocess_io do
        config = Config.new extractions_yml
        Runner.new(config).run
      end
    ensure
      Dir.chdir pwd
    end

    def set_extractions new_extractions
      @extractions = new_extractions
      extractions_hash[:extractions] = @extractions
    end

    def set_destination_dir dir
      @destination_repo = nil # reset
      @extracted_dir    = dir
      extractions_hash[:destination] = @extracted_dir
    end

    def extractions_hash
      @extractions_hash ||= {
        :name          => "my_extractions",
        :upstream      => @repo_dir,
        :upstream_name => "MyOrg/repo",
        :extractions   => @extractions,
        :destination   => @extracted_dir
      }
    end

    def extractions_yaml
      extractions_hash.to_yaml
    end
  end

  # = TestRepo
  #
  # This is a modified form of the fake_ansible_repo.rb spec helper from the
  # ManageIQ project:
  #
  #     https://github.com/ManageIQ/manageiq/blob/f8e70535/spec/support/fake_ansible_repo.rb
  #
  # Which uses Rugged to create a stub git project for testing against with a
  # configurable file structure.  To generate a repo, you just needs to be
  # given a repo_path and a file tree definition.
  #
  #     file_tree_definition = %w[
  #       foo/one.txt
  #       bar/baz/two.txt
  #       qux/
  #       README.md
  #     ]
  #     TestRepo.generate "/path/to/my_repo", file_tree_definition
  #
  #
  # == File Tree Definition
  #
  # The file tree definition (file_struct) is just passed in as a word array for
  # each file/empty-dir entry for the repo.
  #
  # So for a single file repo with a `foo.txt` plain text file, the definition
  # as an array would be:
  #
  #     file_struct = %w[
  #       foo.txt
  #     ]
  #
  # This will generate a repo with a single file called `foo.txt`.  For a more
  # complex example:
  #
  #     file_struct = %w[
  #       bin/foo
  #       lib/foo.rb
  #       lib/foo/version.rb
  #       test/test_helper.rb
  #       test/foo_test.rb
  #       tmp/
  #       LICENSE
  #       README.md
  #     ]
  #
  # NOTE:  directories only need to be defined on their own if they are intended
  # to be empty, otherwise a defining files in them is enough.
  #
  class TestRepo
    attr_accessor :repo
    attr_reader   :file_struct, :last_commit, :repo_path,:index

    def self.generate repo_path, file_struct, &block
      repo = new repo_path, file_struct
      repo.generate(&block)
    end

    def self.clone_at url, dir, &block
      repo = new dir, []
      repo.clone(url, &block)
    end

    def self.merge repo, branch, base_branch = nil
      repo = Rugged::Repository.new repo unless repo.is_a? Rugged::Repository
      dir  = repo.workdir

      test_repo = new dir, []
      test_repo.repo = repo
      test_repo.merge branch, base_branch
    end

    def initialize repo_path, file_struct
      @commit_count = 0
      @repo_path    = Pathname.new repo_path
      @name         = @repo_path.basename
      @file_struct  = file_struct
      @last_commit  = nil
    end

    def generate &block
      build_repo(repo_path, file_struct)

      git_init
      git_commit_initial

      execute(&block) if block_given?
    end

    def clone url, &block
      @repo        = Rugged::Repository.clone_at url, @repo_path.to_s
      @index       = repo.index
      @last_commit = repo.last_commit
      # puts @repo.inspect

      execute(&block) if block_given?
    end

    # Run DSL methods for given TestRepo instance
    def execute &block
      instance_eval(&block)
    end

    # Create a new branch (don't checkout)
    #
    #   $ git branch other_branch
    #
    def create_branch new_branch_name
      repo.create_branch new_branch_name
    end

    def checkout branch
      repo.checkout branch
    end

    def checkout_b branch, source = nil
      repo.create_branch(*[branch, source].compact)
      repo.checkout branch
      @last_commit = repo.last_commit
    end

    # Commit with all changes added to the index
    #
    #   $ git add . && git commit -am "${msg}"
    #
    def commit msg = nil
      git_add_all
      @commit_count += 1

      @last_commit = Rugged::Commit.create(
        repo,
        :message    => msg || "Commit ##{@commit_count}",
        :parents    => [@last_commit].compact,
        :tree       => index.write_tree(repo),
        :update_ref => "HEAD"
      )
    end

    def tag tag_name
      repo.tags.create tag_name, @last_commit
    end

    # Add a merge branch into current branch with `--no-ff`
    #
    # (AKA:  Merge a PR like on github)
    #
    #   $ git merge --no-ff --no-edit
    #
    # If `base_branch` is passed, use that, otherwise use `HEAD`
    #
    def merge branch, base_branch = nil
      # Code is a combination of the examples found here:
      #
      #   - https://github.com/libgit2/rugged/blob/3de6a0a7/test/merge_test.rb#L4-L18
      #   - http://violetzijing.is-programmer.com/2015/11/6/some_notes_about_rugged.187772.html
      #   - https://stackoverflow.com/a/27290470
      #
      # In otherwords... not obvious how to do a `git merge --no-ff --no-edit`
      # with rugged... le-sigh...
      repo.checkout base_branch if base_branch

      base        = (base_branch ? repo.branches[base_branch] : repo.head).target_id
      topic       = repo.branches[branch].target_id
      merge_index = repo.merge_commits(base, topic)

      Rugged::Commit.create(
        repo,
        :message    => "Merged branch '#{branch}' into #{base_branch || current_branch_name}",
        :parents    => [base, topic],
        :tree       => merge_index.write_tree(repo),
        :update_ref => "HEAD"
      )

      repo.checkout_head :strategy => :force
      @last_commit = repo.last_commit
    end

    # Add (or update) a file in the repo, and optionally write content to it
    #
    # The content is optional, but it will fully overwrite the content
    # currently in the file.
    #
    def add_file entry, content = nil
      path          = repo_path.join entry
      dir, filename = path.split unless entry.end_with? "/"

      FileUtils.mkdir_p dir.to_s == '.' ? repo_path : dir
      FileUtils.touch path     if filename
      File.write path, content if filename && content
    end
    alias update_file add_file

    # Prepends content to an existing file
    #
    def add_to_file entry, content
      path = repo_path.join entry
      File.write path, content, :mode => "a"
    end

    def current_branch_name
      repo.head.name.sub(/^refs\/heads\//, '')
    end

    private

    # Generate repo structure based on file_structure array
    #
    # By providing a directory location and an array of paths to generate,
    # this will build a repository directory structure.  If a specific entry
    # ends with a '/', then an empty directory will be generated.
    #
    # Example file structure array:
    #
    #     file_struct = %w[
    #       foo/one.txt
    #       bar/two.txt
    #       baz/
    #       qux.txt
    #     ]
    #
    def build_repo repo_path, file_structure
      file_structure.each do |entry|
        add_file entry
      end
    end

    # Init new repo at local_repo
    #
    #   $ cd /tmp/clone_dir/test_repo && git init .
    #
    def git_init
      @repo  = Rugged::Repository.init_at repo_path.to_s
      @index = repo.index
    end

    # Add new files to index
    #
    #   $ git add .
    #
    def git_add_all
      index.add_all
      index.write
    end

    # Create initial commit
    #
    #   $ git commit -m "Initial Commit"
    #
    def git_commit_initial
      commit "Initial Commit"
    end
  end
end
