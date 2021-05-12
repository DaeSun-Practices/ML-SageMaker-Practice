#!/bin/bash

# Convert DynamoDB export format to CSV for Machine Learning 
hive -e "
ADD jar s3://<your bucket name>/json-serde-1.3.6-SNAPSHOT-jar-with-dependencies.jar ; 
DROP TABLE IF EXISTS blog_backup_data ; 
CREATE EXTERNAL TABLE blog_backup_data (  
customer_id map<string,string>,
age  map<string,string>, job   map<string,string>,  marital  map<string,string>, 
education  map<string,string>, default  map<string,string>, housing map<string,string>,
loan  map<string,string>, contact  map<string,string>, month  map<string,string>,
day_of_week  map<string,string>, duration  map<string,string>, campaign  map<string,string>,
pdays   map<string,string>, previous  map<string,string>, poutcome  map<string,string>,
emp_var_rate   map<string,string>, cons_price_idx  map<string,string>, cons_conf_idx  map<string,string>,
euribor3m map<string,string>, nr_employed  map<string,string>, y  map<string,string>  ) 
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe'  
WITH SERDEPROPERTIES ('ignore.malformed.json' = 'true')
LOCATION '$1/'
;

INSERT OVERWRITE  DIRECTORY 's3://<your bucket name>/<datasource path>/' 
SELECT concat( y['n'],',',
               age['n'],',',  job['s'],',',           
               marital['s'],',', education['s'],',',  default['s'],',',      
               housing['s'],',', loan['s'],',', contact['s'],',',       
               month['s'],',', day_of_week['s'],',', duration['n'],',',      
               campaign['n'],',',pdays['n'],',',previous['n'],',',      
               poutcome['s'],',',  emp_var_rate['n'],',', cons_price_idx['n'],',',
               cons_conf_idx['n'],',', euribor3m['n'],',', nr_employed['n']  )           
FROM blog_backup_data
WHERE customer_id['s'] > 0  ; 
"
if [ $? -ne 0 ]; then 
  echo "Error while running Hive SQL, Location - $1 "
  exit 1 ; 
fi


# upgrade CLI for sagemaker 
pip install awscli --upgrade --user

## Define variable   
REGION="${2//[[:space:]]/}"
ROLE="<your AmazonSageMaker-ExecutionRole >" 
DTTIME=`date +%Y-%m-%d-%H-%M-%S` 
echo  $REGION


# Select  containers image for training and deploy 
case "$REGION" in
"us-west-2" )
    IMAGE="174872318107.dkr.ecr.us-west-2.amazonaws.com/linear-learner:latest"
    ;;
"us-east-1" )
    IMAGE="382416733822.dkr.ecr.us-east-1.amazonaws.com/linear-learner:latest" 
    ;;
"us-east-2" )
    IMAGE="404615174143.dkr.ecr.us-east-2.amazonaws.com/linear-learner:latest" 
    ;;
"eu-west-1" )
    IMAGE="438346466558.dkr.ecr.eu-west-1.amazonaws.com/linear-learner:latest" 
    ;;
 *)
    echo "Invalid Region Name or Amazon SageMaker is not supported in this region."
    exit 1 ;  
esac

  
# Training job and  model artifact 
TRAINING_JOB_NAME=TRAIN-${DTTIME} 
S3OUTPUT="s3://<your bucket name>/model/" 
INSTANCETYPE="ml.m4.xlarge"
INSTANCECOUNT=1
VOLUMESIZE=5 
aws sagemaker create-training-job --training-job-name ${TRAINING_JOB_NAME} --region ${REGION}  --algorithm-specification TrainingImage=${IMAGE},TrainingInputMode=File --role-arn ${ROLE}  --input-data-config '[{ "ChannelName": "train", "DataSource": { "S3DataSource": { "S3DataType": "S3Prefix", "S3Uri": "s3://<your bucket name>/<datasource path>/", "S3DataDistributionType": "FullyReplicated" } }, "ContentType": "text/csv", "CompressionType": "None" , "RecordWrapperType": "None"  }]'  --output-data-config S3OutputPath=${S3OUTPUT} --resource-config  InstanceType=${INSTANCETYPE},InstanceCount=${INSTANCECOUNT},VolumeSizeInGB=${VOLUMESIZE} --stopping-condition MaxRuntimeInSeconds=120 --hyper-parameters feature_dim=20,predictor_type=binary_classifier  

# wait until job completed 
aws sagemaker wait training-job-completed-or-stopped --training-job-name ${TRAINING_JOB_NAME}  --region ${REGION}

# create model
MODELARTIFACT=`aws sagemaker describe-training-job --training-job-name ${TRAINING_JOB_NAME} --region ${REGION}  --query 'ModelArtifacts.S3ModelArtifacts' --output text `
MODELNAME=MODEL-${DTTIME}
aws sagemaker create-model --region ${REGION} --model-name ${MODELNAME}  --primary-container Image=${IMAGE},ModelDataUrl=${MODELARTIFACT}  --execution-role-arn ${ROLE}


# create end point configuration 
CONFIGNAME=CONFIG-${DTTIME}
aws sagemaker  create-endpoint-config --region ${REGION} --endpoint-config-name ${CONFIGNAME}  --production-variants  VariantName=Users,ModelName=${MODELNAME},InitialInstanceCount=1,InstanceType=ml.m4.xlarge


# create end point 
STATUS=`aws sagemaker describe-endpoint --endpoint-name  ServiceEndpoint --query 'EndpointStatus' --output text --region ${REGION} `
if [[ $STATUS -ne "InService" ]] ;
then
    aws sagemaker  create-endpoint --endpoint-name  ServiceEndpoint  --endpoint-config-name ${CONFIGNAME} --region ${REGION}    
else
    aws sagemaker  update-endpoint --endpoint-name  ServiceEndpoint  --endpoint-config-name ${CONFIGNAME} --region ${REGION}
fi 