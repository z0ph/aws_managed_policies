#!/bin/bash

DATE=`date +%Y-%m-%d-%H-%M`
WORDTOREMOVE="policies/"

python3 --version

# job preparation (SSH + Git)
echo "Job preparation"
aws s3 cp s3://mamip-artifacts/mamip /tmp/mamip.key --region eu-west-1
chmod 600 /tmp/mamip.key
eval "$(ssh-agent -s)"
ssh-add /tmp/mamip.key
git config --global user.name "MAMIP Bot"
git config --global user.email mamip_bot@github.com
mkdir -p /root/.ssh/
ssh-keyscan github.com >> /root/.ssh/known_hosts

# run the magic
echo "Git Clone"
cd /app/
git clone git@github.com:z0ph/aws_managed_policies.git -q
if [ -d /app/aws_managed_policies ]
then
    cd /app/aws_managed_policies
    echo "Run the magic"
    aws iam list-policies > /app/aws_managed_policies/list-policies.json
    cat /app/aws_managed_policies/list-policies.json | jq -cr '.Policies[] | select(.Arn | contains("iam::aws"))|.Arn +" "+ .DefaultVersionId+" "+.PolicyName' | xargs -n3 sh -c 'aws iam get-policy-version --policy-arn $1 --version-id $2 > "policies/$3"' sh
    # push the changes if any
    if [[ -n $(git status -s) ]];
    then
        python3 /app/validate.py
        echo "Tagging"
        git tag $DATE
        git push --tags
        echo "Push the changes to master"
        # Prepare the Tweet
        diff="$(git diff --name-only) $(git ls-files --others --exclude-standard)"
        diff=${diff//$WORDTOREMOVE/}
        diff="${diff:0:200}..."
        git add ./policies
        git commit -am "Update detected"
        # Craft commit ID for tweet direct URL
        commit_id=$(git log --format="%h" -n 1)
        # Send message to qTweeter for publishing the tweet
        echo "aws sqs send-message --queue-url https://sqs.eu-west-1.amazonaws.com/567589703415/qtweet-mamip-sqs-queue.fifo --message-body "$diff https://github.com/z0ph/aws_managed_policies/commit/$commit_id" --message-group-id 1"
        # push to mamip repository
        git push origin master
    else
        echo "No changes detected"
        python3 /app/validate.py
    fi
fi