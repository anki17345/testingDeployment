FROM python:3.12-slim

ENV PYTHONUNBUFFERED 1
ENV DJANGO_SETTINGS_MODULE=core.settings
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        git-core \
        build-essential \
        binutils \
        libproj-dev \
        gdal-bin \
        supervisor && \
    rm -rf /var/lib/apt/lists/*

COPY ./backend/requirements /home/apibackend/requirements
RUN mkdir -p /home/apibackend/media
WORKDIR /home/apibackend


RUN pip install --upgrade pip
RUN pip install -r ./requirements/requirements.txt



EXPOSE 8000

RUN mkdir -p /var/logs/apibackend


COPY ./backend/build-process/docker-backend-django/scripts /home/docker/scripts
COPY ./backend/build-process/docker-backend-django/config/supervisor-backend.conf /etc/supervisor/conf.d/supervisor-backend.conf

RUN sed -i 's/\r$//' /home/docker/scripts/boot.sh  && \
        chmod +x /home/docker/scripts/boot.sh



COPY ./backend /home/apibackend

ENTRYPOINT /home/docker/scripts/boot.sh

