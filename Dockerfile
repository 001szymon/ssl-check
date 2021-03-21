FROM ubuntu:16.10
ENV DEBIAN_FRONTEND noninteractive

RUN apt-get -qq update --fix-missing && \
    apt-get --no-install-recommends -y install openssl net-tools dnsutils aha python3 python3-pip && \
    pip3 install --upgrade pip setuptools && \
    pip3 install Flask && \
    apt-get autoremove -y && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

ADD . /sslcheck

RUN mkdir -p /sslcheck/log /sslcheck/result/json /sslcheck/result/html

EXPOSE 5000

WORKDIR /sslcheck
 
CMD python3 SSLCheckPortal.py
