'use strict';
const { PubSub } = require('@google-cloud/pubsub');
const { v1 } = require('@google-cloud/pubsub');
const { BigQuery } = require('@google-cloud/bigquery');
const fs = require('fs');

const ackIds = [];
const projectId = process.env.GCP_PROJECT_ID
const subscriptionName = process.env.GCP_PUBSUB_SUBSCRIPTION
const dataset = process.env.GCP_DATASET_NAME
const table = process.env.GCP_TABLE_NAME

const filename = '../data.jsonl'

const subClient = new v1.SubscriberClient();
const bigquery = new BigQuery();
const formattedSubscription = subClient.subscriptionPath(
    projectId,
    subscriptionName
);


let main = async() => {

    let timeout = (1000 * 60) * 8 //9 minutes
    let startTime = Date.now()
    fs.writeFileSync(filename, "")
    let newMessages = false
    while (await pullBatch() > 0) {
        let currentTime = Date.now()
        newMessages = true
        if (currentTime - startTime >= timeout) {
            console.log("timeout exceeded")
            break;
        }
    }

    if (newMessages) await finalLoad()

}

let pullBatch = async() => {

    const request = {
        subscription: formattedSubscription,
        maxMessages: 999,
    };

    const [response] = await subClient.pull(request);

    const msgs = []
    for (const message of response.receivedMessages) {

        var payload = JSON.parse(message.message.data).jsonPayload;

        msgs.push(payload)
        ackIds.push(message.ackId);
    }

    processBatch(msgs)

    return response.receivedMessages.length
}

let processBatch = (messages) => {

    const transferredMessages = []
    for (const message of messages) {
        transferredMessages.push(transfer(message))
    }
    load(transferredMessages)
}

let transfer = (message) => {

    return {
        item: message.item,
        user: message.user,
        type: message.type,
        timestamp: new Date().toISOString()
    }

}

let load = (messages) => {


    var content = ""
    messages.forEach(element => {
        content = content + JSON.stringify(element) + "\n"
    });

    fs.appendFileSync(filename, content)

}

let finalLoad = async() => {
    await loadBatchToBqTable()
    await ackWaitingQueue()
    console.log(`ETL finished its work`)

}

let loadBatchToBqTable = async() => {
    const callback = (err, job, apiResponse) => {};

    const metadata = {
        encoding: 'ISO-8859-1',
        sourceFormat: 'NEWLINE_DELIMITED_JSON',
        writeDisposition: 'WRITE_APPEND',
        autodetect: true,
        timePartitioning: {
            "type": "DAY",
            "field": "timestamp",
            "requirePartitionFilter": false
        }
    };

    bigquery.dataset(dataset).table(table).load(filename, metadata).then((data) => {
        console.log("Data loaded to BQ successfully")
    });
}

let ackWaitingQueue = async() => {

    console.log(`To ack ${ackIds.length} messages`)

    while (ackIds.length) {

        const ackRequest = {
            subscription: formattedSubscription,
            ackIds: ackIds.splice(0, 999),
        };
        await subClient.acknowledge(ackRequest);
    }

    console.log("All msgs acked successfully")

}

module.exports = main;