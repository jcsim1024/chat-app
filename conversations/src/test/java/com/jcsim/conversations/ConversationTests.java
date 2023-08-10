package com.jcsim.chatapp;

import org.apache.kafka.clients.consumer.Consumer;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.apache.kafka.clients.consumer.ConsumerRecords;
import org.apache.kafka.clients.consumer.KafkaConsumer;
import org.apache.kafka.clients.producer.KafkaProducer;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.time.Duration;
import java.util.Collections;
import java.util.Properties;

@SpringBootTest
class ChatappApplicationTests {

    private static final String BOOTSTRAP_SERVERS = "localhost:19093";
    private static final String TOPIC = "test-topic";



    @BeforeAll
    static void beforeAll(){
        // verify that zookeeper and brokers are running
        try {
            // Specify the shell command in an array
            // so the ProcessBuilder treats the entire string as the command to execute
            String[] shellCommand = {"/bin/bash", "-c", "source streaming/start-brokers.sh && wait_for_zookeeper_and_kafka"};

            // Create and start the process
            ProcessBuilder processBuilder = new ProcessBuilder(shellCommand);
            Process process = processBuilder.start();
            // Read the process output
            BufferedReader reader = new BufferedReader(new InputStreamReader(process.getInputStream()));
            String line;
            while ((line = reader.readLine()) != null) {
                System.out.println("start-brokers.sh Output: " + line);
            }


            // Wait for the process to complete and get the exit code
            int exitCode = process.waitFor();
            System.out.println("Exit code: " + exitCode);
            assert exitCode == 0;
        } catch (IOException | InterruptedException e) {
            e.printStackTrace();
        }
    }
    @Test
    void contextLoads() {

        // Create the producer
        Properties producerProps = new Properties();
        producerProps.put("bootstrap.servers", BOOTSTRAP_SERVERS);
        producerProps.put("key.serializer", "org.apache.kafka.common.serialization.StringSerializer");
        producerProps.put("value.serializer", "org.apache.kafka.common.serialization.StringSerializer");

        KafkaProducer<String, String> producer = new KafkaProducer<>(producerProps);

        //send a 2M byte message filled with "1_"
        String testMessage = new String(new char[1024 * 10]).replace("\0", "1_");

        ProducerRecord<String, String> record = new ProducerRecord<>(TOPIC, "1",testMessage);
        producer.send(record);
        producer.partitionsFor(TOPIC).forEach(partitionInfo -> {
            System.out.println("Partition: " + partitionInfo.partition() + " Leader: " + partitionInfo.leader().toString());
        });
        // Close the producer
        producer.close();
        // access producer metadata
        // sleep for 1 second to allow the producer to complete
        try {
            Thread.sleep(3000);
        } catch (InterruptedException e) {
            e.printStackTrace();
        }


        // Create a consumer for each broker
        for (int i = 0; i < 3; i++) {
            Properties consumerProps = new Properties();
            consumerProps.put("bootstrap.servers", BOOTSTRAP_SERVERS);
            consumerProps.put("key.deserializer", "org.apache.kafka.common.serialization.StringDeserializer");
            consumerProps.put("value.deserializer", "org.apache.kafka.common.serialization.StringDeserializer");
            consumerProps.put("group.id", "test-consumer-group" + i);

            Consumer<String, String> consumer = new KafkaConsumer<>(consumerProps);

            // Subscribe to the topic
            consumer.subscribe(Collections.singletonList(TOPIC));

            // Consume the test message
            ConsumerRecords<String, String> records = consumer.poll(Duration.ofSeconds(1));
            for (ConsumerRecord<String, String> rec : records) {
                assert records.count() == 1;
                assert rec.value().equals(testMessage);
            }

            // Close the consumer
            consumer.close();
        }
    }
}