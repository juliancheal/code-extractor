require 'yaml'

# Class to extract files and folders from a git repository, while maintaining
# The git history.
class CodeExtractor
  attr_reader :extraction

  def initialize(extraction = 'extractions.yml')
    @extraction = YAML.load_file(extraction)
  end

  def extract
    puts @extraction
    clone
    extract_branch
    filter_branch
  end

  def clone
    return if Dir.exist?(@extraction[:destination])
    puts 'Cloning…'
    system "git clone -o upstream git@github.com:ManageIQ/manageiq.git #{@extraction[:destination]}"
    puts system('git branch')
  end

  def extract_branch
    puts 'Extracting Branch…'
    Dir.chdir(@extraction[:destination])
    branch = "extract_#{@extraction[:name]}"
    `git checkout master`
    `git fetch upstream && git rebase upstream/master`
    if system("git branch | grep #{branch}")
      `git branch -D #{branch}`
    end
    `git checkout -b #{branch}`
    extractions = @extraction[:extractions].join(' ')
    `git rm -r #{extractions}`
    `git commit -m "extract #{@extraction[:name]} provider"`
  end

  def filter_branch
    # puts 'removing tags'
    # system("git tag -d #{`git tag`}")
    extractions = @extraction[:extractions].join(' ')
    # `git filter-branch --index-filter #{extractions} --msg-filter`
    # `time git filter-branch --index-filter '`
    # `git read-tree --empty`
    # `git reset $GIT_COMMIT -- #{extractions} ' --msg-filter '`
    # `cat -`
    # `echo`
    # `echo`
    # `echo "(transferred from ManageIQ/manageiq@$GIT_COMMIT)"`
    # `' -- --all -- #{extractions}`
    `time git filter-branch --index-filter '
    git read-tree --empty
    git reset $GIT_COMMIT -- #{extractions}
    ' --msg-filter '
    cat -
    echo
    echo
    echo "(transferred from ManageIQ/manageiq@$GIT_COMMIT)"
    ' -- --all -- #{extractions}`
  end
end

code_extractor = CodeExtractor.new

code_extractor.extract

# function extract_branch {
#   branch="extract_$NAME"
#   git checkout master
#   # git mup
#   git fetch upstream && git rebase upstream/master # && git push && git checkout
#   git branch -D $branch
#   git checkout -b $branch
#   git rm -r $EXTRACT_DIRS
#   git commit -m "extract $NAME provider"
# }
#
# function check_dir {
#     if [ -d $DIR ] ; then
#       if [ ! -z $FORCE ] ; then
#         echo "rm -rf $DIR"
#         rm -rf $DIR
#       else
#         echo "$DIR exists, rm or try -f"
#         exit 1
#       fi
#     fi
# }
#
# function clone {
#   git clone -o upstream git@github.com:ManageIQ/manageiq.git $DIR
# }
#
# function clone_cp {
#   echo "copy manageiq.git to $DIR"
#   cp -a manageiq.git $DIR
# }
#
# function filter_branch {
#   echo "removing tags"
#   git tag -d `git tag`
#
#   echo "extracting $EXTRACT_DIRS"
#   export EXTRACT_DIRS
#   time git filter-branch --index-filter '
#   git read-tree --empty
#   git reset $GIT_COMMIT -- $EXTRACT_DIRS
# ' --msg-filter '
#   cat -
#   echo
#   echo
#   echo "(transferred from ManageIQ/manageiq@$GIT_COMMIT)"
# ' -- --all -- $EXTRACT_DIRS
# }
#
# DIR="`pwd`/manageiq-providers-$NAME"
#
# set -x
#
# if [ ! -z $EXTRACT_BRANCH ] ; then
#   echo "extracting branch"
#   cd $EXTRACT_BRANCH
#   extract_branch
#   cd -
# fi
#
# echo "Target dir is $DIR"
#
# if [ ! -z $CLONE ] ; then
#    echo "clone"
#    check_dir
#    clone
# fi
#
# if [ ! -z $COPY_FROM ] ; then
#    echo "copy"
#    check_dir
#    clone_cp
# fi
#
# if [ ! -z $REWRITE ] ; then
#   echo "rewrite"
#   cd $DIR
#   filter_branch
#   cd -
# fi
#
# if [ ! -z $GENERATOR ] ; then
#   echo "run generator"
#   cd $GENERATOR
#   git checkout provider_generator
#   bundle exec rails g provider $NAME --path `dirname $DIR`
#   if [ ! -z $GEMFILE_URL ] ; then
#     branch="extract_$NAME"
#     git checkout $branch
# #    ruby -pi -e "gsub 'ManageIQ/manageiq-providers-$NAME', '$GEMFILE_URL/manageiq-providers-$NAME'" Gemfile
#     git commit -a -m 'point to provider gem'
#   fi
#   cd $DIR
#   git add .
#   git commit -m "rails g provider $NAME"
#   cd -
# fi
#
#
# if [ ! -z $PUSH ] ; then
#   cd $DIR
#   git remote remove origin || true
# #  git remote add origin git@github.com:${PUSH}/manageiq-providers-${NAME}.git
#   git remote add origin git@github.com:juliancheal/manageiq-providers-${NAME}.git
#   git fetch origin
#   git branch master --set-upstream-to=origin/master || true
#   OVERRIDE=true git push -f origin
#   cd -
# fi
