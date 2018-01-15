#! /bin/bash

set -eux

git pull --rebase
gitbook build .
git checkout gh-pages
rm -rf `ls | egrep -v _book`
mv _book/* ./
rm -rf _book
msg="rebuilding site `date`"
git add .
git commit -m "$msg"
git push
git checkout master
