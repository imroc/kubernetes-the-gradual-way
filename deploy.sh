#! /bin/bash

set -eux

git add .
msg="rebuilding site `date`"
if [ $# -eq 1  ]
    then msg="$1"
fi
git commit -m "$msg"

gitbook build .

git checkout gh-pages
rm -rf `ls | egrep -v _book`
mv _book/* ./
rm -rf _book

git add .
git commit -m "$msg"
git push

git checkout master
