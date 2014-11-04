#!/usr/bin/env ruby

require 'bundler/setup'
require 'cloudformation-ruby-dsl/cfntemplate'
require 'cloudformation-ruby-dsl/spotprice'
require 'cloudformation-ruby-dsl/table'
require 'json'

template do

  value :AWSTemplateFormatVersion => '2010-09-09'

  value :Description => 'New Startup SignUp Persistent Data Stores: MySQL, Custom Resource with Liquibase, SQS queue and SNS topic.'

  mapping 'AWSRegionAmznLinuxAMI',
          :'eu-west-1' => { :hvm => 'ami-892fe1fe', :pvm => 'ami-d02386a7' },
          :'sa-east-1' => { :hvm => 'ami-c9e649d4', :pvm => 'ami-e1f15bfc' },
          :'us-east-1' => { :hvm => 'ami-76817c1e', :pvm => 'ami-904be6f8' },
          :'ap-northeast-1' => { :hvm => 'ami-29dc9228', :pvm => 'ami-c9466bc8' },
          :'us-west-2' => { :hvm => 'ami-d13845e1', :pvm => 'ami-d38dcce3' },
          :'us-west-1' => { :hvm => 'ami-f0d3d4b5', :pvm => 'ami-09626b4c' },
          :'ap-southeast-1' => { :hvm => 'ami-a6b6eaf4', :pvm => 'ami-c2604490' },
          :'ap-southeast-2' => { :hvm => 'ami-d9fe9be3', :pvm => 'ami-a7c8a89d' }

  parameter 'InstanceType',
            :Description => 'Custom resource runner instance type',
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
                'c2.large',
                'c2.xlarge',
                'c3.2xlarge',
                'c3.4xlarge',
                'c3.8xlarge',
            ],
            :ConstraintDescription => 'must be a valid EC2 instance type.'

  parameter 'MySqlInstanceType',
            :Description => 'MySQL Server instance type',
            :Type => 'String',
            :Default => 't2.small',
            :AllowedValues => [
                't2.micro',
                't2.small',
                't2.medium',
                'm3.medium',
                'm3.large',
                'm3.xlarge',
                'm3.2xlarge',
                'c2.large',
                'c2.xlarge',
                'c3.2xlarge',
                'c3.4xlarge',
                'c3.8xlarge',
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
                          :Action => [ 'sns:Publish' ],
                          :Resource => [ '*' ],
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

  resource 'LiquibaseRunnerRole', :Type => 'AWS::IAM::Role', :Properties => {
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
              :PolicyName => 'LiquibaseCustomResourceRunner',
              :PolicyDocument => {
                  :Statement => [
                      {
                          :Effect => 'Allow',
                          :Action => [ 'sqs:ChangeMessageVisibility', 'sqs:DeleteMessage', 'sqs:ReceiveMessage' ],
                          :Resource => get_att('LiquibaseCustomResourceQueue', 'Arn'),
                      },
                  ],
              },
          },
      ],
  }

  resource 'LiquibaseRunnerInstanceProfile', :Type => 'AWS::IAM::InstanceProfile', :Properties => {
      :Path => '/',
      :Roles => [ ref('LiquibaseRunnerRole') ],
  }

  resource 'LiquibaseRunnerLaunchConfig', :Type => 'AWS::AutoScaling::LaunchConfiguration', :Metadata => { :'AWS::CloudFormation::Init' => { :config => { :packages => { :rpm => { :'aws-cfn-resource-bridge' => 'http://s3.amazonaws.com/cloudformation-examples/aws-cfn-resource-bridge-0.1-4.noarch.rpm' }, :yum => { :'mysql-connector-java' => [] } }, :files => { :'/etc/cfn/bridge.d/schema.conf' => { :content => join('', "[schema]\n", "resource_type=Custom::DatabaseSchema\n", "flatten=false\n", 'queue_url=', ref('LiquibaseCustomResourceQueue'), "\n", "timeout=600\n", "default_action=/home/ec2-user/liquify.py\n") }, :'/home/ec2-user/liquify.py' => { :source => 'https://raw.github.com/awslabs/aws-cfn-custom-resource-examples/master/examples/schema/impl/liquify.py', :mode => '000755', :owner => 'ec2-user' }, :'/home/ec2-user/liquibase/lib/mysql-connector-java-bin.jar' => { :content => '/usr/share/java/mysql-connector-java.jar', :mode => '120644' }, :'/home/ec2-user/users.csv' => { :source => 'http://awsinfo.me.s3.amazonaws.com/services/cloudformation/scripts/users.csv', :mode => '000644', :owner => 'ec2-user' }, :'/home/ec2-user/blogs.csv' => { :source => 'http://awsinfo.me.s3.amazonaws.com/services/cloudformation/scripts/blogs.csv', :mode => '000644', :owner => 'ec2-user' } }, :sources => { :'/home/ec2-user/liquibase' => 'http://s3.amazonaws.com/cloudformation-examples/liquibase-3.0.5-bin.zip' }, :services => { :sysvinit => { :'cfn-resource-bridge' => { :enabled => 'true', :ensureRunning => 'true', :files => [ '/etc/cfn/bridge.d/schema.conf', '/home/ec2-user/liquify.py' ] } } } } } }, :Properties => {
      :IamInstanceProfile => ref('LiquibaseRunnerInstanceProfile'),
      :ImageId => find_in_map('AWSRegionAmznLinuxAMI', ref('AWS::Region'), 'hvm'),
      :InstanceType => ref('InstanceType'),
      :SecurityGroups => [ get_att('LiquibaseRunnerSecurityGroup', 'GroupId') ],
      :UserData => base64(
          join('',
               "#!/bin/bash -x\n",
               "exec &> /home/ec2-user/userdata.log\n",
               "yum update -y aws-cfn-bootstrap\n",
               '/opt/aws/bin/cfn-init --region ',
               ref('AWS::Region'),
               ' -s ',
               aws_stack_id,
               " -r LiquibaseRunnerLaunchConfig -v\n",
               '/opt/aws/bin/cfn-signal -e $? \'',
               ref('LiquibaseRunnerWaitConditionHandle'),
               "'\n",
          )
      ),
  }

  resource 'MySqlRdbms', :Type => 'AWS::EC2::Instance', :Metadata => { :'AWS::CloudFormation::Init' => { :config => { :packages => { :yum => { :mysql => [], :'mysql-server' => [], :'mysql-libs' => [] } }, :files => { :'/tmp/setup.mysql' => { :content => join('', "DELETE FROM mysql.user WHERE User='';\n", "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');\n", "DROP DATABASE test;\n", "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';\n", 'CREATE DATABASE ', ref('DbName'), ";\n", 'GRANT ALL ON ', ref('DbName'), '.* TO \'', ref('DbUser'), '\'@\'%\' IDENTIFIED BY \'', ref('DbPassword'), "';\n", "FLUSH PRIVILEGES;\n"), :mode => '000644', :owner => 'root', :group => 'root' } }, :services => { :sysvinit => { :mysqld => { :enabled => 'true', :ensureRunning => 'true' } } } } } },   :Properties => {
     :ImageId => find_in_map('AWSRegionAmznLinuxAMI', ref('AWS::Region'), 'hvm'),
     :InstanceType => ref('MySqlInstanceType'),
     :SecurityGroups => [ ref('MySqlSecurityGroup') ],
     :Tags => [
        {
            :Key => 'Name',
            :Value => 'MySQL Server',
        }
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
               ref('MySqlWaitConditionHandle'),
               "'\n",
               "  exit 1\n",
               "}\n",
               '/opt/aws/bin/cfn-init -s ',
               aws_stack_id,
               ' -r MySqlRdbms ',
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
               '/opt/aws/bin/cfn-signal -e 0 -r "MySQL Server setup complete" \'',
               ref('MySqlWaitConditionHandle'),
               "'\n",
          )
      ),
  }

  resource 'MySqlSecurityGroup', :Type => 'AWS::EC2::SecurityGroup', :Properties => {
      :GroupDescription => 'Enable MySQL access via port 3306',
      :SecurityGroupIngress => [
          { :IpProtocol => 'tcp', :FromPort => '3306', :ToPort => '3306', :CidrIp => '172.31.0.0/16' },
      ],
  }

  resource 'MySqlWaitConditionHandle', :Type => 'AWS::CloudFormation::WaitConditionHandle'
    
  resource 'MySqlWaitCondition', :Type => 'AWS::CloudFormation::WaitCondition', :DependsOn => 'MySqlRdbms', :Properties => {
      :Count => '1',
      :Handle => ref('MySqlWaitConditionHandle'),
      :Timeout => '600',
  }

  resource 'NewSignupQueue', :Type => 'AWS::SQS::Queue'

  resource 'NewSignupTopic', :Type => 'AWS::SNS::Topic', :Properties => {
      :Subscription => [
          { :Endpoint => 'nobody@amazon.com', :Protocol => 'email' },
          {
              :Endpoint => get_att('NewSignupQueue', 'Arn'),
              :Protocol => 'sqs',
          },
      ],
  }

  resource 'NewSignUpSns2SqsPolicy', :Type => 'AWS::SQS::QueuePolicy', :Properties => {
      :Queues => [ ref('NewSignupQueue') ],
      :PolicyDocument => {
          :Id => join('/', get_att('NewSignupQueue', 'Arn'), 'NewSignUpSns2SqsPolicy'),
          :Version => '2008-10-17',
          :Statement => [
              {
                  :Condition => {
                      :ArnEquals => { :'aws:SourceArn' => ref('NewSignupTopic') },
                  },
                  :Resource => get_att('NewSignupQueue', 'Arn'),
                  :Principal => { :AWS => '*' },
                  :Action => [ 'sqs:SendMessage' ],
                  :Sid => 'Allow-SNS-SendMessage',
                  :Effect => 'Allow',
              },
          ],
      },
  }

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

  resource 'LiquibaseRunnerAutoScalingGroup', :Type => 'AWS::AutoScaling::AutoScalingGroup', :UpdatePolicy => { :AutoScalingRollingUpdate => { :MinInstancesInService => '0', :MaxBatchSize => '1', :PauseTime => 'PT0S' } }, :Properties => {
      :AvailabilityZones => get_azs,
      :LaunchConfigurationName => ref('LiquibaseRunnerLaunchConfig'),
      :MinSize => '1',
      :MaxSize => '1',
      :Tags => [
          {
              :Key => 'Name',
              :Value => 'Custom Resource Runner - Liquibase',
              :PropagateAtLaunch => true,
          },
      ],
  }

  resource 'LiquibaseRunnerSecurityGroup', :Type => 'AWS::EC2::SecurityGroup', :Properties => { :GroupDescription => 'Access to Liquibase Custom Resource Runner instances' }

  resource 'LiquibaseRunnerSecurityGroupIngress', :Type => 'AWS::EC2::SecurityGroupIngress', :Properties => {
      :IpProtocol => 'tcp',
      :FromPort => '22',
      :ToPort => '22',
      :SourceSecurityGroupId => get_att('LiquibaseRunnerSecurityGroup', 'GroupId'),
      :GroupId => get_att('LiquibaseRunnerSecurityGroup', 'GroupId'),
  }

  resource 'LiquibaseRunnerWaitConditionHandle', :Type => 'AWS::CloudFormation::WaitConditionHandle'

  resource 'LiquibaseRunnerWaitCondition', :Type => 'AWS::CloudFormation::WaitCondition', :DependsOn => 'LiquibaseRunnerAutoScalingGroup', :Properties => {
      :Count => '1',
      :Handle => ref('LiquibaseRunnerWaitConditionHandle'),
      :Timeout => '600',
  }

  change_log = JSON.parse(File.read('liquibase-changelog.json'))

  resource 'MySqlSchema', :Type => 'Custom::DatabaseSchema', :DependsOn => [ 'LiquibaseRunnerAutoScalingGroup', 'MySqlRdbms', 'LiquibaseCustomResourceQueue', 'LiquibaseCustomResourceTopic', 'LiquibaseCustomResourceQueuePolicy' ], :Version => '1.0', :Properties => {
      :ServiceToken => ref('LiquibaseCustomResourceTopic'),
      :DatabaseURL => join('',
           'jdbc:mysql://',
           get_att('MySqlRdbms', 'PublicDnsName'),
           ':3306',
           '/',
           ref('DbName'),
      ),
      :DatabaseUsername => ref('DbUser'),
      :DatabasePassword => ref('DbPassword'),
      :databaseChangeLog => change_log
  }

  output 'MySqlEndpoint',
         :Description => 'Relational database endpoint for the signup data store',
         :Value => get_att('MySqlRdbms', 'PublicDnsName')

  output 'SignUpSnsTopic',
         :Description => 'SNS Topic ARN',
         :Value => ref('NewSignupTopic')

end.exec!
