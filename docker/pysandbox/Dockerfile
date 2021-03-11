FROM python:3
MAINTAINER Dr. Michael Specht <specht@quelltextschmiede.de>

RUN apt-get update && apt-get upgrade -y
RUN apt-get install -y tzdata cpulimit && rm -rf /var/cache/apt/*
RUN cp /usr/share/zoneinfo/Europe/Berlin /etc/localtime && echo "Europe/Berlin" > /etc/timezone
RUN useradd -u 1000 harold
ADD ./killuser.py /killuser.py
RUN pip install pymysql
USER harold
