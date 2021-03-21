'use strict';

const express = require('express')
const bodyParser = require('body-parser')
const app = express()
app.use(bodyParser.json())
// Constants
const PORT = 8080
const HOST = '0.0.0.0'
const etl = require('./etl');



app.get('/', (req, res) => {
  res.send('Hello World, Again');
});

app.post('/etl', (req, res) => {
   etl()
   .then(function(){
    res.status(200).send({done: true});
   })
   .catch(function(e){
    console.log(e)
    res.status(400).send({error: e});
   })
});

app.listen(PORT, HOST);
console.log(`Running on http://${HOST}:${PORT}`);