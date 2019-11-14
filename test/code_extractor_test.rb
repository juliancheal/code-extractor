require 'test_helper'

class CodeExtractorTest < CodeExtractor::TestCase
  def test_code_extractor
    create_base_repo
    set_extractions ["foo"]
    output, _ = run_extraction

    assert_no_tags
    assert output.include? "Cloning…"
    assert output.include? "Removing tag v1.0"
    assert output.include? "Removing tag v2.0"
    assert output.include? 'Extracting Branch…'

    in_git_dir do
      assert_includes current_commit_message, "Extract my_extractions"

      refute Dir.exist?  "foo"
      assert File.exist? "baz"
      assert File.exist? "qux"
    end

    on_branch "master" do
      assert_includes current_commit_message, "add Bar content"
      assert_includes current_commit_message, "(transferred from MyOrg/repo@"

      assert File.exist? "foo/bar"
      refute File.exist? "baz"
      refute File.exist? "qux"
    end
  end

  def test_code_extractor_removes_existing_extraction_branch
    repo_structure = %w[
      foo/bar
      baz
    ]

    create_repo repo_structure do
      create_branch "extract_my_extractions"
      checkout "extract_my_extractions"
    end

    set_extractions ["foo"]
    _, err = run_extraction

    assert_no_tags
    refute err.include? "fatal: A branch named 'extract_my_extractions' already exists."

    in_git_dir do
      assert_includes current_commit_message, "Extract my_extractions"

      refute Dir.exist?  "foo"
      assert File.exist? "baz"
    end

    on_branch "master" do
      assert_includes current_commit_message, "Initial Commit"
      assert_includes current_commit_message, "(transferred from MyOrg/repo@"

      assert File.exist? "foo/bar"
      refute File.exist? "baz"
    end
  end

  def test_code_extractor_skips_cloning_if_directory_exists
    repo_structure = %w[
      foo/bar
      baz
    ]

    create_repo repo_structure do
      create_branch "extract_my_extractions"
      checkout "extract_my_extractions"
    end

    Rugged::Repository.clone_at repo_dir, extracted_dir

    set_extractions ["foo"]
    output, _ = run_extraction

    assert_no_tags
    refute output.include? "Cloning…"

    in_git_dir do
      assert_includes current_commit_message, "Extract my_extractions"

      refute Dir.exist?  "foo"
      assert File.exist? "baz"
    end

    on_branch "master" do
      assert_includes current_commit_message, "Initial Commit"
      assert_includes current_commit_message, "(transferred from MyOrg/repo@"

      assert File.exist? "foo/bar"
      refute File.exist? "baz"
    end
  end

  def test_unextract_an_extraction
    # original extraction to work off of, in which we "un-extract" this later
    create_base_repo
    set_extractions ["foo"]
    run_extraction

    # Merge our extracted branch (removed code) into the master branch of the
    # original repository
    #
    is_bare       = true
    bare_repo_dir = File.join @sandbox_dir, "bare_original.git"
    Rugged::Repository.init_at bare_repo_dir, is_bare

    # Can't push to a local non-bare repo via Rugged currently... hence this
    # extra weirdness being done...
    destination_repo.remotes.create("original", bare_repo_dir)
    destination_repo.remotes["original"].push [destination_repo.head.name]

    original_repo.remotes.create("origin", bare_repo_dir)
    original_repo.fetch("origin")
    original_repo.remotes["origin"].push [original_repo.head.name]
    original_repo.create_branch "extract_my_extractions", "origin/extract_my_extractions"

    # Code is a combination of the examples found here:
    #
    #   - https://github.com/libgit2/rugged/blob/3de6a0a7/test/merge_test.rb#L4-L18
    #   - http://violetzijing.is-programmer.com/2015/11/6/some_notes_about_rugged.187772.html
    #   - https://stackoverflow.com/a/27290470
    #
    # In otherwords... not obvious how to do a `git merge --no-ff --no-edit`
    # with rugged... le-sigh...
    #
    # TODO: Move into a helper
    base        = original_repo.branches["master"].target_id
    topic       = original_repo.branches["extract_my_extractions"].target_id
    merge_index = original_repo.merge_commits(base, topic)

    Rugged::Commit.create(
      original_repo,
      :message    => "Merged branch 'extract_my_extractions' into master",
      :parents    => [base, topic],
      :tree       => merge_index.write_tree(original_repo),
      :update_ref => "HEAD"
    )

    original_repo.remotes['origin'].push [original_repo.head.name]


    # Run new extraction, with some extra commits added to the new repo that
    # has been extracted previously

    new_upstream_dir       = File.join @sandbox_dir, "new_upstream.git"
    cloned_extractions_dir = File.join @sandbox_dir, "cloned_extractions.git"

    CodeExtractor::TestRepo.clone_at extracted_dir, cloned_extractions_dir do
      checkout_b 'master', 'origin/master'

      update_file "foo/bar", "Updated Bar Content"
      commit "update bar content"

      update_file "foo/baz", "Baz Content"
      commit "add new baz"
    end

    # Update the configuration for the (second) extraction

    set_extractions ["foo"]

    extractions_hash[:name]               = "the_extracted"
    extractions_hash[:reinsert]           = true
    extractions_hash[:target_name]        = "MyOrg/extracted_repo"
    extractions_hash[:target_remote]      = bare_repo_dir
    extractions_hash[:target_base_branch] = "master"
    extractions_hash[:upstream]           = cloned_extractions_dir
    extractions_hash[:upstream_name]      = "MyOrg/repo"
    extractions_hash[:extra_cmds]         = [
      "mkdir lib",
      "mv foo lib",
      "git add -A",
      "git commit -m 'Move foo/ into lib/'"
    ]

    set_destination_dir new_upstream_dir

    # The run the actual extraction we are testing
    #
    # aka:  updated commits and puts 'lib/foo' back into the original repo
    run_extraction

    in_git_dir do
      assert_commits [
        "Move foo/ into lib/",
        "add new baz",
        "update bar content",
        "Re-insert extractions from MyOrg/extracted_repo",
        "Merged branch 'extract_my_extractions' into master",
        "Extract my_extractions",
        "Commit #3",
        "add Bar content",
        "Initial Commit"
      ]

      refute Dir.exist?  "foo"
      assert File.exist? "qux"
      assert File.exist? "lib/foo/bar"
      assert File.exist? "lib/foo/baz"
    end
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
end
