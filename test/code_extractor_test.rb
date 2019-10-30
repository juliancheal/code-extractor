require 'test_helper'

class CodeExtractorTest < CodeExtractor::TestCase
  def test_code_extractor
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
end
