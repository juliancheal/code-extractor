require 'test_helper'

class CodeExtractorReinsertTest < CodeExtractor::TestCase
  def test_unextract_an_extraction
    # original extraction to work off of, in which we "un-extract" this later
    create_base_repo
    set_extractions ["foo"]
    run_extraction

    # Perform updates to extracted repo to simulate changes since extraction
    perform_merges_of_extracted_code
    apply_new_commits_on_extracted_repo
    update_extraction_hash

    # Run new extraction, with some extra commits added to the new repo that
    # has been extracted previously
    #
    # This next line will run the actual extraction we are testing
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

  def perform_merges_of_extracted_code
    # Merge our extracted branch (removed code) into the master branch of the
    # original repository
    #
    is_bare        = true
    @bare_repo_dir = File.join @sandbox_dir, "bare_original.git"
    Rugged::Repository.init_at @bare_repo_dir, is_bare

    # Can't push to a local non-bare repo via Rugged currently... hence this
    # extra weirdness being done...
    destination_repo.remotes.create("original", @bare_repo_dir)
    destination_repo.remotes["original"].push [destination_repo.head.name]

    original_repo.remotes.create("origin", @bare_repo_dir)
    original_repo.fetch("origin")
    original_repo.remotes["origin"].push [original_repo.head.name]
    original_repo.create_branch "extract_my_extractions", "origin/extract_my_extractions"

    CodeExtractor::TestRepo.merge original_repo, "extract_my_extractions"
    original_repo.remotes['origin'].push [original_repo.head.name]
  end

  def apply_new_commits_on_extracted_repo
    @new_upstream_dir       = File.join @sandbox_dir, "new_upstream.git"
    @cloned_extractions_dir = File.join @sandbox_dir, "cloned_extractions.git"

    CodeExtractor::TestRepo.clone_at extracted_dir, @cloned_extractions_dir do
      checkout_b 'master', 'origin/master'

      update_file "foo/bar", "Updated Bar Content"
      commit "update bar content"

      update_file "foo/baz", "Baz Content"
      commit "add new baz"
    end
  end

  # Update the configuration for the (second) extraction
  #
  # Boiler plate will do the following:
  #
  #   - Assumes "foo/" is still the only extracted directory
  #   - A "reinsert" is the new action that will be performed
  #   - The following methods have been executed prior
  #     * `.create_base_repo`
  #     * `.perform_merges_of_extracted_code`
  #     * `.apply_new_commits_on_extracted_repo`
  #   - As a result, assumes the following instance variables are set:
  #     * `@new_upstream_dir`
  #     * `@bare_repo_dir`
  #     * `@cloned_extractions_dir`
  #   - The desired behavior of `.extra_cmds` is to move `foo` into `lib/`
  #
  # There is a `custom_updates` hash available in the args for adding
  # additional changes, so if any of the above are not the case, changes can be
  # made at the end.
  #
  def update_extraction_hash custom_updates = {}
    set_extractions ["foo"]
    set_destination_dir @new_upstream_dir

    extractions_hash[:name]               = "the_extracted"
    extractions_hash[:reinsert]           = true
    extractions_hash[:target_name]        = "MyOrg/extracted_repo"
    extractions_hash[:target_remote]      = @bare_repo_dir
    extractions_hash[:target_base_branch] = "master"
    extractions_hash[:upstream]           = @cloned_extractions_dir
    extractions_hash[:upstream_name]      = "MyOrg/repo"
    extractions_hash[:extra_cmds]         = [
      "mkdir lib",
      "mv foo lib",
      "git add -A",
      "git commit -m 'Move foo/ into lib/'"
    ]

    custom_updates.each do |hash_key, value|
      extractions_hash[hash_key] = value
    end
  end
end
