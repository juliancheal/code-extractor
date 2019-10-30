# code-extractor

Extracts code from from one repository to another preserving history

## How it works

The code extractor works by cloning a source repository into a specified
destination and running `git filter-branch` to extract the specified files and
directories.  Once it has completed, the new repository will be left with a
`master` branch with the extracted code with preserved history which can be
pushed into a new upstream repository.  Additionally, there will be a "deletion
branch" named `extract_$name`, which can be used to push a deletion commit to
the source repository.

## Installation

Just install the gem via rubygems:

```console
$ gem install code-extractor
```

Or if you want to do it yourself, the `lib/code_extractor.rb` file is a
standalone ruby script, so you can just download that and run it with a modern
ruby version.

## Usage

### Configuration

Create a file named `extractions.yml` with the configuration.  For example:

```yaml
---
:name: extracted_thing
:upstream: git@github.com:SourceOrg/source_repo.git
:upstream_branch: master
:upstream_name: SourceOrg/source_repo
:extractions:
  - file1
  - dir1/file2
  - dir2
:destination: /dev/new_repo
```

* `:name` - The name of the feature being extracted.  This will be used as part of
  the "deletion branch" name as well as the commit message to that branch.
* `:upstream` - The git repository URL from which the extraction will occur.
* `:upstream_branch` - The branch on `:upstream` from which the extraction will occur.
  Defaults to "master" if not set.
* `:upstream_name` - The name of the repository from with the extraction will occur.
  This will be used in the extracted commit messages to relate back to the original
  repository.  With the example yaml above, this would cause the following to be
  added to the commit messages:
  `(transferred from SourceOrg/source_repo@$GIT_COMMIT)`
* `:extractions` - An array of files and directories to be extracted.
* `:destination` - The target directory for the extracted repository.

### Execution

If you have install this as a gem, you can just run:

```console
$ code-extractor
```

But if you installed this manually, just either make the script executable, or
run it with the ruby interpreter via.

```console
$ ruby code_extractor.rb
```

This shouldn't be run in the directory of the original repository, but instead
in an empty directory where the clone can be created and modified.

### Post-execution

* Push the master branch to a new target repository.  For example:

    ```
    git remote add upstream git@github.com:SomeOrg/new_repo.git
    git push -u upstream master
    ```

* Create a pull request to delete the extracted code from the source repository.
  For example:

    ```
    git remote add source git@github.com:SomeOrg/source_repo.git
    git push -u source extract_$name
    # Create a pull request from the extract_$name branch
    ```
