# Deployment

1 - Deploy API as lambda function


<!-- az login --tenant 8baba655-ea55-43cb-b947-c46c036cbdeb -->

## Keys
openssl genrsa -out ./keys/private_${ENVIRONMENT}_key.pem 2048
openssl rsa -pubout -in ./keys/private_${ENVIRONMENT}_key.pem -out ./keys/public_${ENVIRONMENT}_key.pem
aws secretsmanager put-secret-value --secret-id cloud-atlas-${ENVIRONMENT}-cloudfront-private-key --secret-string file://./keys/private_${ENVIRONMENT}_key.pem --version-stages AWSCURRENT