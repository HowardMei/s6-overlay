./getupstream.sh
set -x
git checkout develop && git rebase -Xours upstream || exit 1
##git checkout master && git rebase develop || exit 1
set +x
echo "Please edit in develop branch and rebase master upon new develop updates"
##echo "git push --all origin -u  to push all changes to remote"
