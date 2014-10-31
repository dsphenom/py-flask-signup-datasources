REGION=$(shell /usr/bin/curl -s http://169.254.169.254/latest/dynamic/instance-identity/document/ | jq -r .region)
template:
	/usr/bin/ruby flask-signup-datasources.rb expand > flask-signup-datasources.template
validate:
	/usr/bin/aws cloudformation validate-template --template-body file://flask-signup-datasources.template --region ${REGION}
clean:
	rm -f flask-signup-datasources.template
