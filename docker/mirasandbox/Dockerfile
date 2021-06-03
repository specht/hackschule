FROM ubuntu
MAINTAINER Dr. Michael Specht <specht@quelltextschmiede.de>

RUN apt-get update && apt-get upgrade -y
RUN apt-get install -y tzdata wget cpulimit && rm -rf /var/cache/apt/*
RUN cp /usr/share/zoneinfo/Europe/Berlin /etc/localtime && echo "Europe/Berlin" > /etc/timezone
RUN useradd -u 1000 harold
# ADD ./killuser.py /killuser.py
#RUN pip install pymysql numpy ansicolors
RUN wget -O /miranda.tar.gz 'https://www.cs.kent.ac.uk/people/staff/dat/ccount/click.php?id=2'
RUN ls -l /
RUN tar xpzf /miranda.tar.gz -C /
USER harold
