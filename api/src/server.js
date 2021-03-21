'use strict';

const express = require('express')
const bodyParser = require('body-parser')
const app = express()
app.use(bodyParser.json())
// Constants
const PORT = 8080
const HOST = '0.0.0.0'

const bunyan = require('bunyan');

//we use this package in case code is running on other cloud providers 
//or stackdriver agent is not installed on the running machine


// const {LoggingBunyan} = require('@google-cloud/logging-bunyan')
// const loggingBunyan = new LoggingBunyan();


const logger = bunyan.createLogger({
  name: 'events-service',
  streams: [
    {stream: process.stdout, level: 'info'},
    //no need to use it when code run on GCP compute services
    //loggingBunyan.stream('info'),
  ],
});

//random values
const types = ["Buy", "AddToCart", "Like", "ScrollToComments", "BrowsePhotos"]
const users = ["U0010", "U0011", "U0012", "U0013", "U0014"]
const items = ["I12300", "I12301", "I12302", "I12304"]

app.get('/', (req, res) => {
  res.send('Hello World');
});

//api to receive JSON array of JSON objects
app.post('/receive', (req, res) => {
  req.body.forEach(event => {
    event.user = users[Math.floor(Math.random() * users.length)]
    event.item = items[Math.floor(Math.random() * items.length)]
    event.type = types[Math.floor(Math.random() * types.length)]
    event.timestamp = Date.now()
    logger.info(event);
  });
  res.status(200).send({done: true});
});

app.listen(PORT, HOST);
console.log(`Running on http://${HOST}:${PORT}`);