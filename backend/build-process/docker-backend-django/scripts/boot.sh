#!/bin/bash
set -e

echo "apibackend:boot:env:${APP_ENVIRONMENT}"

python manage.py migrate
python manage.py collectstatic --noinput

echo "agentloop-backend:run:prod" && /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisor-backend.conf
