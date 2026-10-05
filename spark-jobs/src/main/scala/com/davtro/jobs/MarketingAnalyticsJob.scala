package com.davtro.jobs
import org.apache.spark.sql.SparkSession
import org.apache.spark.sql.functions._
import org.apache.spark.sql.streaming.Trigger
object MarketingAnalyticsJob {
  def main(args: Array[String]): Unit = {
    val spark = SparkSession.builder().appName("DavTro Marketing Analytics").master("spark://spark-master:7077").config("spark.sql.streaming.checkpointLocation", "/tmp/checkpoint").getOrCreate()
    import spark.implicits._
    val kafkaDF = spark.readStream.format("kafka").option("kafka.bootstrap.servers", "kafka-kraft:9092").option("subscribe", "marketing-actions").option("startingOffsets", "latest").load()
    val parsedDF = kafkaDF.selectExpr("CAST(value AS STRING) as json").select(from_json($"json", new org.apache.spark.sql.types.StructType().add("event", "string").add("property_id", "integer").add("guest_email", "string").add("booking_value", "double").add("timestamp", "string")).as("data")).select("data.*")
    val aggDF = parsedDF.withWatermark("timestamp", "10 minutes").groupBy(window($"timestamp", "5 minutes"), $"property_id").agg(count("*").as("booking_count"), sum("booking_value").as("total_revenue"), avg("booking_value").as("avg_booking_value"))
    val query = aggDF.writeStream.outputMode("update").format("console").trigger(Trigger.ProcessingTime("10 seconds")).start()
    val jdbcDF = parsedDF.writeStream.foreachBatch { (batchDF: org.apache.spark.sql.Dataset[org.apache.spark.sql.Row], batchId: Long) => batchDF.write.format("jdbc").option("url", "jdbc:postgresql://postgres-db:5432/davtro_rentals").option("dbtable", "marketing_events").option("user", "davtro").option("password", "changeme").mode("append").save() }.start()
    query.awaitTermination(); jdbcDF.awaitTermination()
  }
}
