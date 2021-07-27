In this tutorial, we'll look at how to configure GitLab CI to continuously deploy a Django and Docker application to Amazon Web Services (AWS) EC2.

Objectives
1.Set up a new EC2 instance
2.Configure an AWS Security Group
3.Install Docker on an EC2 instance
4.Set up Passwordless SSH Login
5 Configure AWS RDS for data persistence
6.Deploy Django to AWS EC2 with Docker
7.Configure GitLab CI to continuously deploy Django to EC2

Project Setup
Along with Django and Docker, the demo project that we'll be using includes Postgres, Nginx, and Gunicorn.

Step1
create an EC@2 instance
sg -80 and 22
install docker and docker compose

[ec2-user]$ sudo yum update -y
[ec2-user]$ sudo yum install -y docker
[ec2-user]$ sudo service docker start

[ec2-user]$ sudo curl -L "https://github.com/docker/compose/releases/download/1.25.5/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
[ec2-user]$ sudo chmod +x /usr/local/bin/docker-compose

[ec2-user]$ docker --version
Docker version 19.03.6-ce, build 369ce74

[ec2-user]$ docker-compose --version
docker-compose version 1.25.5, build 8a1c60f6

Add the ec2-user to the docker group so you can execute Docker commands without having to use sudo:

sudo usermod -a -G docker ec2-user

Next, generate a new SSH key:
ssh-keygen -t rsa

Save the key to /home/ec2-user/.ssh/id_rsa and don't set a password. This will generate a public and private key -- id_rsa and id_rsa.pub, respectively. To set up passwordless SSH login, copy the public key over to the authorized_keys file and set the proper permissions:

[ec2-user]$ cat ~/.ssh/id_rsa.pub
[ec2-user]$ vi ~/.ssh/authorized_keys
[ec2-user]$ chmod 600 ~/.ssh/authorized_keys
[ec2-user]$ chmod 600 ~/.ssh/id_rsa

Copy the contents of the private key:

[ec2-user]$ cat ~/.ssh/id_rsa


Add the key to the ssh-agent:

$ ssh-add - <<< "${PRIVATE_KEY}"

To test, run:

$ ssh -o StrictHostKeyChecking=no ec2-user@<YOUR_INSTANCE_IP> whoami

ec2-user

# example:
# ssh -o StrictHostKeyChecking=no ec2-user@54.183.101.163 whoami

Then, create a new directory for the app:
ssh -o StrictHostKeyChecking=no root@<YOUR_INSTANCE_IP> mkdir /home/ec2-user/app

RDS
Moving along, let's spin up a production Postgres database via AWS Relational Database Service (RDS).
It will take a few minutes for the RDS instance to spin up. Once it's available, take note of the endpoint. For example:

djangodb.c7kxiqfnzo9e.us-west-1.rds.amazonaws.com

The full URL will look something like this:
postgres://username:password@rdsendpoint:5432/databasename
postgres://webapp:YOUR_PASSWORD@djangodb.c7kxiqfnzo9e.us-west-1.rds.amazonaws.com:5432/django_prod

sign in to gitlab
create gitlab.ci file

Here, we defined a single build stage where we:

Set the IMAGE, WEB_IMAGE, and NGINX_IMAGE environment variables
Install bash
Set the appropriate permissions for setup_env.sh
Run setup_env.sh
Log in to the GitLab Container Registry
Pull the images if they exist
Build the images
Push the images up to the registry
Add the setup_env.sh file to the project root:

This file will create the required .env file, based on the environment variables found in your GitLab project's CI/CD settings (Settings > CI / CD > Variables). Add the variables based on the RDS connection information from above.

For example:

SECRET_KEY: 9zYGEFk2mn3mWB8Bmg9SAhPy6F4s7cCuT8qaYGVEnu7huGRKW9
SQL_DATABASE: djangodb
SQL_HOST: djangodb.c7kxiqfnzo9e.us-west-1.rds.amazonaws.com
SQL_PASSWORD: 3ZQtN4vxkZp2kAa0vinV
SQL_PORT: 5432
SQL_USER: webapp

Once done, commit and push your code up to GitLab to trigger a new build. Make sure it passes. You should see the images in the GitLab Container Registry:

AWS Security Group
Next, before adding deployment to the CI process, we need to update the inbound ports for the "Security Group" so that port 5432 can be accessed from the EC2 instance. Why is this necessary? Turn to app/entrypoint.prod.sh:

Here, we're waiting for the Postgres instance to be healthy, by testing the connection with netcat, before starting Gunciorn. If port 5432 isn't open, the loop will continue forever.

So, navigate to the EC2 Console again and click "Security Groups" on the left sidebar. Select the django-security-group Security Group and click "Edit inbound rules":

Click "Add rule". Under type, select "PostgreSQL" and under source select the django-security-group Security Group:
add 5432 and select sg-group of rds.remember when creating rds the sg was the one from ec2 we create you associate it with the rds.

GitLab CI: Deploy Stage
Next, add a deploy stage to .gitlab-ci.yml and create a global before_script that's used for both stages

So, in the deploy stage we:

Add the private SSH key to the ssh-agent
Copy over the .env and docker-compose.prod.yml files to the remote server
Set the appropriate permissions for deploy.sh
Run deploy.sh

So, after SSHing into the server, we

Navigate to the deployment directory
Add the environment variables
Log in to the GitLab Container Registry
Pull the images
Spin up the containers
Add the EC2_PUBLIC_IP_ADDRESS and PRIVATE_KEY environment variables to GitLab.

Update the setup_env.sh file:

#!/bin/sh

echo DEBUG=0 >> .env
echo SQL_ENGINE=django.db.backends.postgresql >> .env
echo DATABASE=postgres >> .env

echo SECRET_KEY=$SECRET_KEY >> .env
echo SQL_DATABASE=$SQL_DATABASE >> .env
echo SQL_USER=$SQL_USER >> .env
echo SQL_PASSWORD=$SQL_PASSWORD >> .env
echo SQL_HOST=$SQL_HOST >> .env
echo SQL_PORT=$SQL_PORT >> .env
echo WEB_IMAGE=$IMAGE:web  >> .env
echo NGINX_IMAGE=$IMAGE:nginx  >> .env
echo CI_REGISTRY_USER=$CI_REGISTRY_USER   >> .env
echo CI_JOB_TOKEN=$CI_JOB_TOKEN  >> .env
echo CI_REGISTRY=$CI_REGISTRY  >> .env
echo IMAGE=$CI_REGISTRY/$CI_PROJECT_NAMESPACE/$CI_PROJECT_NAME >> .env

Next, add the server's IP to the ALLOWED_HOSTS list in the Django settings.

Commit and push your code to trigger a new build. Once the build passes, navigate to the IP of your instance. You should see:

{
  "hello": "world"
}

PostgreSQL via SSH Tunnel
Need to access the database?

SSH into the box:

$ ssh -o StrictHostKeyChecking=no ec2-user@<YOUR_INSTANCE_IP>

Install Postgres:

[ec2-user]$ sudo amazon-linux-extras install postgresql11 -y
Then, run psql, like so:

[ec2-user]$ psql -h <YOUR_RDS_ENDPOINT> -U webapp -d django_prod

Enter the password.

psql (11.5, server 12.2)
WARNING: psql major version 11, server major version 12.
         Some psql features might not work.
SSL connection (protocol: TLSv1.2, cipher: ECDHE-RSA-AES256-GCM-SHA384, bits: 256, compression: off)
Type "help" for help.

django_prod=> \l
                                   List of databases
    Name     |  Owner   | Encoding |   Collate   |    Ctype    |   Access privileges
-------------+----------+----------+-------------+-------------+-----------------------
 django_prod | webapp   | UTF8     | en_US.UTF-8 | en_US.UTF-8 |
 postgres    | webapp   | UTF8     | en_US.UTF-8 | en_US.UTF-8 |
 rdsadmin    | rdsadmin | UTF8     | en_US.UTF-8 | en_US.UTF-8 | rdsadmin=CTc/rdsadmin
 template0   | rdsadmin | UTF8     | en_US.UTF-8 | en_US.UTF-8 | =c/rdsadmin          +
             |          |          |             |             | rdsadmin=CTc/rdsadmin
 template1   | webapp   | UTF8     | en_US.UTF-8 | en_US.UTF-8 | =c/webapp            +
             |          |          |             |             | webapp=CTc/webapp
(5 rows)

django_prod=> \q
Exit the SSH session once done.

Finally, update the deploy stage so that it only runs when changes are made to the master branch:

deploy:
  stage: deploy
  script:
    - mkdir -p ~/.ssh
    - echo "$PRIVATE_KEY" | tr -d '\r' > ~/.ssh/id_rsa
    - cat ~/.ssh/id_rsa
    - chmod 700 ~/.ssh/id_rsa
    - eval "$(ssh-agent -s)"
    - ssh-add ~/.ssh/id_rsa
    - ssh-keyscan -H 'gitlab.com' >> ~/.ssh/known_hosts
    - chmod +x ./deploy.sh
    - scp  -o StrictHostKeyChecking=no -r ./.env ./docker-compose.prod.yml ec2-user@$EC2_PUBLIC_IP_ADDRESS:/home/ec2-user/app
    - bash ./deploy.sh
  only:
    - master

to test, create a new develop branch. Add an exclamation point after world in urls.py:

def home(request):
    return JsonResponse({"hello": "world!"})    

o test, create a new develop branch. Add an exclamation point after world in urls.py:

def home(request):
    return JsonResponse({"hello": "world!"})
Commit and push your changes to GitLab. Ensure only the build stage runs. Once the build passes open a PR against the master branch and merge the changes. This will trigger a new pipeline with both stages -- build and deploy. Ensure the deploy works as expected:

{
  "hello": "world!"
}    

Next Steps
This tutorial looked at how to configure GitLab CI to continuously deploy a Django and Docker application to AWS EC2.

At this point, you'll probably want to use a domain name rather than an IP address. To do so, you'll need to:

Set up a static IP address and associate it to your EC2 instance
Create an SSL certificate through Amazon Certificate Manager
Set up a new Elastic Load Balancer and install the certificate on it





