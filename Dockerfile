FROM swift:5.2-xenial
WORKDIR /app
COPY . ./
RUN apt-get update
RUN apt-get install -y zip unzip
CMD swift package clean
CMD swift run
