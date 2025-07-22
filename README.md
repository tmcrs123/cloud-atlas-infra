# Deployment

1 - Deploy API as lambda function


<!-- az login --tenant 8baba655-ea55-43cb-b947-c46c036cbdeb -->

## Keys
openssl genrsa -out ./keys/private_${ENVIRONMENT}_key.pem 2048
openssl rsa -pubout -in ./keys/private_${ENVIRONMENT}_key.pem -out ./keys/public_${ENVIRONMENT}_key.pem
aws secretsmanager put-secret-value --secret-id cloud-atlas-${ENVIRONMENT}-cloudfront-private-key --secret-string file://./keys/private_${ENVIRONMENT}_key.pem --version-stages AWSCURRENT

## Deployment steps

Create the RSA keys using the command above
make sure you are in the terraform workspace for the environment you want to deploy - `terraform workspace list / terraform workspace select <workspace_name>`
update the `variables.tf` file the public cloudfront key. Make sure the private variables in `terraform.tfvars` are correct. If in PROD remove the local callback url
run main.tf - `terraform apply`
Go to Azure and create a FREE sql database in the deployment group. Don't forget to allow 0.0.0.0 to 255.255.255.255
Update the app.settings file with the connection string for the database and the correct cloudfront keys
deploy the lambda API
run the migrations
update the allowed redirect urls for the cognito client now that you know the cloudfront dist url
double check keys in google maps dev portal and allowed urls
update the relevant IDS in the UI config
deploy the UI
run invalidation in cloudfront

<!-- openssl genrsa -out ./keys/private_demo_key.pem 2048
openssl rsa -pubout -in ./keys/private_demo_key.pem -out ./keys/public_demo_key.pem -->