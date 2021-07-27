In this tutorial, we'll deploy a Django app to AWS EC2 with Docker. The app will run behind an HTTPS Nginx proxy with Let's Encrypt SSL certificates. We'll use AWS RDS to serve our Postgres database along with AWS ECR to store and manage our Docker images.

By the end of this tutorial, you will be able to:

1.Set up a new EC2 instance
2.Install Docker on an EC2 instance
3.Configure and use an Elastic IP address
4.Set up an IAM role
5.Utilize Amazon Elastic Container Registry (ECR) image registry to store built images
6.Configure AWS RDS for data persistence
7.Configure an AWS Security Group
8.Deploy Django to AWS EC2 with Docker
9.Run the Django app behind an HTTPS Nginx proxy with Let's Encrypt SSL certificates

procedures
1. create an ec2 instance
  --sg 22,80,443 --ssh,http and https and custom 0.0.0.0/0 from aywhere
2. Access the instance and install the docker file  

Start by installing the latest version of Docker and version 1.25.5 of Docker Compose:
$ sudo apt update
$ sudo apt install apt-transport-https ca-certificates curl software-properties-common
$ curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
$ sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu bionic stable"
$ sudo apt update
$ sudo apt install docker-ce
$ sudo usermod -aG docker ${USER}
$ sudo curl -L "https://github.com/docker/compose/releases/download/1.25.5/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
$ sudo chmod +x /usr/local/bin/docker-compose

Install AWS CLI
$ sudo apt install unzip
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
$ aws --version

Elastic IP
By default, instances receive new public IP address every time they start and re-start.

Elastic IP allows you to allocate static IPs for your EC2 instances, so the IP stays the same all the time and can be re-associated between instances. It's recommended to use one for your production setup.
associate an elastic ip address and associate it with our instance

IAM Role
We'll be using AWS ECR to pull images from AWS ECR to our EC2 instance during deployment. Since public access to ECR is not allowed, you'll need to create an IAM role with permissions to pull Docker images from ECR and attach it to your EC2 instance.
create an ec2 role and and add ecrpolicy to and attach it to our ec2

Add DNS Record
Add an A record to your DNS, for the domain that you are using, to point to your EC2 instance's public IP.

It's the Elastic IP you've associated to your instance.

CREATE an ECR

AWS RDS
Now we can add configure a RDS Postgres database.

While you can run your own Postgres database in a container, since databases are critical services, adding additional layers, such us Docker, adds unnecessary risk in production. To simplify tasks such as minor version updates, regular backups, and scaling, it's recommended to use a managed service

Under Settings, set:

DB Instance identifier: djangoec2
Master username: webapp
Select Auto generate a password
security-group 5432 for our database ensure its there

Leave Database authentication as it is.

Open Additional configuration and change Initial database name to djangoec2

Finally, click Create database.

Take note of the database endpoint; you'll need to set it in your Django app.

To limit access to your database, only connections from instances inside the same Security Group are allowed. Our application can connect because we set the same Security Group, django-ec2, for both the RDS and EC2 instances. Instances inside other Security Groups are therefore not allowed to connect.

Project Config
With the AWS infrastructure set up, we now need to configure our Django project locally before deploying it.

git clone https://github.com/testdrivenio/django-on-docker-letsencrypt django-on-docker-letsencrypt-aws
cd django-on-docker-letsencrypt-aws

Docker Compose
When the app is deployed for the first time, you should follow these two steps to avoid issues with certificates:

Start by issuing the certificates from Let's Encrypt's staging environment
Then, when all is running as expected, switch to Let's Encrypt's production environment

For the web and nginx-proxy services, update the image properties to use images from ECR (which we'll add shortly).

Examples:

image: 123456789.dkr.ecr.us-east-1.amazonaws.com/django-ec2:web

image: 123456789.dkr.ecr.us-east-1.amazonaws.com/django-ec2:nginx-proxy
The values consist of the repository URL (123456789.dkr.ecr.us-east-1.amazonaws.com) along with the image name (django-ec2) and tags (web and nginx-proxy).

To keep things simple we're using a single registry to store both images. We used the web and nginx-proxy to differentiate between the two. Ideally, you should use two registries: one for web and one for nginx-proxy. Update this on your own if you'd like it.

Other than the image properties, we also removed the db service (and related volume) since we'll use RDS rather than managing Postgres in a container.

Notes:

Change <YOUR_DOMAIN.COM> to your actual domain
Change SQL_PASSWORD and SQL_HOST to match those created in the RDS section
Change SECRET_KEY to some long random string
The VIRTUAL_HOST and VIRTUAL_PORT are needed by nginx-proxy container to auto create the reverse proxy configuration
LETSENCRYPT_HOST is there so the nginx-proxy-companion can issue Let's Encrypt certificate for your domain.

For testing/debugging purposes you may want to use a * for DJANGO_ALLOWED_HOSTS the first time you deploy to simplify things. Just don't forget to limit the allowed hosts once testing is complete.

Second, add an .env.staging.proxy-companion file, making sure to update the DEFAULT_EMAIL value:

Build and Push Docker Images

Now we're ready to build the Docker images:

$ docker-compose -f docker-compose.staging.yml build
It may take a few minutes to build. Once done, we're ready to push the images up to ECR.

aws ecr get-login-password --region <aws-region> | docker login --username AWS --password-stdin <aws-account-id>.dkr.ecr.<aws-region>.amazonaws.com
# aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 123456789.dkr.ecr.us-east-1.amazonaws.com

Then push the images to ECR:

$ docker-compose -f docker-compose.staging.yml push
Open your django-ec2 ECR repository to see the pushed images:
You should see two images

Running the Containers
Everything is set up for deployment.

It's time to move to your EC2 instance.

Assuming you have a project directory created on your instance, like /home/ubuntu/django-on-docker, copy the files and folders over with SCP:

scp -i /path/to/your/djangoletsencrypt.pem \
      -r $(pwd)/{app,nginx,.env.staging,.env.staging.proxy-companion,docker-compose.staging.yml} \
      ubuntu@public-ip-or-domain-of-ec2-instance:/path/to/django-on-docker

Next, connect to your instance via SSH and move to the project directory:

$ ssh -i /path/to/your/djangoletsencrypt.pem ubuntu@public-ip-or-domain-of-ec2-instance
$ cd /path/to/django-on-docker

Login to ECR Docker repository.

$ aws ecr get-login-password --region <aws-region> | docker login --username AWS --password-stdin <aws-account-id>.dkr.ecr.<aws-region>.amazonaws.com

Pull the images:

$ docker pull <aws-account-id>.dkr.ecr.<aws-region>.amazonaws.com/django-ec2:web
$ docker pull <aws-account-id>.dkr.ecr.<aws-region>.amazonaws.com/django-ec2:nginx-proxy

With that, you're ready to spin up the containers:

$ docker-compose -f docker-compose.staging.yml up -d

Once the containers are up and running, navigate to your domain in your browser. You should see something like:

Your connection is private
This is expected. This screen is shown because the certificate was issued from a staging environment.

How do you know if everything works?

Click on "Advanced" and then on "Proceed". You should now see your app. Upload an image, and then make sure you can view the image at https://yourdomain.com/mediafiles/IMAGE_FILE_NAME.

Issue the Production Certificate
Now, that everything works as expected, we can switch over to Let's Encrypt's production environment.

Bring down the existing containers and exit your instance:

$ docker-compose -f docker-compose.staging.yml down -v
$ exit

Back on your local machine, open docker-compose.prod.yml and make the same changes that you did for the staging version:

Update the ìmage properties to match your AWS ECR URLs for the ẁeb and nginx-proxy services
Remove the db service along with the related volume

Next create an .env.prod file by duplicating the .env.staging file. You don't need to make any changes to it.

docker-compose -f docker-compose.prod.yml build
$ aws ecr get-login-password --region <aws-region> | docker login --username AWS --password-stdin <aws-account-id>.dkr.ecr.<aws-region>.amazonaws.com
$ docker-compose -f docker-compose.prod.yml push

Copy the new files and folders to your instance with SCP:

$ scp -i /path/to/your/djangoletsencrypt.pem \
      $(pwd)/{.env.prod,.env.prod.proxy-companion,docker-compose.prod.yml} \
      ubuntu@public-ip-or-domain-of-ec2-instance:/path/to/django-on-docker

ssh -i /path/to/your/djangoletsencrypt.pem ubuntu@public-ip-or-domain-of-ec2-instance
$ cd /path/to/django-on-docker

Log in to your ECR Docker repository again:

$ aws ecr get-login-password --region <aws-region> | docker login --username AWS --password-stdin <aws-account-id>.dkr.ecr.<aws-region>.amazonaws.com

Pull the images:

$ docker pull <aws-account-id>.dkr.ecr.<aws-region>.amazonaws.com/django-ec2:web
$ docker pull <aws-account-id>.dkr.ecr.<aws-region>.amazonaws.com/django-ec2:nginx-proxy

And finally spin up the containers:

$ docker-compose -f docker-compose.prod.yml up -d    

Navigate to your domain again. You should no longer see a warning.

Congrats! You're now using a production Let's Encrypt certificate for your Django application running on AWS EC2.        



