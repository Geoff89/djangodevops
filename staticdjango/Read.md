Amazon's Simple Storage System (S3) provides a simple, cost-effective way to store static files. This tutorial shows how to configure Django to load and serve up static and user uploaded media files, public and private, via an Amazon S3 bucket


Step1
create an s3 bucket and unclick all public access

IAM Access
Although you could use the AWS root user, it's best for security to create an IAM user that only has access to S3 or to a specific S3 bucket. What's more, by setting up a group, it makes it much easier to assign (and remove) access to the bucket. So, we'll start by setting up a group with limited permissions and then create a user and assign that user to the group.

IAM Group
Within the AWS Console, navigate to the main IAM page and click "User groups" on the sidebar. Then, click the "Create group" button, provide a name for the group and then search for and select the built-in policy "AmazonS3FullAccess":

If you'd like to limit access even more, to the specific bucket we just created, create a new policy with the following permissions:

{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "s3:*",
            "Resource": [
                "arn:aws:s3:::your-bucket-name",
                "arn:aws:s3:::your-bucket-name/*"
            ]
        }
    ]
}

Create user and attach to the group and take note of the access and secret keys

Django Project
Clone down the django-docker-s3 repo, and then check out the v1 tag to the master branch:

$ git clone https://github.com/testdrivenio/django-docker-s3 --branch v1 --single-branch
$ cd django-docker-s3
$ git checkout tags/v1 -b master

From the project root, create the images and spin up the Docker containers:

$ docker-compose up -d --build
Once the build is complete, collect the static files:

$ docker-compose exec web python manage.py collectstatic

Then, navigate to http://localhost:1337:

You should be able to upload an image, and then view the image at http://localhost:1337/mediafiles/IMAGE_FILE_NAME.

The radio buttons, for public vs. private, do not work. We'll be adding this functionality later in this tutorial. Ignore them for now.

Take a quick look at the project structure before moving on:

├── .gitignore
├── LICENSE
├── README.md
├── app
│   ├── Dockerfile
│   ├── entrypoint.sh
│   ├── hello_django
│   │   ├── __init__.py
│   │   ├── asgi.py
│   │   ├── settings.py
│   │   ├── urls.py
│   │   └── wsgi.py
│   ├── manage.py
│   ├── mediafiles
│   ├── requirements.txt
│   ├── static
│   │   └── bulma.min.css
│   ├── staticfiles
│   └── upload
│       ├── __init__.py
│       ├── admin.py
│       ├── apps.py
│       ├── migrations
│       │   └── __init__.py
│       ├── models.py
│       ├── templates
│       │   └── upload.html
│       ├── tests.py
│       └── views.py
├── docker-compose.yml
└── nginx
    ├── Dockerfile
    └── nginx.conf

Django Storages
Next, install django-storages, to use S3 as the main Django storage backend, and boto3, to interact with the AWS API.

Update the requirements file:

boto3==1.17.58
Django==3.2
django-storages==1.11.1
gunicorn==20.1.0   


Add storages to the INSTALLED_APPS in settings.py:

INSTALLED_APPS = [
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',
    'upload',
    'storages',
]
Update the images and spin up the new containers:

Static Files
Moving along, we need to update the handling of static files in settings.py:

STATIC_URL = '/staticfiles/'
STATIC_ROOT = os.path.join(BASE_DIR, 'staticfiles')
STATICFILES_DIRS = (os.path.join(BASE_DIR, 'static'),)


MEDIA_URL = '/mediafiles/'
MEDIA_ROOT = os.path.join(BASE_DIR, 'mediafiles')

Replace those settings with the following:

USE_S3 = os.getenv('USE_S3') == 'TRUE'

if USE_S3:
    # aws settings
    AWS_ACCESS_KEY_ID = os.getenv('AWS_ACCESS_KEY_ID')
    AWS_SECRET_ACCESS_KEY = os.getenv('AWS_SECRET_ACCESS_KEY')
    AWS_STORAGE_BUCKET_NAME = os.getenv('AWS_STORAGE_BUCKET_NAME')
    AWS_DEFAULT_ACL = 'public-read'
    AWS_S3_CUSTOM_DOMAIN = f'{AWS_STORAGE_BUCKET_NAME}.s3.amazonaws.com'
    AWS_S3_OBJECT_PARAMETERS = {'CacheControl': 'max-age=86400'}
    # s3 static settings
    AWS_LOCATION = 'static'
    STATIC_URL = f'https://{AWS_S3_CUSTOM_DOMAIN}/{AWS_LOCATION}/'
    STATICFILES_STORAGE = 'storages.backends.s3boto3.S3Boto3Storage'
else:
    STATIC_URL = '/staticfiles/'
    STATIC_ROOT = os.path.join(BASE_DIR, 'staticfiles')

STATICFILES_DIRS = (os.path.join(BASE_DIR, 'static'),)

MEDIA_URL = '/mediafiles/'
MEDIA_ROOT = os.path.join(BASE_DIR, 'mediafiles')

$ docker-compose up -d --build 

ake note of USE_S3 and STATICFILES_STORAGE:

The USE_S3 environment variable is used to turn the S3 storage on (value is TRUE) and off (value is FALSE). So, you could configure two Docker compose files: one for development with S3 off and the other for production with S3 on.
The STATICFILES_STORAGE setting configures Django to automatically add static files to the S3 bucket when the collectstatic command is run.

Add the appropriate environment variables to the web service in the docker-compose.yml file:

web:
  build: ./app
  command: bash -c 'while !</dev/tcp/db/5432; do sleep 1; done; gunicorn hello_django.wsgi:application --bind 0.0.0.0:8000'
  volumes:
    - ./app/:/usr/src/app/
    - static_volume:/usr/src/app/staticfiles
    - media_volume:/usr/src/app/mediafiles
  expose:
    - 8000
  environment:
    - SECRET_KEY=please_change_me
    - SQL_ENGINE=django.db.backends.postgresql
    - SQL_DATABASE=postgres
    - SQL_USER=postgres
    - SQL_PASSWORD=postgres
    - SQL_HOST=db
    - SQL_PORT=5432
    - DATABASE=postgres
    - USE_S3=TRUE
    - AWS_ACCESS_KEY_ID=UPDATE_ME
    - AWS_SECRET_ACCESS_KEY=UPDATE_ME
    - AWS_STORAGE_BUCKET_NAME=UPDATE_ME
  depends_on:
    - db

 Don't forget to update AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY with the user keys that you just created along with the AWS_STORAGE_BUCKET_NAME.

To test, re-build and run the containers:

$ docker-compose down -v
$ docker-compose up -d --build   

Collect the static files:

$ docker-compose exec web python manage.py collectstatic

It should take much longer than before since the files are being uploaded to the S3 bucket.

http://localhost:1337 should still render correctly:

View the page source to ensure the CSS stylesheet is pulled in from the S3 bucket:

Verify that the static files can be seen on the AWS console within the "static" subfolder of the S3 bucket:

Media uploads will still hit the local filesystem since we've only configured S3 for static files. We'll work with media uploads shortly.

Finally, update the value of USE_S3 to FALSE and re-build the images to make sure that Django uses the local filesystem for static files. Once done, change USE_S3 back to TRUE.

Public Media Files
To prevent users from overwriting existing static files, media file uploads should be placed in a different subfolder in the bucket. We'll handle this by creating custom storage classes for each type of storage.

Add a new file called storage_backends.py to the "app/hello_django" folder:

from django.conf import settings
from storages.backends.s3boto3 import S3Boto3Storage


class StaticStorage(S3Boto3Storage):
    location = 'static'
    default_acl = 'public-read'


class PublicMediaStorage(S3Boto3Storage):
    location = 'media'
    default_acl = 'public-read'
    file_overwrite = False
Make the following changes to settings.py:

USE_S3 = os.getenv('USE_S3') == 'TRUE'

if USE_S3:
    # aws settings
    AWS_ACCESS_KEY_ID = os.getenv('AWS_ACCESS_KEY_ID')
    AWS_SECRET_ACCESS_KEY = os.getenv('AWS_SECRET_ACCESS_KEY')
    AWS_STORAGE_BUCKET_NAME = os.getenv('AWS_STORAGE_BUCKET_NAME')
    AWS_DEFAULT_ACL = None
    AWS_S3_CUSTOM_DOMAIN = f'{AWS_STORAGE_BUCKET_NAME}.s3.amazonaws.com'
    AWS_S3_OBJECT_PARAMETERS = {'CacheControl': 'max-age=86400'}
    # s3 static settings
    STATIC_LOCATION = 'static'
    STATIC_URL = f'https://{AWS_S3_CUSTOM_DOMAIN}/{STATIC_LOCATION}/'
    STATICFILES_STORAGE = 'hello_django.storage_backends.StaticStorage'
    # s3 public media settings
    PUBLIC_MEDIA_LOCATION = 'media'
    MEDIA_URL = f'https://{AWS_S3_CUSTOM_DOMAIN}/{PUBLIC_MEDIA_LOCATION}/'
    DEFAULT_FILE_STORAGE = 'hello_django.storage_backends.PublicMediaStorage'
else:
    STATIC_URL = '/staticfiles/'
    STATIC_ROOT = os.path.join(BASE_DIR, 'staticfiles')
    MEDIA_URL = '/mediafiles/'
    MEDIA_ROOT = os.path.join(BASE_DIR, 'mediafiles')

STATICFILES_DIRS = (os.path.join(BASE_DIR, 'static'),)


With the DEFAULT_FILE_STORAGE setting now set, all FileFields will upload their content to the S3 bucket. Review the remaining settings before moving on.

Next, let's make a few changes to the upload app.

app/upload/models.py:

from django.db import models


class Upload(models.Model):
    uploaded_at = models.DateTimeField(auto_now_add=True)
    file = models.FileField()

app/upload/views.py:

from django.conf import settings
from django.core.files.storage import FileSystemStorage
from django.shortcuts import render

from .models import Upload


def image_upload(request):
    if request.method == 'POST':
        image_file = request.FILES['image_file']
        image_type = request.POST['image_type']
        if settings.USE_S3:
            upload = Upload(file=image_file)
            upload.save()
            image_url = upload.file.url
        else:
            fs = FileSystemStorage()
            filename = fs.save(image_file.name, image_file)
            image_url = fs.url(filename)
        return render(request, 'upload.html', {
            'image_url': image_url
        })
    return render(request, 'upload.html')

Create the new migration file and then build the new images:

$ docker-compose exec web python manage.py makemigrations
$ docker-compose down -v
$ docker-compose up -d --build
$ docker-compose exec web python manage.py migrate

Test it out! Upload an image at http://localhost:1337. The image should be uploaded to S3 (to the media subfolder) and the image_url should include the S3 url:

Private Media Files
Add a new class to the storage_backends.py:

class PrivateMediaStorage(S3Boto3Storage):
    location = 'private'
    default_acl = 'private'
    file_overwrite = False
    custom_domain = False
Add the appropriate settings:

USE_S3 = os.getenv('USE_S3') == 'TRUE'

if USE_S3:
    # aws settings
    AWS_ACCESS_KEY_ID = os.getenv('AWS_ACCESS_KEY_ID')
    AWS_SECRET_ACCESS_KEY = os.getenv('AWS_SECRET_ACCESS_KEY')
    AWS_STORAGE_BUCKET_NAME = os.getenv('AWS_STORAGE_BUCKET_NAME')
    AWS_DEFAULT_ACL = None
    AWS_S3_CUSTOM_DOMAIN = f'{AWS_STORAGE_BUCKET_NAME}.s3.amazonaws.com'
    AWS_S3_OBJECT_PARAMETERS = {'CacheControl': 'max-age=86400'}
    # s3 static settings
    STATIC_LOCATION = 'static'
    STATIC_URL = f'https://{AWS_S3_CUSTOM_DOMAIN}/{STATIC_LOCATION}/'
    STATICFILES_STORAGE = 'hello_django.storage_backends.StaticStorage'
    # s3 public media settings
    PUBLIC_MEDIA_LOCATION = 'media'
    MEDIA_URL = f'https://{AWS_S3_CUSTOM_DOMAIN}/{PUBLIC_MEDIA_LOCATION}/'
    DEFAULT_FILE_STORAGE = 'hello_django.storage_backends.PublicMediaStorage'
    # s3 private media settings
    PRIVATE_MEDIA_LOCATION = 'private'
    PRIVATE_FILE_STORAGE = 'hello_django.storage_backends.PrivateMediaStorage'
else:
    STATIC_URL = '/staticfiles/'
    STATIC_ROOT = os.path.join(BASE_DIR, 'staticfiles')
    MEDIA_URL = '/mediafiles/'
    MEDIA_ROOT = os.path.join(BASE_DIR, 'mediafiles')

STATICFILES_DIRS = (os.path.join(BASE_DIR, 'static'),)

Create a new model in app/upload/models.py:

from django.db import models

from hello_django.storage_backends import PublicMediaStorage, PrivateMediaStorage


class Upload(models.Model):
    uploaded_at = models.DateTimeField(auto_now_add=True)
    file = models.FileField(storage=PublicMediaStorage())


class UploadPrivate(models.Model):
    uploaded_at = models.DateTimeField(auto_now_add=True)
    file = models.FileField(storage=PrivateMediaStorage())
Then, update the view:

from django.conf import settings
from django.core.files.storage import FileSystemStorage
from django.shortcuts import render

from .models import Upload, UploadPrivate


def image_upload(request):
    if request.method == 'POST':
        image_file = request.FILES['image_file']
        image_type = request.POST['image_type']
        if settings.USE_S3:
            if image_type == 'private':
                upload = UploadPrivate(file=image_file)
            else:
                upload = Upload(file=image_file)
            upload.save()
            image_url = upload.file.url
        else:
            fs = FileSystemStorage()
            filename = fs.save(image_file.name, image_file)
            image_url = fs.url(filename)
        return render(request, 'upload.html', {
            'image_url': image_url
        })
    return render(request, 'upload.html')
Again, create the migration file, re-build the images, and spin up the new containers:

$ docker-compose exec web python manage.py makemigrations
$ docker-compose down -v
$ docker-compose up -d --build
$ docker-compose exec web python manage.py migrate

o test, upload a private image at http://localhost:1337. Like a public image, the image should be uploaded to S3 (to the private subfolder) and the image_url should include the S3 URL along with the following query string parameters:

AWSAccessKeyId
Signature
Expires
Essentially, we created a temporary, signed URL that users can access for a specific period of time. You won't be able to access it directly, without theparameters.

Conclusion
This post walked you through how to create a bucket on Amazon S3, configure an IAM user and group, and set up Django to upload and serve static files and media uploads to and from S3.

By using S3, you:

Increase the amount of space you have available for static and media files
Decrease the stress on your own server since it no longer has to serve up the files
Can limit access to specific files
Can take advantage of the CloudFront CDN






