# py-flask-signup-datasources

Uses a CloudFormation Ruby DSL, [cloudformation-ruby-dsl](https://github.com/bazaarvoice/cloudformation-ruby-dsl), to build an AWS CloudFormation template to deploy the data sources, including MySQL server, SNS, SQS and Liquibase required for Python Flask Startup Signup application

## Usage
To build a template run:

	make template

This will create a JSON CloudFormation template flask-signup-datasources.template

To validate a template run:

	make validate

This will run the AWS CLI cloudformation validate-template action on the flask-signup-datasource.template file using the CloudFormation API of the local region

To clean up:

	make clean

