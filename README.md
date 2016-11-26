# Deploy the app

## Prerequisites

- access to the AWS console
- AWS credentials (access_key and secret_access_key) with enough rights to create an EC2 instance
- an EC2 key pair
- ruby and bundler to run the scripts
- git

### 1. Configure a new security group

Screenshot

- port 2375 for docker set to my ip
- port 22 for ssh (not really needed)
- port 80 HTTP

Note the security group ID

### 2. Provision a new server

To provision a new server for the app, first configure it

- run bundle install

Config:

- `REGION` (default `eu-west-1`), possible values http://docs.aws.amazon.com/general/latest/gr/rande.html#ec2_region
- `ACCESS_KEY` required  
- `SECRET_ACCESS_KEY` required
- `KEY_NAME` required
- `INSTANCE_TYPE` (default `t1.micro`), possible values https://aws.amazon.com/ec2/instance-types/
- `INSTANCE_NAME` (default `test-robin`), name of the instance
- `MYSQL_PASSWORD` password of the mysql root user
- `SECURITY_GROUP` security group id

- run `ruby spawn_server.rb`

Example:

````bash
ACCESS_KEY="SETME" \
SECRET_ACCESS_KEY="SETME" \
KEY_NAME="SETME" \
MYSQL_PASSWORD="some_passwords" \
SECURITY_GROUP="SETME" \
ruby spawn_server.rb
````

Output:

````bash
Creating instance
Waiting for instance to boot ...
...
...
...
Instance test-robin (t1.micro) deployed:
Public dns: ec2-54-78-180-161.eu-west-1.compute.amazonaws.com
ssh core@ec2-54-78-180-161.eu-west-1.compute.amazonaws.com using key dcdget
mysql is running on port 3306. User: root password: some_passwords
````

### 3. Deploy the app

Config:

- `APP_VERSION` required, an integer, first time, must use 1
- `SECRET_KEY_BASE` (default `super_secret`) rails app secret key base
- `DOCKER_HOST` required, public dns of the previously deployed server
- `MYSQL_PASSWORD` required, password of the mysql root user (defined during server provisionning)
- `APP_ROOT_DIR` (default "../devops-test"), root directory of the app to deploy

Example:

````bash
APP_VERSION=1 \
DOCKER_HOST=ec2-54-74-235-87.eu-west-1.compute.amazonaws.com \
MYSQL_PASSWORD=some_passwords \
ruby deploy.rb
````

Output:

````bash
-----> Building app version 1
[docker build logs ...]
-----> Running database migrations
[rake db:create logs ...]
[rake db:migrate logs ...]
-----> Starting the app
[docker container start logs ...]
-----> Deploying nginx
[docker build logs ...]
[docker container start logs ...]
-----> App version 1 reachable at http://ec2-54-78-180-161.eu-west-1.compute.amazonaws.com
-----> To see app logs: ./vendor/docker -H tcp://ec2-54-78-180-161.eu-west-1.compute.amazonaws.com:2375 logs app_v1
-----> To run a command in the app environment: ./vendor/docker -H tcp://ec2-54-78-180-161.eu-west-1.compute.amazonaws.com:2375 run -it  -e MYSQL_PORT=3306 -e MYSQL_PASSWORD=some_passwords -e MYSQL_USER=root -e MYSQL_HOST=127.0.0.1 -e SECRET_KEY_BASE=super_secret app:v1 <command>
-----> To deploy an update run: VERSION=N ruby deploy.rb
````

# Infrastructure

## How does it works ?

- spawn server .rb
- what does the script do
- coreos
- mysql

- deploy .rb
- app docker file
- nginx
- app

## Strength

- automatic provisionning / low dependencies
- fast deployment
- docker ==> really reproducible builds and processes
- scripted less prone to human error
- no ssh requirement (api based server management using docker), less user error prone
- haute dispo with automatic restart

## Weaknesses

- security, docker exposed (security group configuration), could be made secure
- no redundancy (bad for high availability)
- no monitoring
- downtime during deployment
- manual versionning


- TODO

- [ ] create a repo with this on Github
