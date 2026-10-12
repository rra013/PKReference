package com.pkreference.backend.config;

import org.apache.kafka.common.TopicPartition;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.kafka.core.KafkaOperations;
import org.springframework.kafka.listener.CommonErrorHandler;
import org.springframework.kafka.listener.DeadLetterPublishingRecoverer;
import org.springframework.kafka.listener.DefaultErrorHandler;
import org.springframework.util.backoff.FixedBackOff;

/**
 * What happens when a {@code @KafkaListener} method throws.
 *
 * <p>By default Spring Kafka retries a failed record a few times and then skips it, logging the error:
 * the data is lost quietly. This class replaces that with "retry, then park it where it can be
 * found". Spring Boot gives the one {@code CommonErrorHandler} bean in the context to every
 * listener container it builds, so declaring the bean is all the wiring there is.
 */
@Configuration
public class KafkaErrorHandling {

    /**
     * Retry 3 times, 2 seconds apart (four attempts in all), then publish the record to
     * {@code <topic>.DLT}, same partition, and move on. The dead-letter record carries the original
     * value plus headers saying which exception failed it.
     *
     * <p>{@code template} is Spring Boot's auto-configured KafkaTemplate, injected as this method's
     * parameter: a {@code @Bean} method's parameters are filled in from the context like a
     * constructor's.
     */
    @Bean
    CommonErrorHandler kafkaErrorHandler(KafkaOperations<Object, Object> template) {
        var recoverer = new DeadLetterPublishingRecoverer(template,
                (record, ex) -> new TopicPartition(record.topic() + ".DLT", record.partition()));
        return new DefaultErrorHandler(recoverer, new FixedBackOff(2000L, 3));
    }
}
