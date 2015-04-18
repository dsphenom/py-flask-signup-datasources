#!/usr/bin/env ruby

require 'bundler/setup'
require 'cloudformation-ruby-dsl/cfntemplate'
require 'cloudformation-ruby-dsl/spotprice'
require 'cloudformation-ruby-dsl/table'

template do

  value :AWSTemplateFormatVersion => '2010-09-09'

  value :Description => 'New Startup SignUp Persistent Data Stores: RDBMs (MySQL), Custom Resource with Liquibase, SQS queue and SNS topic.'

  mapping 'AWSRegionAmznLinuxAMI',
          :'eu-central-1' => { :hvm => 'ami-04003319', :pvm => 'ami-0600331b' },
          :'eu-west-1' => { :hvm => 'ami-892fe1fe', :pvm => 'ami-d02386a7' },
          :'sa-east-1' => { :hvm => 'ami-c9e649d4', :pvm => 'ami-e1f15bfc' },
          :'us-east-1' => { :hvm => 'ami-76817c1e', :pvm => 'ami-904be6f8' },
          :'ap-northeast-1' => { :hvm => 'ami-29dc9228', :pvm => 'ami-c9466bc8' },
          :'us-west-2' => { :hvm => 'ami-d13845e1', :pvm => 'ami-d38dcce3' },
          :'us-west-1' => { :hvm => 'ami-f0d3d4b5', :pvm => 'ami-09626b4c' },
          :'ap-southeast-1' => { :hvm => 'ami-a6b6eaf4', :pvm => 'ami-c2604490' },
          :'ap-southeast-2' => { :hvm => 'ami-d9fe9be3', :pvm => 'ami-a7c8a89d' }

  parameter 'KeyName',
            :Description => 'Name of an existing EC2 KeyPair to allow SSH access',
            :Type => 'AWS::EC2::KeyPair::KeyName'

  parameter 'VpcId',
            :Description => 'VPC to deploy RDBMs instance to',
            :Type => 'AWS::EC2::VPC::Id'

  parameter 'RdbmsSubnet',
            :Description => 'VPC subnet to deploy RDBMs instance',
            :Type => 'AWS::EC2::Subnet::Id'

  parameter 'RdbmsInstanceType',
            :Description => 'Relational database instance type',
            :Type => 'String',
            :Default => 't2.micro',
            :AllowedValues => [
                't2.micro',
                't2.small',
                't2.medium',
                'm3.medium',
                'm3.large',
                'm3.xlarge',
                'm3.2xlarge',
                'c4.large',
                'c4.xlarge',
                'c4.2xlarge',
                'c4.4xlarge',
                'c4.8xlarge',
                'c3.large',
                'c3.xlarge',
                'c3.2xlarge',
                'c3.4xlarge',
                'c3.8xlarge',
                'r3.large',
                'r3.xlarge',
                'r3.2xlarge',
                'r3.4xlarge',
                'r3.8xlarge',
                'i2.xlarge',
                'i2.2xlarge',
                'i2.4xlarge',
                'i2.8xlarge',
            ],
            :ConstraintDescription => 'must be a valid EC2 instance type.'

  parameter 'DbUser',
            :Description => 'The database admin account username',
            :Type => 'String',
            :Default => 'dbuser',
            :MinLength => '1',
            :MaxLength => '16',
            :AllowedPattern => '[a-zA-Z][a-zA-Z0-9]*',
            :ConstraintDescription => 'must begin with a letter and contain only alphanumeric characters.'

  parameter 'DbPassword',
            :Description => 'The database admin account password',
            :Type => 'String',
            :Default => 'dbpassword',
            :NoEcho => 'true',
            :MinLength => '1',
            :MaxLength => '41'

  parameter 'DbName',
            :Description => 'Name of database',
            :Type => 'String',
            :Default => 'userdb',
            :MinLength => '1',
            :MaxLength => '64',
            :AllowedPattern => '[a-zA-Z0-9]*',
            :ConstraintDescription => 'must be 1-64 alphanumeric characters'

  resource 'LiquibaseCustomResourceQueue', :Type => 'AWS::SQS::Queue', :Properties => { :ReceiveMessageWaitTimeSeconds => '20', :VisibilityTimeout => '30' }

  resource 'LiquibaseCustomResourceTopic', :Type => 'AWS::SNS::Topic', :Properties => {
      :Subscription => [
          {
              :Endpoint => get_att('LiquibaseCustomResourceQueue', 'Arn'),
              :Protocol => 'sqs',
          },
      ],
  }

  resource 'LiquibaseCustomResourceQueuePolicy', :Type => 'AWS::SQS::QueuePolicy', :Properties => {
      :Queues => [ ref('LiquibaseCustomResourceQueue') ],
      :PolicyDocument => {
          :Version => '2008-10-17',
          :Id => join('/', get_att('LiquibaseCustomResourceQueue', 'Arn'), 'LiquibaseCustomResourceQueuePolicy'),
          :Statement => [
              {
                  :Sid => 'AllowTopicToPublishMessages',
                  :Effect => 'Allow',
                  :Principal => { :AWS => '*' },
                  :Action => [ 'sqs:SendMessage' ],
                  :Resource => get_att('LiquibaseCustomResourceQueue', 'Arn'),
                  :Condition => {
                      :ArnEquals => { :'aws:SourceArn' => ref('LiquibaseCustomResourceTopic') },
                  },
              },
          ],
      },
  }

  resource 'FlaskSignupDatastoreRole', :Type => 'AWS::IAM::Role', :Properties => {
      :AssumeRolePolicyDocument => {
          :Version => '2008-10-17',
          :Statement => [
              {
                  :Effect => 'Allow',
                  :Principal => { :Service => [ 'ec2.amazonaws.com' ] },
                  :Action => [ 'sts:AssumeRole' ],
              },
          ],
      },
      :Path => '/',
      :Policies => [
          {
              :PolicyName => 'FlaskSignup-DatastoreAccess',
              :PolicyDocument => {
                  :Statement => [
                      {
                          :Effect => 'Allow',
                          :Action => [ 'sqs:ChangeMessageVisibility', 'sqs:DeleteMessage', 'sqs:ReceiveMessage' ],
                          :Resource => get_att('LiquibaseCustomResourceQueue', 'Arn'),
                      },
                      {
                          :Effect => 'Allow',
                          :Action => [ 'sns:Publish' ],
                          :Resource => ref('FlaskSignupTopic'),
                      },
                  ],
              },
          },
      ],
  }

  resource 'FlaskSignupDatastoreInstanceProfile', :Type => 'AWS::IAM::InstanceProfile', :Properties => {
      :Path => '/',
      :Roles => [ ref('FlaskSignupDatastoreRole') ],
  }

  resource 'RdbmsInstance', :Type => 'AWS::EC2::Instance', :Metadata => { :'AWS::CloudFormation::Init' => { :configSets => { :datastore => [ 'db', 'runner' ] }, :db => { :packages => { :yum => { :mysql => [], :'mysql-server' => [], :'mysql-libs' => [] } }, :files => { :'/tmp/setup.mysql' => { :content => join('', "DELETE FROM mysql.user WHERE User='';\n", "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');\n", "DROP DATABASE test;\n", "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';\n", 'CREATE DATABASE ', ref('DbName'), ";\n", 'GRANT ALL ON ', ref('DbName'), '.* TO \'', ref('DbUser'), '\'@\'%\' IDENTIFIED BY \'', ref('DbPassword'), "';\n", "FLUSH PRIVILEGES;\n"), :mode => '000644', :owner => 'root', :group => 'root' } }, :services => { :sysvinit => { :mysqld => { :enabled => 'true', :ensureRunning => 'true' } } } }, :runner => { :packages => { :rpm => { :'aws-cfn-resource-bridge' => 'http://s3.amazonaws.com/cloudformation-examples/aws-cfn-resource-bridge-0.1-4.noarch.rpm' }, :yum => { :'mysql-connector-java' => [] } }, :files => { :'/etc/cfn/bridge.d/schema.conf' => { :content => join('', "[schema]\n", "resource_type=Custom::DatabaseSchema\n", "flatten=false\n", 'queue_url=', ref('LiquibaseCustomResourceQueue'), "\n", "timeout=600\n", "default_action=/home/ec2-user/liquify.py\n") }, :'/home/ec2-user/liquify.py' => { :source => 'https://raw.github.com/awslabs/aws-cfn-custom-resource-examples/master/examples/schema/impl/liquify.py', :mode => '000755', :owner => 'ec2-user' }, :'/home/ec2-user/liquibase/lib/mysql-connector-java-bin.jar' => { :content => '/usr/share/java/mysql-connector-java.jar', :mode => '120644' }, :'/home/ec2-user/users.csv' => { :source => 'http://awsinfo.me.s3.amazonaws.com/services/cloudformation/scripts/users.csv', :mode => '000644', :owner => 'ec2-user' }, :'/home/ec2-user/blogs.csv' => { :source => 'http://awsinfo.me.s3.amazonaws.com/services/cloudformation/scripts/blogs.csv', :mode => '000644', :owner => 'ec2-user' } }, :sources => { :'/home/ec2-user/liquibase' => 'http://s3.amazonaws.com/cloudformation-examples/liquibase-3.0.5-bin.zip' }, :services => { :sysvinit => { :'cfn-resource-bridge' => { :enabled => 'true', :ensureRunning => 'true', :files => [ '/etc/cfn/bridge.d/schema.conf', '/home/ec2-user/liquify.py' ] } } } } } }, :Properties => {
      :IamInstanceProfile => ref('FlaskSignupDatastoreInstanceProfile'),
      :ImageId => find_in_map('AWSRegionAmznLinuxAMI', ref('AWS::Region'), 'hvm'),
      :KeyName => ref('KeyName'),
      :InstanceType => ref('RdbmsInstanceType'),
      :SecurityGroupIds => [ ref('RdbmsSecurityGroup') ],
      :SubnetId => ref('RdbmsSubnet'),
      :Tags => [
          { :Key => 'Name', :Value => 'MySQL Server' },
      ],
      :UserData => base64(
          join('',
               "#!/bin/bash -x\n",
               "exec &> /home/ec2-user/userdata.log\n",
               "yum update -y aws-cfn-bootstrap\n",
               "# Helper function\n",
               "function error_exit\n",
               "{\n",
               '  /opt/aws/bin/cfn-signal -e 1 -r "$1" \'',
               ref('RdbmsWaitConditionHandle'),
               "'\n",
               "  exit 1\n",
               "}\n",
               '/opt/aws/bin/cfn-init -s ',
               aws_stack_id,
               ' -r RdbmsInstance -c datastore',
               '    --region ',
               ref('AWS::Region'),
               " || error_exit 'Failed to run cfn-init'\n",
               "# Setup MySQL, create a user and a database\n",
               'mysqladmin -u root password \'',
               ref('DbPassword'),
               "' || error_exit 'Failed to initialize root password'\n",
               'mysql -u root --password=\'',
               ref('DbPassword'),
               "' < /tmp/setup.mysql || error_exit 'Failed to initialize database'\n",
               "# All is well so signal success\n",
               '/opt/aws/bin/cfn-signal -e 0 -r "Rdbms Server setup complete" \'',
               ref('RdbmsWaitConditionHandle'),
               "'\n",
          )
      ),
  }

  resource 'RdbmsSecurityGroup', :Type => 'AWS::EC2::SecurityGroup', :Properties => {
      :GroupDescription => 'Enable Rdbms access via port 3306',
      :VpcId => ref('VpcId'),
      :SecurityGroupIngress => [
          { :IpProtocol => 'tcp', :FromPort => '3306', :ToPort => '3306', :CidrIp => '0.0.0.0/0' },
          { :IpProtocol => 'tcp', :FromPort => '22', :ToPort => '22', :CidrIp => '0.0.0.0/0' },
      ],
  }

  resource 'RdbmsWaitConditionHandle', :Type => 'AWS::CloudFormation::WaitConditionHandle'

  resource 'RdbmsWaitCondition', :Type => 'AWS::CloudFormation::WaitCondition', :DependsOn => 'RdbmsInstance', :Properties => {
      :Count => '1',
      :Handle => ref('RdbmsWaitConditionHandle'),
      :Timeout => '600',
  }

  resource 'FlaskSignupQueue', :Type => 'AWS::SQS::Queue'

  resource 'FlaskSignupTopic', :Type => 'AWS::SNS::Topic', :Properties => {
      :Subscription => [
          { :Endpoint => 'awslab@mailinator.com', :Protocol => 'email' },
          {
              :Endpoint => get_att('FlaskSignupQueue', 'Arn'),
              :Protocol => 'sqs',
          },
      ],
  }

  resource 'FlaskSignUpSns2SqsPolicy', :Type => 'AWS::SQS::QueuePolicy', :Properties => {
      :Queues => [ ref('FlaskSignupQueue') ],
      :PolicyDocument => {
          :Id => join('/', get_att('FlaskSignupQueue', 'Arn'), 'FlaskSignUpSns2SqsPolicy'),
          :Version => '2008-10-17',
          :Statement => [
              {
                  :Condition => {
                      :ArnEquals => { :'aws:SourceArn' => ref('FlaskSignupTopic') },
                  },
                  :Resource => get_att('FlaskSignupQueue', 'Arn'),
                  :Principal => { :AWS => '*' },
                  :Action => [ 'sqs:SendMessage' ],
                  :Sid => 'Allow-SNS-SendMessage',
                  :Effect => 'Allow',
              },
          ],
      },
  }

  resource 'LiquibaseRunnerSecurityGroup', :Type => 'AWS::EC2::SecurityGroup', :Properties => { :GroupDescription => 'Access to Liquibase Custom Resource Runner instances' }

  change_log = JSON.parse(File.read('liquibase-changelog.json'))

  resource 'MySqlSchema', :Type => 'Custom::DatabaseSchema', :DependsOn => [ 'RdbmsInstance', 'LiquibaseCustomResourceQueue', 'LiquibaseCustomResourceTopic', 'LiquibaseCustomResourceQueuePolicy' ], :Version => '1.0', :Properties => {
      :ServiceToken => ref('LiquibaseCustomResourceTopic'),
      :DatabaseURL => join('', 'jdbc:mysql://', get_att('RdbmsInstance', 'PrivateDnsName'), ':3306', '/', ref('DbName')),
      :DatabaseUsername => ref('DbUser'),
      :DatabasePassword => ref('DbPassword'),
      :databaseChangeLog => change_log
  }

  output 'MySqlEndpoint',
         :Description => 'Relational database endpoint for the signup data store',
         :Value => get_att('RdbmsInstance', 'PrivateDnsName')

  output 'SignUpSnsTopic',
         :Description => 'SNS Topic ARN',
         :Value => ref('FlaskSignupTopic')

end.exec!
