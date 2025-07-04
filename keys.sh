openssl genrsa -out ./keys/private_${ENVIRONMENT}_key.pem 2048
openssl rsa -pubout -in ./keys/private_${ENVIRONMENT}_key.pem -out ./keys/public_${ENVIRONMENT}_key.pem
