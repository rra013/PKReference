package com.pkreference.backend.config;

import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;

/**
 * Waits for a Kafka send, so a failure (a record over the topic's size limit, the broker down)
 * throws where it happened. KafkaTemplate.send only returns a future: unread, a failed send was
 * logged and the event lost, while the listener committed its offset.
 */
public final class KafkaSends {
    private static final long TIMEOUT_SECONDS = 30;

    private KafkaSends() {}

    public static <T> T await(CompletableFuture<T> send) {
        try {
            return send.get(TIMEOUT_SECONDS, TimeUnit.SECONDS);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Interrupted waiting for a Kafka send", e);
        } catch (ExecutionException e) {
            throw new IllegalStateException("Kafka send failed", e.getCause());
        } catch (TimeoutException e) {
            throw new IllegalStateException("Kafka send timed out after " + TIMEOUT_SECONDS + "s", e);
        }
    }
}
