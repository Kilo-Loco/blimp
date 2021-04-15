FROM swift:5.2-xenial

ENV PORT=8080
EXPOSE 8080

WORKDIR /app

COPY . ./

RUN apt-get update
RUN apt-get install -y zip unzip

CMD swift package clean
CMD swift run
