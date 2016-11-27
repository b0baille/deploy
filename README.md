# Deploy an app

This guide propose an automated procedure to deploy a ruby app backed by a MySql database behind an Nginx server on a single EC2 instance.

## 0. Prerequisites

To go through this guide, you need:

- an access to the [AWS console](https://console.aws.amazon.com/console/home)
- AWS access key and secret access key with enough rights to create EC2 instances
- an EC2 key pair
- ruby, bundler and git installed on your machine
- this guide assumes it's run on Mac OSX (a Mac OSX docker binary is provided into this repository)

## 1. Configure a security group

First configure a security group using the AWS console:

[![security_group_conf.png](https://s14.postimg.org/b0ek4z0dd/security_group_conf.png)](https://postimg.org/image/bpxchc0wt/)

- port 2375 is used to connect to the docker daemon running on the remote host. It should restrict the access to your own IP address
- port 22 is used to SSH onto the remote host
- port 80 is used to access the app through HTTP

Keep the security group identifier (i.e: `sg-9d1cd8eb`) we will need it in the next step.

## 2. Provision a new server

In this step, we use the `spawn_server.rb` script to launch and provision a new EC2 instance. This script is configurable using environment variables:

- `REGION=eu-west-1` AWS region where to create the instance ([see possible values](http://docs.aws.amazon.com/general/latest/gr/rande.html#ec2_region))
- `ACCESS_KEY` required
- `SECRET_ACCESS_KEY` required
- `KEY_NAME` required, a key pair name that can be used to SSH onto the instance
- `INSTANCE_TYPE=t1.micro` type of the instance ([see possible values](https://aws.amazon.com/ec2/instance-types/))
- `INSTANCE_NAME=test-robin` name of the instance
- `MYSQL_PASSWORD` required, the password to use for the MySql root user
- `SECURITY_GROUP` required, the identifier of the previously created security group

Go to this directory and run `bundle install`. This will download the `aws-sdk` ruby gem, required by `spawn_server.rb`.
Then run the script with the desired configuration:

````bash
ACCESS_KEY="<set_me>" \
SECRET_ACCESS_KEY="<set_me>" \
KEY_NAME="<set_me>" \
MYSQL_PASSWORD="some_passwords" \
SECURITY_GROUP="<set_me>" \
ruby spawn_server.rb
````

This will output important information about your freshly created instance:

````bash
Creating instance
Waiting for instance to boot ...
...
...
...
Instance test-robin (t1.micro) deployed:
Public dns: ec2-54-78-180-161.eu-west-1.compute.amazonaws.com
ssh core@ec2-54-78-180-161.eu-west-1.compute.amazonaws.com using key some_key
mysql is running on port 3306. User: root password: some_passwords
````

In the next step we will deploy the application. You will need the instance public DNS.

## 3. Deploy an app

First clone [this repository](https://github.com/b0baille/devops-test) which contains a deployable ruby app with a `Dockerfile` that creates a container ready to run the app.

The script `deploy.rb` is used to deploy / update the app. It is configurable using the following environment variables:

- `DOCKER_HOST` required, public DNS of the previously deployed server
- `APP_VERSION` required, an integer that indicates the version we deploy. For the first deployment use `1`
- `APP_ROOT_DIR="../devops_test"` root directory of the app to deploy
- `MYSQL_PASSWORD` required, password of the mysql root user (defined during server provisioning)
- `SECRET_KEY_BASE=super_secret` rails app secret key base

Example:

````bash
APP_VERSION=1 \
DOCKER_HOST=ec2-54-74-235-87.eu-west-1.compute.amazonaws.com \
MYSQL_PASSWORD=some_passwords \
APP_ROOT_DIR="../devops_test" \
ruby deploy.rb
````

This will output information about the deployment and the app:

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
-----> To deploy an update run the command again with incremented APP_VERSION config
````

Logs indicates:
- how to access the app
- how to see logs of the app
- how to run a command in the app environment (for example `bundle exec rails c` to manipulate the production database)
- how to deploy an update of the app


# Infrastructure

## How does it works ?

This repo contains 2 scripts, one to create an instance (`spawn_server.rb`), another one to deploy an app (`deploy.rb`).

### Creating an instance

The script `spawn_server.rb` use the ruby `aws-sdk` gem to communicate with AWS's APIs. It creates an instance running [coreos linux](https://coreos.com/why/).

coreos is a linux distribution specialized in running linux containers and built to be secure and to have low maintenance overhead. It's a perfect choice to run containers. It also provides [Cloud-Config](https://coreos.com/os/docs/latest/cloud-config.html) which allow to automatically provision a coreos host. `spawn_server.rb` deploys a coreos instance provisioned with the `cloud_config.yaml` Cloud-Config file.

It setups the host with a `mysql` database running in a container and storing its data on the host file system at `/opt/data`. The database listen for connections on `localhost:3306` and the root password is given in the script's configuration. More information about the container can be found on the [docker hub](https://hub.docker.com/_/mysql/https://hub.docker.com/_/mysql/https://hub.docker.com/_/mysql/)

It also exposes the docker daemon on port 2375. This allow us to communicate remotely with the docker daemon.

### Deploying an app

The script `deploy.rb` uses docker (provided inside `vendor/docker`) to deploy apps. It connects the docker client to the remote docker daemon and gives it instructions to build and run containers:

1. It first build the app using it's `Dockerfile`
2. On first deployment, it runs the `rake db:create` command
3. It runs the `rake db:migrate` command
4. It starts the app container with the `puma -p $PORT`
5. On first deployment, it build and run a container which forward requests on port 80 to the app

## Advantages of this solution

**Automatic and fast server provisioning**. With one command a ready to use server is available

**Efficient dependencies management**. Everything runs in linux containers. Dependencies are packed inside each container. This make it really easy to update the app stack. For example, if we want our app to use a new system tool, we can just modify the app `Dockerfile` to package this new system tool. This make the remote server "unaware" of the app stack, and abstract away system dependencies.

**Reproducible deployments**. Containers and scripts make the deployment process reproducible and predictable. If the app container runs properly somewhere it will run properly everywhere.

**Automated, no SSH**. Scripts automate the entire deployment process and do not requires user to SSH onto the remote host. This reduce the potential human errors.

**Reusable**. This solution could be used to deploy any app using MySql. The only constraint would be to create a `Dockerfile` on the app and make it uses the environment variables `MYSQL_PORT`, `MYSQL_PASSWORD`, `MYSQL_USER` and `MYSQL_HOST`


## Why not production ready ?

**Badly secured**. In the guide above we expose the docker daemon on an open TCP port. During security group creation, we restricted the access to only our IP address but this is not enough. An attacker could connect to our docker daemon and manage it (stop container, create new containers ...). The solution to overcome this issue would be to secure the docker daemon socket following [this guide](https://docs.docker.com/engine/security/https/).

**No redundancy / no high availability**. Each containers are started with a flag indicating that they should restart on failure. This will allow the app to restart automatically if it crashes for example. This is good, however, if our server crashes, the app will be down and we might lose all our data. This could be addressed by a more complex setup including database backup / multiple running instances / load balancing.

**No monitoring**. App logs can easily be consulted, however there is no mechanism to monitor server usage and app performances

**Downtime during deployment**. When we deploy an update the app will be done during the new app version starts.
