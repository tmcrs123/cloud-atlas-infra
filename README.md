## Keys
1. Generate RSA keys:
    ```sh
    openssl genrsa -out ./keys/private_${ENVIRONMENT}_key.pem 2048
    openssl rsa -pubout -in ./keys/private_${ENVIRONMENT}_key.pem -out ./keys/public_${ENVIRONMENT}_key.pem
    aws secretsmanager put-secret-value --secret-id cloud-atlas-${ENVIRONMENT}-cloudfront-private-key --secret-string file://./keys/private_${ENVIRONMENT}_key.pem --version-stages AWSCURRENT
    ```

## Deployment steps

1. Create the RSA keys using the command above.
2. Make sure you are in the terraform workspace for the environment you want to deploy:
    - `terraform workspace list`
    - `terraform workspace select <workspace_name>`
3. Update the `variables.tf` file with the public CloudFront key.
4. Ensure the private variables in `terraform.tfvars` are correct.
    - If in PROD, remove the local callback URL.
5. Deploy the Lambda API (the function must exist before running `terraform apply`; it will be deleted later).
6. Run the main Terraform file:
    - `terraform apply`
7. Go to Azure and create a FREE SQL database in the deployment group.
    - Allow IP range: 0.0.0.0 to 255.255.255.255.
8. Update the `app.settings` file with:
    - The database connection string.
    - The correct CloudFront keys.
9. Run the migrations.
10. Delete the temporary Lambda and redeploy with correct roles.
11. Update the allowed redirect URLs for the Cognito client (now that you know the CloudFront distribution URL).
12. Update the relevant IDs in the UI config.
13. Double-check keys in the Google Maps Dev Portal and allowed URLs.
14. Deploy the UI.
15. Run invalidation in CloudFront.
16. Check the certificates in Route 53.