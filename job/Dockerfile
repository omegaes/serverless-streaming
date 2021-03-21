FROM node:13

# Create app directory
WORKDIR /usr/src


COPY package*.json ./

RUN npm install

WORKDIR /usr/src/app

COPY ./src .

EXPOSE 8080

CMD [ "node", "server.js" ]