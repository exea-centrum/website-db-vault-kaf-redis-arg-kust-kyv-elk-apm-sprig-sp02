package com.davtro.jobs
import org.apache.spark.sql.SparkSession
import org.apache.spark.sql.functions._
import org.apache.spark.sql.streaming.Trigger
object MarketingAnalyticsJob {
  def main(args: Array[String]): Unit = {
    // Konfiguracja z ENV (bez hardcode'owanych adresow/hasel).
    // Domyslne wartosci zgodne z nazwami Service w manifests/base:
    //   kafka-kraft, postgres-clusterip, spark-master-svc.
    // FIX: wczesniej bylo "postgres-db" (takiej uslugi NIE ma -> Job sie wywalal),
    // "spark://spark-master:7077" (usluga nazywa sie spark-master-svc) oraz
    // zahardcode'owane user/password (davtro/changeme) zamiast credsy z Vaulta.
    val masterUrl = sys.env.getOrElse("SPARK_MASTER_URL", "spark://spark-master-svc:7077")
    val kafkaBootstrap = sys.env.getOrElse("KAFKA_BOOTSTRAP_SERVERS", "kafka-kraft:9092")
    val pgUrl = sys.env.getOrElse("DB_URL", "jdbc:postgresql://postgres-clusterip:5432/davtro_rentals")
    val pgUser = sys.env.getOrElse("DB_USER", "davtro")
    val pgPassword = sys.env.getOrElse("DB_PASSWORD", "")
    val checkpointLocation = sys.env.getOrElse("SPARK_CHECKPOINT_LOCATION", "/tmp/checkpoint")

    val spark = SparkSession.builder().appName("DavTro Marketing Analytics").master(masterUrl).config("spark.sql.streaming.checkpointLocation", checkpointLocation).getOrCreate()
    import spark.implicits._
    val kafkaDF = spark.readStream.format("kafka").option("kafka.bootstrap.servers", kafkaBootstrap).option("subscribe", "marketing-actions").option("startingOffsets", "latest").load()
    val parsedDF = kafkaDF.selectExpr("CAST(value AS STRING) as json").select(from_json($"json", new org.apache.spark.sql.types.StructType().add("event", "string").add("property_id", "integer").add("guest_email", "string").add("booking_value", "double").add("timestamp", "string")).as("data")).select("data.*")
    val aggDF = parsedDF.withWatermark("timestamp", "10 minutes").groupBy(window($"timestamp", "5 minutes"), $"property_id").agg(count("*").as("booking_count"), sum("booking_value").as("total_revenue"), avg("booking_value").as("avg_booking_value"))
    val query = aggDF.writeStream.outputMode("update").format("console").trigger(Trigger.ProcessingTime("10 seconds")).start()
    val jdbcDF = parsedDF.writeStream.foreachBatch { (batchDF: org.apache.spark.sql.Dataset[org.apache.spark.sql.Row], batchId: Long) => batchDF.write.format("jdbc").option("url", pgUrl).option("dbtable", "marketing_events").option("user", pgUser).option("password", pgPassword).mode("append").save() }.start()
    query.awaitTermination(); jdbcDF.awaitTermination()
  }
}
