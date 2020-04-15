#!/bin/bash

function printOk {
  printf "%-48s$(tput setaf 2)[ OK ]$(tput sgr 0)\n" "$1"
}
function printOkWithVal {
  printf "%-23s%24s $(tput setaf 2)[ OK ]$(tput sgr 0)\n" "$1" "$2"
}
function printFail {
  echo
  echo "$(tput setaf 1)ERROR: $1$(tput sgr 0)"
  echo "Exiting..."
}


if [[ $_ != $0 ]]; then
  printFail "Run directly. Do not source."
  return
fi
printOk "Shell check"


GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
if [[ ${GIT_BRANCH} != "master" ]]; then
  printFail "Must be on master branch."
  exit 1
fi
printOkWithVal "Git branch" ${GIT_BRANCH}


BUNDLE_PATH_ACTUAL=$(which bundle)
BUNDLE_PATH_GOLD="/usr/local/opt/ruby/bin/bundle"
if [[ ${BUNDLE_PATH_ACTUAL} != ${BUNDLE_PATH_GOLD} ]]; then
  printFail "Bundle path ${BUNDLE_PATH_ACTUAL} is different from ${BUNDLE_PATH_GOLD}"
  exit 1
fi
printOk "bundle in path"

# Check aws is present or not

AWS_VERSION_ACTUAL=$(aws --version)
AWS_VERSION_GOLD="aws-cli/1.16.246 Python/3.7.4 Darwin/19.4.0 botocore/1.12.236"
if [[ ${AWS_VERSION_ACTUAL} != ${AWS_VERSION_GOLD} ]]; then
  printFail "aws version ${AWS_VERSION_ACTUAL} is different from ${AWS_VERSION_GOLD}"
  exit 1
fi
printOk "aws version"

echo
echo "$(tput setaf 2)▒▒▒▒ All checks passsed ▒▒▒▒$(tput sgr 0)"
echo
echo "$(tput setaf 3)▒▒▒▒ Starting Jekyll build ▒▒▒▒$(tput sgr 0)"
echo

bundle exec jekyll build

if [[ $? -ne 0 ]]; then
  echo "$(tput setaf 1)▒▒▒▒ BUILD FAILED ▒▒▒▒$(tput sgr 0)"
  exit 1
fi
echo "$(tput setaf 2)▒▒▒▒ BUILD SUCCESSFUL ▒▒▒▒$(tput sgr 0)"
echo

# Normally we would just upload the _site folder to s3.
# But we don't do that because the .html file extension show up in URLs
# if we do so. And there is no way to tell cloudfront to map /foo to /foo.html
# without involving lambda functions.

# So we upload non-html and html files separately. html files are first
# stripped off their extension and then uploaded to s3.

echo "$(tput setaf 3)Copying files to _site_aws$(tput sgr 0)"
\rm -rf _site_aws
\cp -R _site/ _site_aws/

echo "$(tput setaf 3)▒▒▒▒ Creating a backup named _site_backup on S3 ▒▒▒▒$(tput sgr 0)"
aws s3 mv --recursive s3://root.saptarshibiswas.com/_site s3://root.saptarshibiswas.com/_site_backup
echo "$(tput setaf 2)▒▒▒▒ Backed up ▒▒▒▒$(tput sgr 0)"
echo

echo "$(tput setaf 3)▒▒▒▒ Uploading non html files to S3 ▒▒▒▒$(tput sgr 0)"
aws s3 sync _site_aws s3://root.saptarshibiswas.com/_site \
  --exclude "*.html" \
  --cache-control 'max-age=604800'
echo "$(tput setaf 2)▒▒▒▒ Non-html files successfully uploaded to S3 ▒▒▒▒$(tput sgr 0)"
echo

echo "$(tput setaf 3)Removing non-html files$(tput sgr 0)"
\find _site_aws -type f -not -name '*.html' -delete
\find _site_aws -name '*.html' -exec sh -c 'mv "$1" "${1%.html}"' sh {} \;
echo

echo "$(tput setaf 3)▒▒▒▒ Uploading html files to S3 ▒▒▒▒$(tput sgr 0)"
aws s3 cp _site_aws s3://root.saptarshibiswas.com/_site --recursive --content-type 'text/html'
echo "$(tput setaf 2)▒▒▒▒ Html files successfully uploaded to S3 ▒▒▒▒$(tput sgr 0)"
echo

echo "$(tput setaf 3)▒▒▒▒ Invalidating Cloudfront ▒▒▒▒$(tput sgr 0)"
# aws cloudfront create-invalidation --distribution-id E2R4LMWTMYG1FI --paths '/*'
echo "$(tput setaf 2)▒▒▒▒ Successfully invalidated Cloudfront ▒▒▒▒$(tput sgr 0)"
echo
