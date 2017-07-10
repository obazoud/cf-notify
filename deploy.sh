#!/usr/bin/env bash
set -x

test $(which pwgen)
if [ $? != "0" ]; then
    echo -e "pwgen not found. Please install using 'sudo apt-get install pwgen' (GNU/Linux) or 'brew install pwgen' (OSX)"
    exit 1
fi

if [ $# -lt 1 ]
then
    echo "usage: $0 <CHANNEL> <WEBHOOK> <AWS_PROFILE> <REGION> <BUCKET_SUFFIX>"
    exit 1
fi

CHANNEL=$1
WEBHOOK=$2
PROFILE=$3
REGION=$4
BUCKET_SUFFIX=$5

if [ -z $CHANNEL ];
then
    echo "Please specify a Slack Channel e.g #general or @me";
    exit 1
fi

if [ -z $WEBHOOK ];
then
    echo "Please specify a Slack WebHook";
    exit 1
fi

if [ -z $PROFILE ];
then
    PROFILE="default"
fi

if [[ $(aws configure --profile $PROFILE list) && $? -ne 0 ]];
then
    exit 1
fi

if [ -z $REGION ];
then
    echo "Please specify a AWS region";
    exit 1
fi

if [ -z $BUCKET_SUFFIX ];
then
    BUCKET_SUFFIX="cf-notify-`pwgen -1 --no-capitalize 5`"
fi

if [ ${CHANNEL:0:1} != '#' ] && [ ${CHANNEL:0:1} != '@' ];
then
    echo ${CHANNEL:0:1}
    echo 'Invalid Channel. Slack channels begin with # or @'
    exit 1
fi

CHANNEL_NAME=`echo ${CHANNEL:1} | tr '[:upper:]' '[:lower:]'`

echo 'Creating bucket'
BUCKET="$BUCKET_SUFFIX-$REGION"
echo $BUCKET
aws s3 mb "s3://$BUCKET" --profile $PROFILE --region $REGION
echo "Bucket $BUCKET created"

echo 'Creating lambda zip artifact'

if [ ! -f slack.py ]; then
    cat > slack.py <<EOL
WEBHOOK='$WEBHOOK'
CHANNEL='$CHANNEL'
CUSTOM_CHANNELS={}
EOL
fi

zip cf-notify.zip lambda_notify.py slack.py
echo 'Lambda artifact created'


echo 'Moving lambda artifact to S3'
aws s3 cp cf-notify.zip s3://$BUCKET/cf-notify.zip --profile $PROFILE --region $REGION

rm cf-notify.zip
echo 'Lambda artifact moved'

echo 'Creating stack'
aws cloudformation create-stack \
    --template-body file://cf-notify.json \
    --stack-name cf-notify-$REGION \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=Bucket,ParameterValue=$BUCKET \
    --profile $PROFILE \
    --region $REGION

if [[ $? != 0 ]];
then
    exit 1
else
    echo 'Stack created'
fi
