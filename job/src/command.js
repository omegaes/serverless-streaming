'use strict';
const { program } = require('commander');
const etl = require('./etl');
program
.version('0.1.0')
.command('pull')
.action( async function () {
  console.log('start');
  await etl()
  console.log('end');

})
.parse(process.argv);