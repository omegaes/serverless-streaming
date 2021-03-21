#!/bin/sh

# Gcloud auth and configuration
gcloudConfig(){
  gcloud auth login
  gcloud config set project $PROJECT_ID
  gcloud config set run/platform managed
  gcloud config set run/region $REGION
}


# Producer API part
buildProducerApiAndDeployToCloudRun(){
  # build Producer API docker and push to GCR
  docker build --pull --rm -f "../api/Dockerfile" -t gcr.io/$PROJECT_ID/streaming-demo "../api"
  docker push gcr.io/$PROJECT_ID/streaming-demo

  # Create a role, service account to be used by cloud run porject, deploy a cloud run service
  gcloud iam roles create $ROLE_ID --project=$PROJECT_ID \
    --file=./cloud-run-role.yml
  gcloud iam service-accounts create $SERVICE_ACCOUNT_ID \
      --description="Cloud run service account" \
      --display-name="cloud-run-service-account"

  gcloud projects add-iam-policy-binding $PROJECT_ID \
      --member="serviceAccount:$SERVICE_ACCOUNT_ID@$PROJECT_ID.iam.gserviceaccount.com" \
      --role=$ROLE

  # Deploy to cloud run
  gcloud run deploy streaming-demo \
    --image gcr.io/$PROJECT_ID/streaming-demo \
    --service-account $SERVICE_ACCOUNT_ID@$PROJECT_ID.iam.gserviceaccount.com \
    --region=$REGION \
    --concurrency=3 \
    --max-instances=1 \
    --memory=256Mi \
    --port=8080 \
    --timeout=30 \
    --platform=managed \
    --allow-unauthenticated


}



# Consumer API part (ETL Job)
buildConsumerApiAndDeployToCloudRun(){
  # Build docker image and deploy to a another Cloud Run service
  docker build --pull --rm -f "../job/Dockerfile" -t gcr.io/$PROJECT_ID/streaming-demo-job "../job"
  docker push gcr.io/$PROJECT_ID/streaming-demo-job
  gcloud alpha run deploy streaming-demo-job \
    --image gcr.io/$PROJECT_ID/streaming-demo-job \
    --service-account $SERVICE_ACCOUNT_ID@$PROJECT_ID.iam.gserviceaccount.com \
    --region=$REGION \
    --concurrency=3 \
    --max-instances=2 \
    --memory=256Mi \
    --port=8080 \
    --timeout=600 \
    --platform=managed \
    --allow-unauthenticated \
    --set-env-vars "GCP_PUBSUB_SUBSCRIPTION=$PUBSUB_EVENTS_SUB" \
    --set-env-vars "GCP_TABLE_NAME=$TABLE_NAME" \
    --set-env-vars "GCP_DATASET_NAME=$DATASET_NAME" \
    --set-env-vars "GCP_PROJECT_ID=$PROJECT_ID" 

}

# Pub/Sub part
createPubSubTopicsAndSubscriptions(){

  export JOB_ENDPOINT_URL=$(gcloud run services describe streaming-demo-job --format='value(status.address.url)') 
  export JOB_ENDPOINT_URL+="/etl"
  # Create Pub/Sub Topic and Subscription to receceive tracking events, and to allow jobs pulling from Queue
  gcloud pubsub topics create $PUBSUB_EVENTS_TOPIC
  gcloud pubsub subscriptions create $PUBSUB_EVENTS_SUB --topic=$PUBSUB_EVENTS_TOPIC --ack-deadline=600

  # Create Pub/Sub Topic and Subscription to receceive alert messages to trigger jobs when Queue have new messages
  gcloud pubsub topics create $PUBSUB_INVOKE_TOPIC
  gcloud pubsub subscriptions create $PUBSUB_INVOKE_SUB \
    --topic=$PUBSUB_INVOKE_TOPIC \
    --push-endpoint=$JOB_ENDPOINT_URL \
    --ack-deadline=600


  ### 
}

# Create logs sink to redirect logs messages from Consumer API to Pub/Sub Queue
createLogsSink(){

  gcloud logging sinks create $SINK_NAME $SINK_LOCATION \
    --log-filter="jsonPayload.name=\"$LOG_NAME\"" --description="events sink"
  WRITTER_SERVICE_ACCOUNT=$(gcloud logging sinks describe $SINK_NAME --format="value(writerIdentity)")
  gcloud pubsub topics  add-iam-policy-binding $PUBSUB_EVENTS_TOPIC --member=$WRITTER_SERVICE_ACCOUNT --role=roles/pubsub.publisher
  # Please visit linke below to learn how to grant the writer service account a permission to write on Pub/Sub 
  # https://cloud.google.com/logging/docs/export/configure_export_v2#dest-auth

}

# Create Alert policy and Notification Channel 
createAlertPolicyAndNotificationChannel(){


  gcloud scheduler jobs create pubsub "Cron_ETL" \
  --schedule="*/3 * * * *" \
  --topic=projects/$PROJECT_ID/topics/$PUBSUB_INVOKE_TOPIC \
  --message-body="hello"

  # echo https://console.cloud.google.com/monitoring/alerting/policies/create?project=$PROJECT_ID
  # First is to create a condition, once condition was violated, an incident will get fired
  # Second is to set a channel to get notified when incident is started, 
  # in this case channel would be $PUBSUB_INVOKE_TOPIC topic
  # You must grant the service account used by cloud logging a role to be able to publish
  # messages on $PUBSUB_INVOKE_TOPIC topic

  # Create notification channel
  gcloud alpha monitoring channels create --display-name="Invoke ETL job" \
  --description="a channel to receive invoke triggers once queue have number of undelievred events" \
  --type=pubsub \
  --channel-labels=topic=projects/$PROJECT_ID/topics/$PUBSUB_INVOKE_TOPIC
  # echo https://console.cloud.google.com/monitoring/alerting/notification?project=$PROJECT_ID
  # grant google monitoring service account to publish on $PUBSUB_INVOKE_TOPIC
  # https://cloud.google.com/monitoring/support/notification-options#pubsub

  PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(project_number)")

  gcloud pubsub topics add-iam-policy-binding \
    projects/$PROJECT_NUMBER/topics/$PUBSUB_INVOKE_TOPIC --role=roles/pubsub.publisher \
    --member=serviceAccount:service-$PROJECT_NUMBER@gcp-sa-monitoring-notification.iam.gserviceaccount.com

  # Create alert policy
  gcloud alpha monitoring policies create --policy-from-file=policy.json
  POLICY=$(gcloud alpha monitoring policies list --filter='displayName="Run ETL jobs policy"' --format='value("name")')
  CHANNEL=$(gcloud alpha monitoring channels list --filter='displayName="Invoke ETL job"' --format='value("name")')
  gcloud alpha monitoring policies update $POLICY --add-notification-channels=$CHANNEL
  # Now policies and notification channel are ready 
  # once there are new messages in $PUBSUB_EVENTS_TOPIC
  # inciden will get trigger, and that cause ETL job to run
  # later ETL jobs will pull all events from queue
  # ETL jobs won't run until new events reach $PUBSUB_EVENTS_TOPIC
}

# Don't forget to clean up resources after you run this demo!
cleanUpResources(){
  gcloud alpha run services delete streaming-demo-job 
  gcloud alpha run services delete streaming-demo
  gcloud iam roles delete $ROLE_ID  --project=$PROJECT_ID 
  gcloud iam service-accounts delete $SERVICE_ACCOUNT_ID@$PROJECT_ID.iam.gserviceaccount.com 
  gcloud pubsub subscriptions delete $PUBSUB_EVENTS_SUB 
  gcloud pubsub topics delete $PUBSUB_EVENTS_TOPIC
  gcloud pubsub subscriptions delete $PUBSUB_INVOKE_SUB 
  gcloud pubsub topics delete $PUBSUB_INVOKE_TOPIC
  gcloud logging sinks delete $SINK_NAME
  POLICY=$(gcloud alpha monitoring policies list --filter='displayName="Run ETL jobs policy"' --format='value("name")')
  CHANNEL=$(gcloud alpha monitoring channels list --filter='displayName="Invoke ETL job"' --format='value("name")')
  gcloud alpha monitoring policies delete $POLICY
  gcloud alpha monitoring channels delete $CHANNEL
  gcloud scheduler jobs delete Cron_ETL

}

# Let us test Producer API + Consumer (ETL)
testProducerAndConsumer(){
  PRODUCER_ENDPOINT_URL=$(gcloud run services describe streaming-demo --format='value(status.address.url)') 
  PRODUCER_ENDPOINT_URL+="/receive"
  # We can use wrk to perform multiple HTTP requests asynchrnouns
  # Install from here: https://github.com/wg/wrk
  wrk -t4 -c10 -d10s -s request.lua $PRODUCER_ENDPOINT_URL
  # To view logs in browser, visit the linke below
  echo https://console.cloud.google.com/logs/query;query=jsonPayload.name:%20%22$LOG_NAME%22%0A;timeRange=PT1H?hl=en&project=$PROJECT_ID

}

gcloudConfig
buildProducerApiAndDeployToCloudRun
buildConsumerApiAndDeployToCloudRun
createPubSubTopicsAndSubscriptions
createLogsSink
createAlertPolicyAndNotificationChannel
testProducerAndConsumer
#cleanUpResources

