Objectives
By the end of this tutorial, you will be able to:

Explain what Terraform is and how you can use it to write infrastructure as code
Utilize the ECR Docker image registry to store images
Create the required Terraform configuration for spinning up an ECS cluster
Spin up AWS infrastructure via Terraform
Deploy a Django app to a cluster of EC2 instances manged by an ECS Cluster
Use Boto3 to update an ECS Service
Configure AWS RDS for data persistence
Create an HTTPS listener for an AWS load balancer

In this tutorial, using Terraform, we'll develop the high-level configuration files required to deploy a Django application to ECS. Once configured, we'll run a single command to set up the following AWS infrastructure:

Networking:
VPC
Public and private subnets
Routing tables
Internet Gateway
Key Pairs
Security Groups
Load Balancers, Listeners, and Target Groups
IAM Roles and Policies
ECS:
Task Definition (with multiple containers)
Cluster
Service
Launch Config and Auto Scaling Group
RDS
Health Checks and Logs

For testing purposes, set DEBUG to True and allow all hosts in the settings.py file:

DEBUG = True

ALLOWED_HOSTS = ['*']

docker build -t django-ecs .

$ docker run \
    -p 8007:8000 \
    --name django-test \
    django-ecs \
    gunicorn hello_django.wsgi:application --bind 0.0.0.0:8000

Ensure you can view the welcome screen again at http://localhost:8007/.

Stop and remove the container once done:

$ docker stop django-test
$ docker rm django-test    

ECR
Before jumping into Terraform, let's push the Docker image to Elastic Container Registry (ECR), a private Docker image registry.

Navigate to the ECR console, and add a new repository called "django-app". Keep the tags mutable.
aws ecr get-login --region us-west-1 --no-include-email
docker push <AWS_ACCOUNT_ID>.dkr.ecr.us-west-1.amazonaws.com/django-app:latest

Terraform Setup
Add a "terraform" folder to your project's root. We'll add each of our Terraform configuration files to this folder.

Here, we defined the AWS provider. You'll need to provide your AWS credentials in order to authenticate. Define them as environment variables:

export AWS_ACCESS_KEY_ID="YOUR_AWS_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="YOUR_AWS_SECRET_ACCESS_KEY"

Run terraform init to create a new Terraform working directory and download the AWS provider.
terraform init

With that we can start defining each piece of the AWS infrastructure.

AWS Resources
Next, let's configure the following AWS resources:

Networking:
VPC
Public and private subnets
Routing tables
Internet Gateway
Key Pairs
Security Groups
Load Balancers, Listeners, and Target Groups
IAM Roles and Policies
ECS:
Task Definition (with multiple containers)
Cluster
Service
Launch Config and Auto Scaling Group
Health Checks and Logs

Network Resources
Here, we defined the following resources:

Virtual Private Cloud (VPC)
Public and private subnets
Route tables
Internet Gateway

Run terraform plan to generate and show the execution plan based on the defined configuration.
Security Groups
Moving on, to protect the Django app and ECS cluster, let's configure Security Groups in a new file called 03_securitygroups.tf:

Take note of the inbound rule on the Security Group associated with the ECS cluster for port 22. This is so we can SSH into an EC2 instance to run the initial DB migrations and add a super user.

Load Balancer
Next, let's configure an Application Load Balancer (ALB) along with the appropriate Target Group and Listener.

So, we configured our load balancer and listener to listen for HTTP requests on port 80. This is temporary. After we verify that our infrastructure and application are set up correctly, we'll update the load balancer to listen for HTTPS requests on port 443.

Take note of the path URL for the health check: /ping/.

IAM Roles
05_iam.tf:

Logs
06_logs.tf:

Key Pair
07_keypair.tf:

ECS
Now, we can configure our ECS cluster.

08_ecs.tf:

Take a look at the user_data field in the aws_launch_configuration. Put simply, user_data is a script that is run when a new EC2 instance is launched. In order for the ECS cluster to discover new EC2 instances, the cluster name needs to be added to the ECS_CLUSTER environment variable within the /etc/ecs/ecs.config config file within the instance. In other words, the following script will run when a new instance is bootstrapped allowing it to be discovered by the cluster:

#!/bin/bash

echo ECS_CLUSTER='production-cluster' > /etc/ecs/ecs.config

Here, we defined our container definition associated with the Django app.

Add the following variables as well:

Again, be sure to replace <AWS_ACCOUNT_ID> with your AWS account ID.

Refer to the Linux Amazon ECS-optimized AMIs guide to find a list of AMIs with Docker pre-installed.

Since we added the Template provider, run terraform init again to download the new provider.

Auto Scaling
09_auto_scaling.tf:

Here, we configured an outputs.tf file along with an output value called alb_hostname. After we execute the Terraform plan, to spin up the AWS infrastructure, the load balancer's DNS name will be outputted to the terminal.

Ready?!? View then execute the plan:

$ terraform plan

$ terraform apply
You should see the health check failing with a 404:

service production-cluster-service (instance i-0fcfd50237c009dc1) (port 32770)
is unhealthy in target-group production-cluster-tg due to
(reason Health checks failed with these codes: [404])
This is expected since we haven't set up a /ping/ handler in the app yet.

Django Health Check
Add the following middleware to app/hello_django/middleware.py:

from django.http import HttpResponse
from django.utils.deprecation import MiddlewareMixin


class HealthCheckMiddleware(MiddlewareMixin):
    def process_request(self, request):
        if request.META['PATH_INFO'] == '/ping/':
            return HttpResponse('pong!')
Add the class to the middleware config in settings.py:

MIDDLEWARE = [
    'hello_django.middleware.HealthCheckMiddleware',  # new
    'django.middleware.security.SecurityMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
]
This middleware is used to handle requests to the /ping/ URL before ALLOWED_HOSTS is checked. Why is this necessary?

The health check request comes from the EC2 instance. Since we don't know the private IP beforehand, this will ensure that the /ping/ route always returns a successful response even after we restrict ALLOWED_HOSTS.

It's worth noting that you could toss Nginx in front of Gunicorn and handle the health check in the Nginx config like so:

location /ping/ {
    access_log off;
    return 200;
}
To test locally, build the new image and then spin up the container:

docker build -t django-ecs .

$ docker run \
    -p 8007:8000 \
    --name django-test \
    django-ecs \
    gunicorn hello_django.wsgi:application --bind 0.0.0.0:8000
Make sure http://localhost:8007/ping/ works as expected:

pong!

Stop and remove the container once done:

$ docker stop django-test
$ docker rm django-test
Next, update ECR:

$ docker build -t <AWS_ACCOUNT_ID>.dkr.ecr.us-west-1.amazonaws.com/django-app:latest .
$ docker push <AWS_ACCOUNT_ID>.dkr.ecr.us-west-1.amazonaws.com/django-app:latest

Let's add a quick script to update the Task Definition and Service so that the new Tasks use the new image that we just pushed.

Create a "deploy" folder in the project root. Then, add an update-ecs.py file to that newly created folder:

So, this script will create a new revision of the Task Definition and then update the Service so it uses the revised Task Definition.

Create and activate a new virtual environment. Then, install Boto3 and Click:

$ pip install boto3 click

Add your AWS credentials along with the default region:

$ export AWS_ACCESS_KEY_ID="YOUR_AWS_ACCESS_KEY_ID"
$ export AWS_SECRET_ACCESS_KEY="YOUR_AWS_SECRET_ACCESS_KEY"
$ export AWS_DEFAULT_REGION="us-west-1"
Run the script like so:

$ python update-ecs.py --cluster=production-cluster --service=production-service

The Service should start two new Tasks based on the revised Task Definition and register them with the associated Target Group. This time the health checks should pass. You should now be able to view your application using the DNS hostname that was outputted to your terminal:

Outputs:

alb_hostname = production-alb-1008464563.us-west-1.elb.amazonaws.com

RDS
Next, let's configure RDS so we can use Postgres for our production database.

Add a new Security Group to 03_securitygroups.tf to ensure that only traffic from your ECS instance can talk to the database:

Note that we left off the default value for the password. More on this in a bit.

Since we'll need to know the address for the instance in our Django app, add a depends_on argument to the aws_ecs_task_definition in 08_ecs.tf:

resource "aws_ecs_task_definition" "app" {
  family                = "django-app"
  container_definitions = data.template_file.app.rendered
  depends_on            = [aws_db_instance.production]
}

Next, we need to update the DATABASES config in settings.py:

if 'RDS_DB_NAME' in os.environ:
    DATABASES = {
        'default': {
            'ENGINE': 'django.db.backends.postgresql_psycopg2',
            'NAME': os.environ['RDS_DB_NAME'],
            'USER': os.environ['RDS_USERNAME'],
            'PASSWORD': os.environ['RDS_PASSWORD'],
            'HOST': os.environ['RDS_HOSTNAME'],
            'PORT': os.environ['RDS_PORT'],
        }
    }
else:
    DATABASES = {
        'default': {
            'ENGINE': 'django.db.backends.sqlite3',
            'NAME': os.path.join(BASE_DIR, 'db.sqlite3'),
        }
    }

Update the environment section in the django_app.json.tpl template:

"environment": [
  {
    "name": "RDS_DB_NAME",
    "value": "${rds_db_name}"
  },
  {
    "name": "RDS_USERNAME",
    "value": "${rds_username}"
  },
  {
    "name": "RDS_PASSWORD",
    "value": "${rds_password}"
  },
  {
    "name": "RDS_HOSTNAME",
    "value": "${rds_hostname}"
  },
  {
    "name": "RDS_PORT",
    "value": "5432"
  }
],

Update the vars passed to the template in 08_ecs.tf:

data "template_file" "app" {
  template = file("templates/django_app.json.tpl")

  vars = {
    docker_image_url_django = var.docker_image_url_django
    region                  = var.region
    rds_db_name             = var.rds_db_name
    rds_username            = var.rds_username
    rds_password            = var.rds_password
    rds_hostname            = aws_db_instance.production.address
  }
}



Add Psycopg2 to the requirements file:

Django==3.1
gunicorn==20.0.4
psycopg2-binary==2.8.5

Update the Dockerfile to install the appropriate packages required for Psycopg2:

# pull official base image
FROM python:3.8.5-slim-buster

# set work directory
WORKDIR /usr/src/app

# set environment variables
ENV PYTHONDONTWRITEBYTECODE 1
ENV PYTHONUNBUFFERED 1

# install psycopg2 dependencies
RUN apt-get update \
  && apt-get -y install gcc postgresql \
  && apt-get clean

# install dependencies
RUN pip install --upgrade pip
COPY ./requirements.txt .
RUN pip install -r requirements.txt

# copy project
COPY . .

Alright. Build the Docker image and push it up to ECR. Then, to update the ECS Task Definition, create the RDS resources, and update the Service, run:

$ terraform apply

Since we didn't set a default for the password, you'll be prompted to enter one:

var.rds_password
  RDS database password

  Enter a value:
Rather than having to pass a value in each time, you could set an environment variable like so:

$ export TF_VAR_rds_password=foobarbaz

$ terraform apply

Keep in mind that this approach, of using environment variables, keeps sensitive variables out of the .tf files, but they are still stored in the terraform.tfstate file in plain text. So, be sure to keep this file out of version control. Since keeping it out of version control doesn't work if other people on your team need access to it, look to either encrypting the secrets or using a secret store like Vault or AWS Secrets Manager.

After the new Tasks are registered with the Target Group, SSH into an EC2 instance where one of the Tasks is running:

$ ssh ec2-user@<instance-ip>
Grab the container ID via docker ps, and use it to apply the migrations:

$ docker exec -it <container-id> python manage.py migrate

# docker exec -it 73284cda8a87 python manage.py migrate

You may want to create a super user as well. Once done, exit from the SSH session. You'll probably want to remove the following inbound rule from the ECS Security group if you don't need SSH access any longer:

ingress {
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
}

Domain and SSL Certificate
Assuming you've generated and validated a new SSL certificate from AWS Certificate Manager, add the certificate's ARN to your variables:

# domain

variable "certificate_arn" {
  description = "AWS Certificate Manager ARN for validated domain"
  default     = "ADD YOUR ARN HERE"
}

Update the default listener associated with the load balancer in 04_loadbalancer.tf so that it listens for HTTPS requests on port 443 (as opposed to HTTP on port 80):

# Listener (redirects traffic from the load balancer to the target group)
resource "aws_alb_listener" "ecs-alb-http-listener" {
  load_balancer_arn = aws_lb.production.id
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = var.certificate_arn
  depends_on        = [aws_alb_target_group.default-target-group]

  default_action {
    type             = "forward"
    target_group_arn = aws_alb_target_group.default-target-group.arn
  }
}
Apply the changes:

$ terraform apply

Make sure to point your domain at the load balancer using a CNAME record. Make sure you can view your application.

Nginx
Next, let's add Nginx into the mix to handle requests for static files appropriately.

In the project root, create the following files and folders:
Here, we set up a single location block, routing all traffic to the Django app. We'll set up a new location block for static files in the next section.

Create a new repo in ECR called "nginx", and then build and push the new image:

$ docker build -t <AWS_ACCOUNT_ID>.dkr.ecr.us-west-1.amazonaws.com/nginx:latest .
$ docker push <AWS_ACCOUNT_ID>.dkr.ecr.us-west-1.amazonaws.com/nginx:latest

Add the following variable to the ECS section of the variables file:

variable "docker_image_url_nginx" {
  description = "Docker image to run in the ECS cluster"
  default     = "<AWS_ACCOUNT_ID>.dkr.ecr.us-west-1.amazonaws.com/nginx:latest"
}

Add the new container definition to the django_app.json.tpl template:

[
  {
    "name": "django-app",
    "image": "${docker_image_url_django}",
    "essential": true,
    "cpu": 10,
    "memory": 512,
    "links": [],
    "portMappings": [
      {
        "containerPort": 8000,
        "hostPort": 0,
        "protocol": "tcp"
      }
    ],
    "command": ["gunicorn", "-w", "3", "-b", ":8000", "hello_django.wsgi:application"],
    "environment": [
      {
        "name": "RDS_DB_NAME",
        "value": "${rds_db_name}"
      },
      {
        "name": "RDS_USERNAME",
        "value": "${rds_username}"
      },
      {
        "name": "RDS_PASSWORD",
        "value": "${rds_password}"
      },
      {
        "name": "RDS_HOSTNAME",
        "value": "${rds_hostname}"
      },
      {
        "name": "RDS_PORT",
        "value": "5432"
      }
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "/ecs/django-app",
        "awslogs-region": "${region}",
        "awslogs-stream-prefix": "django-app-log-stream"
      }
    }
  },
  {
    "name": "nginx",
    "image": "${docker_image_url_nginx}",
    "essential": true,
    "cpu": 10,
    "memory": 128,
    "links": ["django-app"],
    "portMappings": [
      {
        "containerPort": 80,
        "hostPort": 0,
        "protocol": "tcp"
      }
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "/ecs/nginx",
        "awslogs-region": "${region}",
        "awslogs-stream-prefix": "nginx-log-stream"
      }
    }
  }
]

Pass the variable to the template in 08_ecs.tf:

data "template_file" "app" {
  template = file("templates/django_app.json.tpl")

  vars = {
    docker_image_url_django = var.docker_image_url_django
    docker_image_url_nginx  = var.docker_image_url_nginx
    region                  = var.region
    rds_db_name             = var.rds_db_name
    rds_username            = var.rds_username
    rds_password            = var.rds_password
    rds_hostname            = aws_db_instance.production.address
  }
}

Add the new logs to 06_logs.tf:

resource "aws_cloudwatch_log_group" "nginx-log-group" {
  name              = "/ecs/nginx"
  retention_in_days = var.log_retention_in_days
}

resource "aws_cloudwatch_log_stream" "nginx-log-stream" {
  name           = "nginx-log-stream"
  log_group_name = aws_cloudwatch_log_group.nginx-log-group.name
}

Update the Service so it points to the nginx container instead of django-app:

resource "aws_ecs_service" "production" {
  name            = "${var.ecs_cluster_name}-service"
  cluster         = aws_ecs_cluster.production.id
  task_definition = aws_ecs_task_definition.app.arn
  iam_role        = aws_iam_role.ecs-service-role.arn
  desired_count   = var.app_count
  depends_on      = [aws_alb_listener.ecs-alb-http-listener, aws_iam_role_policy.ecs-service-role-policy]

  load_balancer {
    target_group_arn = aws_alb_target_group.default-target-group.arn
    container_name   = "nginx"
    container_port   = 80
  }
}

Apply the changes:

$ terraform apply

Make sure the app can still be accessed from the browser.

Now that we're dealing with two containers, let's update the deploy function to handle multiple container definitions in update-ecs.py:

@click.command()
@click.option("--cluster", help="Name of the ECS cluster", required=True)
@click.option("--service", help="Name of the ECS service", required=True)
def deploy(cluster, service):
    client = boto3.client("ecs")

    container_definitions = []
    response = get_current_task_definition(client, cluster, service)
    for container_definition in response["taskDefinition"]["containerDefinitions"]:
        new_def = container_definition.copy()
        container_definitions.append(new_def)

    response = client.register_task_definition(
        family=response["taskDefinition"]["family"],
        volumes=response["taskDefinition"]["volumes"],
        containerDefinitions=container_definitions,
    )
    new_task_arn = response["taskDefinition"]["taskDefinitionArn"]

    response = client.update_service(
        cluster=cluster, service=service, taskDefinition=new_task_arn,
    )

Static Files
Set the STATIC_ROOT in your settings.py file:

STATIC_URL = '/staticfiles/'
STATIC_ROOT = os.path.join(BASE_DIR, 'staticfiles')
Also, turn off debug mode:

DEBUG = False

Update the Dockerfile so that it runs the collectstatic command at the end:

# pull official base image
FROM python:3.8.5-slim-buster

# set work directory
WORKDIR /usr/src/app

# set environment variables
ENV PYTHONDONTWRITEBYTECODE 1
ENV PYTHONUNBUFFERED 1

# install psycopg2 dependencies
RUN apt-get update \
  && apt-get -y install gcc postgresql \
  && apt-get clean

# install dependencies
RUN pip install --upgrade pip
COPY ./requirements.txt .
RUN pip install -r requirements.txt

# copy project
COPY . .

# collect static files
RUN python manage.py collectstatic --no-input

Next, let's add a shared volume to the Task Definition and update the Nginx conf file.

Add the new location block to nginx.conf:

upstream hello_django {
    server django-app:8000;
}

server {

    listen 80;

    location /staticfiles/ {
        alias /usr/src/app/staticfiles/;
    }

    location / {
        proxy_pass http://hello_django;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Host $host;
        proxy_redirect off;
    }

}

Add the volume to aws_ecs_task_definition in 08_ecs.tf:

resource "aws_ecs_task_definition" "app" {
  family                = "django-app"
  container_definitions = data.template_file.app.rendered
  depends_on            = [aws_db_instance.production]

  volume {
    name      = "static_volume"
    host_path = "/usr/src/app/staticfiles/"
  }
}

Add the volume to the container definitions in the django_app.json.tpl template:

[
  {
    "name": "django-app",
    "image": "${docker_image_url_django}",
    "essential": true,
    "cpu": 10,
    "memory": 512,
    "links": [],
    "portMappings": [
      {
        "containerPort": 8000,
        "hostPort": 0,
        "protocol": "tcp"
      }
    ],
    "command": ["gunicorn", "-w", "3", "-b", ":8000", "hello_django.wsgi:application"],
    "environment": [
      {
        "name": "RDS_DB_NAME",
        "value": "${rds_db_name}"
      },
      {
        "name": "RDS_USERNAME",
        "value": "${rds_username}"
      },
      {
        "name": "RDS_PASSWORD",
        "value": "${rds_password}"
      },
      {
        "name": "RDS_HOSTNAME",
        "value": "${rds_hostname}"
      },
      {
        "name": "RDS_PORT",
        "value": "5432"
      }
    ],
    "mountPoints": [
      {
        "containerPath": "/usr/src/app/staticfiles",
        "sourceVolume": "static_volume"
      }
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "/ecs/django-app",
        "awslogs-region": "${region}",
        "awslogs-stream-prefix": "django-app-log-stream"
      }
    }
  },
  {
    "name": "nginx",
    "image": "${docker_image_url_nginx}",
    "essential": true,
    "cpu": 10,
    "memory": 128,
    "links": ["django-app"],
    "portMappings": [
      {
        "containerPort": 80,
        "hostPort": 0,
        "protocol": "tcp"
      }
    ],
    "mountPoints": [
      {
        "containerPath": "/usr/src/app/staticfiles",
        "sourceVolume": "static_volume"
      }
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "/ecs/nginx",
        "awslogs-region": "${region}",
        "awslogs-stream-prefix": "nginx-log-stream"
      }
    }
  }
]

Now, each container will share a directory named "staticfiles".

Build the new images and push them up to ECR:

$ docker build -t <AWS_ACCOUNT_ID>.dkr.ecr.us-west-1.amazonaws.com/django-app:latest .
$ docker push <AWS_ACCOUNT_ID>.dkr.ecr.us-west-1.amazonaws.com/django-app:latest

$ docker build -t <AWS_ACCOUNT_ID>.dkr.ecr.us-west-1.amazonaws.com/nginx:latest .
$ docker push <AWS_ACCOUNT_ID>.dkr.ecr.us-west-1.amazonaws.com/nginx:latest

Apply the changes:

$ terraform apply

Static files should now load correctly.

Allowed Hosts
Finally, let's lock down our application for production:

ALLOWED_HOSTS = os.getenv('ALLOWED_HOSTS', '').split()

Add the ALLOWED_HOSTS environment variable to the container definition:

"environment": [
  {
    "name": "RDS_DB_NAME",
    "value": "${rds_db_name}"
  },
  {
    "name": "RDS_USERNAME",
    "value": "${rds_username}"
  },
  {
    "name": "RDS_PASSWORD",
    "value": "${rds_password}"
  },
  {
    "name": "RDS_HOSTNAME",
    "value": "${rds_hostname}"
  },
  {
    "name": "RDS_PORT",
    "value": "5432"
  },
  {
    "name": "ALLOWED_HOSTS",
    "value": "${allowed_hosts}"
  }
],

Pass the variable to the template in 08_ecs.tf:

data "template_file" "app" {
  template = file("templates/django_app.json.tpl")

  vars = {
    docker_image_url_django = var.docker_image_url_django
    docker_image_url_nginx  = var.docker_image_url_nginx
    region                  = var.region
    rds_db_name             = var.rds_db_name
    rds_username            = var.rds_username
    rds_password            = var.rds_password
    rds_hostname            = aws_db_instance.production.address
    allowed_hosts           = var.allowed_hosts
  }
}

Add the variable to the ECS section of the variables file, making sure to add your domain name:

variable "allowed_hosts" {
  description = "Domain name for allowed hosts"
  default     = "YOUR DOMAIN NAME"
}

Build the new image and push it up to ECR:

$ docker build -t <AWS_ACCOUNT_ID>.dkr.ecr.us-west-1.amazonaws.com/django-app:latest .
$ docker push <AWS_ACCOUNT_ID>.dkr.ecr.us-west-1.amazonaws.com/django-app:latest

Apply:

$ terraform apply

Bring the infrastructure down once done:

$ terraform destroy

Conclusion
This tutorial looked at how to use Terraform to spin up the required AWS infrastructure for running a Django app on ECS.

While the initial configuration is complex, large teams with complicated infrastructure requirements, will benefit from Terraform. It provides a readable, central source of truth for your infrastructure, which should result in quicker feedback cycles.

Next steps:

Configure CloudWatch alarms for scaling containers out and in.
Store user-uploaded files on Amazon S3
Set up multi-stage Docker builds and use a non-root user in the Docker container
Rather than routing traffic on port 80 to Nginx, add a listener for port 443.
Run through the entire Django deployment checklist.
If you're planing to host multiple applications, you may want to move any "common" resources shared across the applications to a separate Terraform stack so that if you're regularly making modifications, your core AWS services will not be not affected.
Take a look at ECS Fargate. This can help simply your infrastructure since you don't have to manage the actual cluster.





