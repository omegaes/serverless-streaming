# Serverless Streaming events into BigQuery

This is a demo project to show you how you can use Cloud Run, Stackdriver, Pub/Sub, Cloud Monitoring and BigQuery to accept events from your clients into BigQuery, with no hassle of building a scalable infastructure where all these services are serverless servicess and have a free tier!.

# Used technologies 
- Backend: node.js, express, dotenv, Docker, GCP sdks and Bunyan
- HTTP benchmarking: wrk
- Cloud: gcloud commands and GCP console

# Producer
Clients will generate events and send it to backend, API to receive events considerd as a `Producer` and will send these events to a Queue to store their temporarily, `Producer` will write these events as log messages, each event as a log message, later a sink in `Stackdriver` will send these logs to a `Pub\Sub Topic - Events topic` 

# Consumer
Consumers are jobs running to pull a big batch of events, do an ETL on events and load into BigQuery.
Consumer here built as an API call, it will take around 9 mins to do its work and return 200 response, you can run the job asynchronously to process high load.
The consumer will get triggered from a `Pub/Sub message`, once the job finish its work, it will return 200 success response 

# Build the demo

  - GCP account, you can get free credits once you [signup](https://cloud.google.com/gcp)
  - Install gcloud and login to your account, [gcloud](https://cloud.google.com/sdk/gcloud)
  - Create new GCP project, create/get a project ID
  - ```sh
    git clone git@github.com:omegaes/serverless-streaming.git
    cd serverless-streaming/deploy
    export PROJECT_ID=
    export LOCATION=US
    export REGION=us-east1
    export SERVICE_ACCOUNT_ID=
    export ROLE_ID=roleCloudRun
    export SINK_NAME=events_sink
    export PUBSUB_EVENTS_TOPIC=events_topic
    export PUBSUB_EVENTS_SUB=events_subscription
    export PUBSUB_INVOKE_TOPIC=invoke_topic
    export PUBSUB_INVOKE_SUB=invoke_topic_subscription
    export LOG_NAME=events-service
    export SINK_LOCATION=pubsub.googleapis.com/projects/$PROJECT_ID/topics/$PUBSUB_EVENTS_TOPIC
    export ROLE=projects/$PROJECT_ID/roles/$ROLE_ID
    export DATASET_NAME=test_data
    export TABLE_NAME=events

    ./commands.sh #start building and deploying!
    ```
 - command .sh includes these functions:
    - gcloudConfig: to configure your gcloud CLI with your project and preference
    - buildProducerApiAndDeployToCloudRun: build producer API from api folder, deploy to cloud run
    - buildConsumerApiAndDeployToCloudRun: build consumer API from job folder, deploy to cloud run
    - createPubSubTopicsAndSubscriptions: Build 2 topics and its subscriptions to run this demo
    - createLogsSink: create stackdriver logs sink to redirect from Producer API stdout to Pub/Sub topic
    - createAlertPolicyAndNotificationChannel: create cloud schedlure and alert to trigger Consumer API to process events and do the ETL work
    - testProducerAndConsumer: to run the demo, produce random events from clients' calls, then you can monitor BigQuery after ETL run successfully
    - cleanUpResources: delete all create resources in this example
    
You can refer to my article on Medium to understand how this example works, See [Stream Millions of events from your client to BigQuery in a Serverless way, Part #1](https://medium.com/@abdulrahmanbabil/stream-millions-of-events-from-your-client-to-bigquery-in-a-serverless-way-part-1-a38c4f9cd6e4).


