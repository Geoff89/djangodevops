This is a step-by-step tutorial that details how to configure Django to run on Docker with Postgres. For production environments, we'll add on Nginx and Gunicorn. We'll also take a look at how to serve Django static and media files via Nginx.

Dependencies:

Django v3.0.7
Docker v19.03.8
Python v3.8.3

--using
Docker
Postgres
Gunicorn
Production Dockerfile
Nginx
Static Files
Media Files

PYTHONDONTWRITEBYTECODE: Prevents Python from writing pyc files to disc (equivalent to python -B option)
PYTHONUNBUFFERED: Prevents Python from buffering stdout and stderr (equivalent to python -u option)

-when  creating docker files, environment and docker-compose we will create for both development and production
--spinning up django image and db container the follwing comanda apply
docker-compose up -d --build
docker-compose exec web python manage.py migrate --noinput

if you get the following error
django.db.utils.OperationalError: FATAL:  database "hello_django_dev" does not exist

Run docker-compose down -v to remove the volumes along with the containers. Then, re-build the images, run the containers, and apply the migrations

Ensure the default Django tables were created:
docker-compose exec db psql --username=hello_django --dbname=hello_django_dev

hello_django_dev=# \c hello_django_dev
hello_django_dev=# \dt
hello_django_dev=# \q

You can check that the volume was created as well by running:
docker volume inspect django-on-docker_postgres_data

Next, add an entrypoint.sh file to the "app" directory to verify that Postgres is healthy before applying the migrations and running the Django development server:

entrypoint.sh
#!/bin/sh

if [ "$DATABASE" = "postgres" ]
then
    echo "Waiting for postgres..."

    while ! nc -z $SQL_HOST $SQL_PORT; do
      sleep 0.1
    done

    echo "PostgreSQL started"
fi

python manage.py flush --no-input
python manage.py migrate

exec "$@"

chmod +x app/entrypoint.sh

Then, update the Dockerfile to copy over the entrypoint.sh file and run it as the Docker entrypoint command:
# pull official base image
FROM python:3.8.3-alpine

# set work directory
WORKDIR /usr/src/app

# set environment variables
ENV PYTHONDONTWRITEBYTECODE 1
ENV PYTHONUNBUFFERED 1

# install psycopg2 dependencies
RUN apk update \
    && apk add postgresql-dev gcc python3-dev musl-dev

# install dependencies
RUN pip install --upgrade pip
COPY ./requirements.txt .
RUN pip install -r requirements.txt

Add the DATABASE environment variable to .env.dev:

DATABASE=postgres

Test it out again:

Re-build the images
Run the containers
Try http://localhost:8000/


# copy entrypoint.sh
COPY ./entrypoint.sh .

# copy project
COPY . .

# run entrypoint.sh
ENTRYPOINT ["/usr/src/app/entrypoint.sh"]

 we can still create an independent Docker image for Django as long as the DATABASE environment variable is not set to postgres. To test, build a new image and then run a new container:
 docker build -f ./app/Dockerfile -t hello_django:latest ./app
 docker run -d \
    -p 8006:8000 \
    -e "SECRET_KEY=please_change_me" -e "DEBUG=1" -e "DJANGO_ALLOWED_HOSTS=*" \
    hello_django python /usr/src/app/manage.py runserver 0.0.0.0:8000

Second, you may want to comment out the database flush and migrate commands in the entrypoint.sh script so they don't run on every container start or re-start:    
#!/bin/sh

if [ "$DATABASE" = "postgres" ]
then
    echo "Waiting for postgres..."

    while ! nc -z $SQL_HOST $SQL_PORT; do
      sleep 0.1
    done

    echo "PostgreSQL started"
fi

# python manage.py flush --no-input
# python manage.py migrate

exec "$@"

--Then run them manually after the containers spin up, like so
docker-compose exec web python manage.py flush --no-input
docker-compose exec web python manage.py migrate

Gunicorn
Moving along, for production environments, let's add Gunicorn, a production-grade WSGI server, to the requirements file:

Django==3.0.7
gunicorn==20.0.4
psycopg2-binary==2.8.5

Since we still want to use Django's built-in server in development, create a new compose file called docker-compose.prod.yml for production

version: '3.7'

services:
  web:
    build: ./app
    command: gunicorn hello_django.wsgi:application --bind 0.0.0.0:8000
    ports:
      - 8000:8000
    env_file:
      - ./.env.prod
    depends_on:
      - db
  db:
    image: postgres:12.0-alpine
    volumes:
      - postgres_data:/var/lib/postgresql/data/
    env_file:
      - ./.env.prod.db

volumes:
  postgres_data:

We're running Gunicorn rather than the Django development server. We also removed the volume from the web service since we don't need it in production. Finally, we're using separate environment variable files to define environment variables for both services that will be passed to the container at runtime.

Add the two files to the project root. You'll probably want to keep them out of version control, so add them to a .gitignore file.i.e .env.prod and .env.prod.db
.env.prod:

DEBUG=0
SECRET_KEY=change_me
DJANGO_ALLOWED_HOSTS=localhost 127.0.0.1 [::1]
SQL_ENGINE=django.db.backends.postgresql
SQL_DATABASE=hello_django_prod
SQL_USER=hello_django
SQL_PASSWORD=hello_django
SQL_HOST=db
SQL_PORT=5432
DATABASE=postgresq  

.env.prod.db:

POSTGRES_USER=hello_django
POSTGRES_PASSWORD=hello_django
POSTGRES_DB=hello_django_prod


Bring down the development containers (and the associated volumes with the -v flag):
docker-compose down -v
--then run the production images and spin up the containers
docker-compose -f docker-compose.prod.yml up -d --build

Verify that the hello_django_prod database was created along with the default Django tables. Test out the admin page at http://localhost:8000/admin. The static files are not being loaded anymore. This is expected since Debug mode is off. We'll fix this shortly.



Did you notice that we're still running the database flush (which clears out the database) and migrate commands every time the container is run? This is fine in development, but let's create a new entrypoint file for production.

entrypoint.prod.sh:

#!/bin/sh

if [ "$DATABASE" = "postgres" ]
then
    echo "Waiting for postgres..."

    while ! nc -z $SQL_HOST $SQL_PORT; do
      sleep 0.1
    done

    echo "PostgreSQL started"
fi

exec "$@"


update the file permissions locally:

$ chmod +x app/entrypoint.prod.sh


$ docker-compose down -v

build the production images and spin up the containers:

docker-compose -f docker-compose.prod.yml up -d --build

Verify that the hello_django_prod database was created along with the default Django tables. Test out the admin page at http://localhost:8000/admin. The static files are not being loaded anymore. This is expected since Debug mode is off

docker-compose -f docker-compose.prod.yml logs -f check if container fails to start 
create a new Dockerfile called Dockerfile.prod for use with production builds

Production Dockerfile
###########
# BUILDER #
###########

# pull official base image
FROM python:3.8.3-alpine as builder

# set work directory
WORKDIR /usr/src/app

# set environment variables
ENV PYTHONDONTWRITEBYTECODE 1
ENV PYTHONUNBUFFERED 1

# install psycopg2 dependencies
RUN apk update \
    && apk add postgresql-dev gcc python3-dev musl-dev

# lint
RUN pip install --upgrade pip
RUN pip install flake8
COPY . .
RUN flake8 --ignore=E501,F401 .

# install dependencies
COPY ./requirements.txt .
RUN pip wheel --no-cache-dir --no-deps --wheel-dir /usr/src/app/wheels -r requirements.txt


#########
# FINAL #
#########

# pull official base image
FROM python:3.8.3-alpine

# create directory for the app user
RUN mkdir -p /home/app

# create the app user
RUN addgroup -S app && adduser -S app -G app

# create the appropriate directories
ENV HOME=/home/app
ENV APP_HOME=/home/app/web
RUN mkdir $APP_HOME
WORKDIR $APP_HOME

# install dependencies
RUN apk update && apk add libpq
COPY --from=builder /usr/src/app/wheels /wheels
COPY --from=builder /usr/src/app/requirements.txt .
RUN pip install --no-cache /wheels/*

# copy entrypoint-prod.sh
COPY ./entrypoint.prod.sh $APP_HOME

# copy project
COPY . $APP_HOME

# chown all the files to the app user
RUN chown -R app:app $APP_HOME

# change to the app user
USER app

# run entrypoint.prod.sh
ENTRYPOINT ["/home/app/web/entrypoint.prod.sh"]

Here, we used a Docker multi-stage build to reduce the final image size. Essentially, builder is a temporary image that's used for building the Python wheels. The wheels are then copied over to the final production image and the builder image is discarded.

Did you notice that we created a non-root user? By default, Docker runs container processes as root inside of a container. This is a bad practice since attackers can gain root access to the Docker host if they manage to break out of the container. If you're root in the container, you'll be root on the host.

Update the web service within the docker-compose.prod.yml file to build with Dockerfile.prod:

web:
  build:
    context: ./app
    dockerfile: Dockerfile.prod
  command: gunicorn hello_django.wsgi:application --bind 0.0.0.0:8000
  ports:
    - 8000:8000
  env_file:
    - ./.env.prod
  depends_on:
    - db

docker-compose -f docker-compose.prod.yml down -v
docker-compose -f docker-compose.prod.yml up -d --build
docker-compose -f docker-compose.prod.yml exec web python manage.py migrate --noinput

Nginx
Next, let's add Nginx into the mix to act as a reverse proxy for Gunicorn to handle client requests as well as serve up static files.

Add the service to docker-compose.prod.yml:

nginx:
  build: ./nginx
  ports:
    - 1337:80
  depends_on:
    - web
then, in the local project root, create the following files and folders:

└── nginx
    ├── Dockerfile
    └── nginx.conf

Dockerfile:

FROM nginx:1.19.0-alpine

RUN rm /etc/nginx/conf.d/default.conf
COPY nginx.conf /etc/nginx/conf.d

upstream hello_django {
    server web:8000;
}

server {

    listen 80;

    location / {
        proxy_pass http://hello_django;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Host $host;
        proxy_redirect off;
    }

}    

Then, update the web service, in docker-compose.prod.yml, replacing ports with expose:

web:
  build:
    context: ./app
    dockerfile: Dockerfile.prod
  command: gunicorn hello_django.wsgi:application --bind 0.0.0.0:8000
  expose:
    - 8000
  env_file:
    - ./.env.prod
  depends_on:
    - db

Now, port 8000 is only exposed internally, to other Docker services. The port will no longer be published to the host machine.

docker-compose -f docker-compose.prod.yml down -v
$ docker-compose -f docker-compose.prod.yml up -d --build
$ docker-compose -f docker-compose.prod.yml exec web python manage.py migrate --noinput

Ensure the app is up and running at http://localhost:1337.

project structure looks like this

├── .env.dev
├── .env.prod
├── .env.prod.db
├── .gitignore
├── app
│   ├── Dockerfile
│   ├── Dockerfile.prod
│   ├── entrypoint.prod.sh
│   ├── entrypoint.sh
│   ├── hello_django
│   │   ├── __init__.py
│   │   ├── asgi.py
│   │   ├── settings.py
│   │   ├── urls.py
│   │   └── wsgi.py
│   ├── manage.py
│   └── requirements.txt
├── docker-compose.prod.yml
├── docker-compose.yml
└── nginx
    ├── Dockerfile
    └── nginx.conf    


Bring the containers down once done:

$ docker-compose -f docker-compose.prod.yml down -v 

Since Gunicorn is an application server, it will not serve up static files. So, how should both static and media files be handled in this particular configuration? 

Static Files
Update settings.py:

STATIC_URL = "/staticfiles/"
STATIC_ROOT = os.path.join(BASE_DIR, "staticfiles")

Development
Now, any request to http://localhost:8000/staticfiles/* will be served from the "staticfiles" directory.

To test, first re-build the images and spin up the new containers per usual. Ensure static files are still being served correctly at http://localhost:8000/admin.

Production
For production, add a volume to the web and nginx services in docker-compose.prod.yml so that each container will share a directory named "staticfiles":

version: '3.7'

services:
  web:
    build:
      context: ./app
      dockerfile: Dockerfile.prod
    command: gunicorn hello_django.wsgi:application --bind 0.0.0.0:8000
    volumes:
      - static_volume:/home/app/web/staticfiles
    expose:
      - 8000
    env_file:
      - ./.env.prod
    depends_on:
      - db
  db:
    image: postgres:12.0-alpine
    volumes:
      - postgres_data:/var/lib/postgresql/data/
    env_file:
      - ./.env.prod.db
  nginx:
    build: ./nginx
    volumes:
      - static_volume:/home/app/web/staticfiles
    ports:
      - 1337:80
    depends_on:
      - web

volumes:
  postgres_data:
  static_volume:

We need to also create the "/home/app/web/staticfiles" folder in Dockerfile.prod:

# create the appropriate directories
ENV HOME=/home/app
ENV APP_HOME=/home/app/web
RUN mkdir $APP_HOME
RUN mkdir $APP_HOME/staticfiles
WORKDIR $APP_HOME


Why is this necessary?

Docker Compose normally mounts named volumes as root. And since we're using a non-root user, we'll get a permission denied error when the collectstatic command is run if the directory does not already exist

To get around this, you can either:

Create the folder in the Dockerfile (source)
Change the permissions of the directory after it's mounted (source)
We used the former.

Next, update the Nginx configuration to route static file requests to the "staticfiles" folder:

upstream hello_django {
    server web:8000;
}

server {

    listen 80;

    location / {
        proxy_pass http://hello_django;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Host $host;
        proxy_redirect off;
    }

    location /staticfiles/ {
        alias /home/app/web/staticfiles/;
    }

}

Spin down the development containers:

$ docker-compose down -v

docker-compose -f docker-compose.prod.yml up -d --build
$ docker-compose -f docker-compose.prod.yml exec web python manage.py migrate --noinput
$ docker-compose -f docker-compose.prod.yml exec web python manage.py collectstatic --no-input --clear

Again, requests to http://localhost:1337/staticfiles/* will be served from the "staticfiles" directory.

Navigate to http://localhost:1337/admin and ensure the static assets load correctly.

You can also verify in the logs -- via docker-compose -f docker-compose.prod.yml logs -f -- that requests to the static files are served up successfully via Nginx:

logs -- via 
docker-compose -f docker-compose.prod.yml logs -f -- that requests to the static files are served up successfully via Nginx:

MEDIA FILES
to test out the handling of media files, start by creating a new Django app:
docker-compose up -d --build
docker-compose exec web python manage.py startapp upload  

Add the new app to the INSTALLED_APPS list in settings.py:
app/upload/views.py:

from django.shortcuts import render
from django.core.files.storage import FileSystemStorage


def image_upload(request):
    if request.method == "POST" and request.FILES["image_file"]:
        image_file = request.FILES["image_file"]
        fs = FileSystemStorage()
        filename = fs.save(image_file.name, image_file)
        image_url = fs.url(filename)
        print(image_url)
        return render(request, "upload.html", {
            "image_url": image_url
        })
    return render(request, "upload.html")

Add a "templates", directory to the "app/upload" directory, and then add a new template called upload.html:

% block content %}

  <form action="{% url "upload" %}" method="post" enctype="multipart/form-data">
    {% csrf_token %}
    <input type="file" name="image_file">
    <input type="submit" value="submit" />
  </form>

  {% if image_url %}
    <p>File uploaded at: <a href="{{ image_url }}">{{ image_url }}</a></p>
  {% endif %}

{% endblock %}

app/hello_django/urls.py:

from django.contrib import admin
from django.urls import path
from django.conf import settings
from django.conf.urls.static import static

from upload.views import image_upload

urlpatterns = [
    path("", image_upload, name="upload"),
    path("admin/", admin.site.urls),
]

if bool(settings.DEBUG):
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)

app/hello_django/settings.py:

MEDIA_URL = "/mediafiles/"
MEDIA_ROOT = os.path.join(BASE_DIR, "mediafiles")

Development
Test:

$ docker-compose up -d --build
You should be able to upload an image at http://localhost:8000/, and then view the image at http://localhost:8000/mediafiles/IMAGE_FILE_NAME.

Production
For production, add another volume to the web and nginx services:

version: '3.7'

services:
  web:
    build:
      context: ./app
      dockerfile: Dockerfile.prod
    command: gunicorn hello_django.wsgi:application --bind 0.0.0.0:8000
    volumes:
      - static_volume:/home/app/web/staticfiles
      - media_volume:/home/app/web/mediafiles
    expose:
      - 8000
    env_file:
      - ./.env.prod
    depends_on:
      - db
  db:
    image: postgres:12.0-alpine
    volumes:
      - postgres_data:/var/lib/postgresql/data/
    env_file:
      - ./.env.prod.db
  nginx:
    build: ./nginx
    volumes:
      - static_volume:/home/app/web/staticfiles
      - media_volume:/home/app/web/mediafiles
    ports:
      - 1337:80
    depends_on:
      - web

volumes:
  postgres_data:
  static_volume:
  media_volume:

  Create the "/home/app/web/mediafiles" folder in Dockerfile.prod:

...

# create the appropriate directories
ENV HOME=/home/app
ENV APP_HOME=/home/app/web
RUN mkdir $APP_HOME
RUN mkdir $APP_HOME/staticfiles
RUN mkdir $APP_HOME/mediafiles
WORKDIR $APP_HOME

pdate the Nginx config again:

upstream hello_django {
    server web:8000;
}

server {

    listen 80;

    location / {
        proxy_pass http://hello_django;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Host $host;
        proxy_redirect off;
    }

    location /staticfiles/ {
        alias /home/app/web/staticfiles/;
    }

    location /mediafiles/ {
        alias /home/app/web/mediafiles/;
    }

}

docker-compose down -v

$ docker-compose -f docker-compose.prod.yml up -d --build
$ docker-compose -f docker-compose.prod.yml exec web python manage.py migrate --noinput
$ docker-compose -f docker-compose.prod.yml exec web python manage.py collectstatic --no-input --clear

Test it out one final time:

Upload an image at http://localhost:1337/.
Then, view the image at http://localhost:1337/mediafiles/IMAGE_FILE_NAME.

If you see an 413 Request Entity Too Large error, you'll need to increase the maximum allowed size of the client request body in either the server or location context within the Nginx config.

location / {
    proxy_pass http://hello_django;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header Host $host;
    proxy_redirect off;
    client_max_body_size 100M;
}

n terms of actual deployment to a production environment, you'll probably want to use a:

Fully managed database service -- like RDS or Cloud SQL -- rather than managing your own Postgres instance within a container.
Non-root user for the db and nginx services

 The app has to be run inside a container 
docker-compose up -d --build
docker-compose exec web python manage.py startapp upload
add the necessary setting in the app which is in the docker environment





