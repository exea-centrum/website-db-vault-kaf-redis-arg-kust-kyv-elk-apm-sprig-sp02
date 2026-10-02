FROM apache/spark:3.5.0
COPY target/scala-2.12/davtro-spark-jobs-assembly-1.0.0.jar /opt/spark/jobs/
CMD ["/opt/spark/bin/spark-submit","--class","com.davtro.jobs.MarketingAnalyticsJob","/opt/spark/jobs/davtro-spark-jobs-assembly-1.0.0.jar"]
