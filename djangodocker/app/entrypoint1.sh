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
#chmod +x app/entrypoint.sh
#Second, you may want to comment out the database 
#flush and migrate commands in the entrypoint.sh script so they don't run on every container start or re-start:
#docker-compose exec web python manage.py flush --no-input
#docker-compose exec web python manage.py migrate