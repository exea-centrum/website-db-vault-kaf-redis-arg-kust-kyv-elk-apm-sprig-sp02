package com.davtro.rental;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.kafka.annotation.EnableKafka;
@SpringBootApplication @EnableKafka
public class RentalProcessorApplication {
    public static void main(String[] args) { SpringApplication.run(RentalProcessorApplication.class, args); }
}
